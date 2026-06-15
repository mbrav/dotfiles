#!/usr/bin/env python3
"""
agent.py — tmux-agents-codex management CLI

Subcommands:
  spawn     <task> <prompt>       spawn a Codex subagent pane
  pane-id   <task>                resolve task name → tmux pane ID
  prompt    <task> <text>         send a follow-up prompt to a running agent pane
  result    <task> [--wait]       read last complete response from JSONL log
  ping      <task>                check if a new response is ready (timestamp only)
  resurrect <task> <session-id>   bring back a cleaned-up agent by session UUID
  status                          list pane IDs and titles in current agents window
  cleanup   <task|--all>          kill one or all agent panes
"""

import argparse
import json
import os
import re
import shlex
import subprocess
import sys
import time
import uuid
from datetime import datetime, timezone
from pathlib import Path

CODEX_SESSIONS_ROOT = Path.home() / ".codex" / "sessions"
TASK_OPTION = "@tmux_agents_task"
TASK_COMPLETE_VALUE = b'"task_complete"'
TASK_COMPLETE_TYPE_RE = re.compile(
    rb'"payload"\s*:\s*\{\s*"type"\s*:\s*"task_complete"'
)
TIMESTAMP_RE = re.compile(rb'"timestamp"\s*:\s*"([^"]+)"')


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------


def get_win() -> str:
    win = os.environ.get("TMUX_WIN")
    if win:
        return win
    return subprocess.check_output(
        ["tmux", "display-message", "-p", "#{window_name}"], text=True
    ).strip()


def statefile(win: str, task: str) -> Path:
    return Path(f"/tmp/tmux-codex-{win}-{task}.json")


def load_state(win: str, task: str) -> dict:
    sf = statefile(win, task)
    if not sf.exists():
        print(f"No state file found for task: {task}", file=sys.stderr)
        sys.exit(1)
    return json.loads(sf.read_text())


def save_state(win: str, task: str, state: dict) -> None:
    statefile(win, task).write_text(json.dumps(state, sort_keys=True))


def tmux(*args: str) -> subprocess.CompletedProcess:
    return subprocess.run(["tmux", *args], check=True, text=True)


def tmux_out(*args: str) -> str:
    return subprocess.check_output(["tmux", *args], text=True).strip()


def tag_pane(pane_id: str, task: str) -> None:
    tmux("set-option", "-p", "-t", pane_id, TASK_OPTION, task)


def resolve_pane_id(win: str, task: str) -> str:
    sf = statefile(win, task)
    if sf.exists():
        pane_id = json.loads(sf.read_text())["pane_id"]
        live = tmux_out("list-panes", "-t", f"agents:{win}", "-F", "#{pane_id}")
        if pane_id in live.splitlines():
            return pane_id

    # Fallback: search by stable pane option first, then mutable terminal title.
    lines = tmux_out(
        "list-panes",
        "-t",
        f"agents:{win}",
        "-F",
        "#{pane_id}\t#{@tmux_agents_task}\t#{pane_title}",
    ).splitlines()
    for line in lines:
        parts = line.split("\t", 2)
        if len(parts) == 3 and task in (parts[1], parts[2]):
            return parts[0]

    print(f"pane not found: {task}", file=sys.stderr)
    sys.exit(1)


def codex_sessions_today() -> Path:
    """Return today's codex sessions directory."""
    now = datetime.now()
    return CODEX_SESSIONS_ROOT / str(now.year) / f"{now.month:02d}" / f"{now.day:02d}"


def find_jsonl_by_session_id(session_id: str) -> Path | None:
    """Search the date-partitioned Codex session tree by UUID."""
    if not session_id or session_id.startswith("unknown-"):
        return None
    if not CODEX_SESSIONS_ROOT.exists():
        return None

    pattern = f"*{session_id}.jsonl"
    for jsonl in sorted(CODEX_SESSIONS_ROOT.glob(f"*/*/*/{pattern}"), reverse=True):
        return jsonl

    # Fallback for any future layout change.
    for jsonl in sorted(CODEX_SESSIONS_ROOT.rglob(pattern), reverse=True):
        return jsonl
    return None


def parse_json_line(line: bytes) -> dict | None:
    try:
        return json.loads(line)
    except (json.JSONDecodeError, UnicodeDecodeError):
        return None


def session_meta(jsonl: Path) -> dict | None:
    """Read only the session_meta record from a Codex JSONL file."""
    try:
        with jsonl.open("rb") as f:
            for line in f:
                if b'"session_meta"' not in line:
                    continue
                record = parse_json_line(line)
                if record and record.get("type") == "session_meta":
                    payload = record.get("payload", {})
                    return payload if isinstance(payload, dict) else None
    except OSError:
        return None
    return None


def detect_new_session(
    before_files: set[Path], cwd: str, timeout: float = 15.0
) -> tuple[str, Path] | None:
    """
    Poll today's sessions dir until a new JSONL appears.
    Returns the session UUID and JSONL path, or None on timeout.
    """
    sessions_dir = codex_sessions_today()
    deadline = time.monotonic() + timeout
    fallback: tuple[str, Path] | None = None
    while time.monotonic() < deadline:
        time.sleep(0.5)
        try:
            current = set(sessions_dir.glob("*.jsonl"))
        except FileNotFoundError:
            continue
        new_files = current - before_files
        for f in sorted(new_files, key=lambda p: p.stat().st_mtime, reverse=True):
            meta = session_meta(f)
            if meta is None:
                continue
            sid = meta.get("id")
            if sid:
                if meta.get("cwd") == cwd:
                    return sid, f
                fallback = fallback or (sid, f)
        if fallback:
            return fallback
    return None


def resolve_jsonl(state: dict) -> Path | None:
    """Return a usable JSONL path, preferring the cached path in state."""
    cached = state.get("jsonl_path")
    if cached:
        jsonl = Path(cached).expanduser()
        if jsonl.exists():
            return jsonl

    jsonl = find_jsonl_by_session_id(state.get("session_id", ""))
    if jsonl:
        state["jsonl_path"] = str(jsonl)
    return jsonl


def now_iso() -> str:
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%S.%f")[:-3] + "Z"


def parse_iso(ts: str) -> datetime:
    return datetime.fromisoformat(ts.replace("Z", "+00:00"))


def iso_from_epoch(value: int | float) -> str:
    seconds = value / 1000 if value > 10_000_000_000 else value
    return (
        datetime.fromtimestamp(seconds, timezone.utc)
        .isoformat(timespec="milliseconds")
        .replace("+00:00", "Z")
    )


def task_complete_timestamp(record: dict) -> str | None:
    ts = record.get("timestamp")
    if isinstance(ts, str):
        return ts

    completed_at = record.get("payload", {}).get("completed_at")
    if isinstance(completed_at, (int, float)):
        return iso_from_epoch(completed_at)
    return None


def task_complete_record(line: bytes) -> dict | None:
    if TASK_COMPLETE_VALUE not in line:
        return None

    record = parse_json_line(line)
    if not record or record.get("type") != "event_msg":
        return None

    payload = record.get("payload", {})
    if payload.get("type") != "task_complete":
        return None
    return record


def task_complete_timestamp_from_line(line: bytes) -> str | None:
    if TASK_COMPLETE_TYPE_RE.search(line):
        match = TIMESTAMP_RE.search(line)
        if match:
            return match.group(1).decode("utf-8", "replace")

    record = task_complete_record(line)
    if record:
        return task_complete_timestamp(record)
    return None


def scan_task_completions(jsonl: Path, state: dict) -> None:
    """
    Advance the cached scan offset and remember the last task_complete line.

    Ping uses this path without JSON-decoding the final response text. Result can
    later seek directly to last_complete_offset and decode just that one record.
    """
    if not jsonl.exists():
        return

    try:
        start = int(state.get("scan_offset", 0) or 0)
    except (TypeError, ValueError):
        start = 0

    size = jsonl.stat().st_size
    if start < 0 or start > size:
        start = 0

    offset = start
    with jsonl.open("rb") as f:
        f.seek(start)
        while True:
            line_start = f.tell()
            line = f.readline()
            if not line:
                offset = f.tell()
                break
            if not line.endswith(b"\n"):
                offset = line_start
                break

            offset = f.tell()
            if TASK_COMPLETE_VALUE not in line:
                continue

            ts = task_complete_timestamp_from_line(line)
            if ts:
                state["last_complete_at"] = ts
                state["last_complete_offset"] = line_start

    state["scan_offset"] = offset


def has_fresh_response(state: dict) -> bool:
    sent_at = state.get("sent_at")
    completed_at = state.get("last_complete_at")
    if not sent_at or not completed_at:
        return False
    try:
        return parse_iso(completed_at) > parse_iso(sent_at)
    except ValueError:
        return False


def response_from_offset(jsonl: Path, offset: int) -> str | None:
    try:
        with jsonl.open("rb") as f:
            f.seek(offset)
            line = f.readline()
    except OSError:
        return None

    record = task_complete_record(line)
    if record is None:
        return None

    message = record.get("payload", {}).get("last_agent_message")
    return message if isinstance(message, str) and message else None


def extract_last_response(jsonl: Path, sent_at: str | None = None) -> str | None:
    """Fallback full scan for old state files without cached offsets."""
    if not jsonl.exists():
        return None

    sent_dt = parse_iso(sent_at) if sent_at else None
    last_text = None
    try:
        with jsonl.open("rb") as f:
            for line in f:
                record = task_complete_record(line)
                if record is None:
                    continue
                ts = task_complete_timestamp(record)
                if sent_dt and (not ts or parse_iso(ts) <= sent_dt):
                    continue
                message = record.get("payload", {}).get("last_agent_message")
                if isinstance(message, str) and message:
                    last_text = message
    except OSError:
        return None
    return last_text


def response_from_state(jsonl: Path, state: dict) -> str | None:
    offset = state.get("last_complete_offset")
    if offset is not None:
        try:
            result = response_from_offset(jsonl, int(offset))
        except (TypeError, ValueError):
            result = None
        if result is not None:
            return result

    return extract_last_response(jsonl, state.get("sent_at"))


# ---------------------------------------------------------------------------
# Subcommands
# ---------------------------------------------------------------------------


def cmd_spawn(args: argparse.Namespace) -> None:
    win = get_win()
    target = f"agents:{win}"
    cwd = os.getcwd()

    # Ensure the agents session and target window exist
    try:
        existing = subprocess.check_output(
            ["tmux", "list-windows", "-t", "agents", "-F", "#{window_name}"],
            text=True,
            stderr=subprocess.DEVNULL,
        ).strip()
        if win not in existing.splitlines():
            tmux("new-window", "-t", "agents", "-n", win)
    except subprocess.CalledProcessError:
        tmux("new-session", "-d", "-s", "agents", "-n", win)

    # Split a new pane (detached, preserving focus)
    pane_id = tmux_out("split-window", "-t", target, "-d", "-P", "-F", "#{pane_id}")

    # Name the pane
    tmux("select-pane", "-t", pane_id, "-T", args.task)
    tag_pane(pane_id, args.task)

    # Snapshot current sessions before spawning so we can detect the new one
    sessions_dir = codex_sessions_today()
    sessions_dir.mkdir(parents=True, exist_ok=True)
    before_files = set(sessions_dir.glob("*.jsonl"))

    # Side-by-side horizontal layout: | Agent 1 | Agent 2 | Agent 3 |
    tmux("select-layout", "-t", target, "even-horizontal")

    # Launch Codex
    sent_at = now_iso()
    tmux("send-keys", "-t", pane_id, "-l", shlex.join(["codex", args.prompt]))
    tmux("send-keys", "-t", pane_id, "Enter")

    # Detect new session ID from the JSONL file that codex creates
    print("Waiting for Codex session to start...", file=sys.stderr)
    detected = detect_new_session(before_files, cwd, timeout=15.0)
    session_id = None
    jsonl_path = None
    if detected:
        session_id, jsonl_path = detected

    if not session_id:
        print(
            "Warning: could not detect session ID within 15s. State file incomplete.",
            file=sys.stderr,
        )
        session_id = "unknown-" + str(uuid.uuid4())[:8]

    state = {
        "pane_id": pane_id,
        "session_id": session_id,
        "cwd": cwd,
        "sent_at": sent_at,
    }
    if jsonl_path:
        state["jsonl_path"] = str(jsonl_path)

    save_state(win, args.task, state)

    print(f"Spawned '{args.task}' in pane {pane_id} ({target}) [session: {session_id}]")


def cmd_pane_id(args: argparse.Namespace) -> None:
    win = get_win()
    print(resolve_pane_id(win, args.task))


def cmd_prompt(args: argparse.Namespace) -> None:
    win = get_win()
    pane_id = resolve_pane_id(win, args.task)
    tmux("send-keys", "-t", pane_id, "-l", args.text)
    tmux("send-keys", "-t", pane_id, "Enter")
    # Update sent_at so ping knows to wait for a fresh response
    sf = statefile(win, args.task)
    if sf.exists():
        state = json.loads(sf.read_text())
        state["sent_at"] = now_iso()
        save_state(win, args.task, state)


def cmd_result(args: argparse.Namespace) -> None:
    win = get_win()
    sf = statefile(win, args.task)
    state = load_state(win, args.task)
    session_id = state["session_id"]
    jsonl = resolve_jsonl(state)

    if jsonl is None:
        print(
            f"JSONL not found for session {session_id}",
            file=sys.stderr,
        )
        sys.exit(1)

    if args.wait:
        print(
            f"Waiting for response from '{args.task}' (session: {session_id})...",
            file=sys.stderr,
        )

    while True:
        scan_task_completions(jsonl, state)
        sf.write_text(json.dumps(state, sort_keys=True))

        if has_fresh_response(state):
            result = response_from_state(jsonl, state)
            if result is not None:
                print(result)
                return

        if not args.wait:
            print(
                f"No fresh complete response yet for task '{args.task}' "
                f"(session: {session_id})",
                file=sys.stderr,
            )
            sys.exit(1)

        time.sleep(2)


def cmd_ping(args: argparse.Namespace) -> None:
    win = get_win()
    sf = statefile(win, args.task)
    if not sf.exists():
        print("no session")
        sys.exit(1)

    state = json.loads(sf.read_text())
    sent_at_str = state.get("sent_at")
    if not sent_at_str:
        print("thinking")
        return

    jsonl = resolve_jsonl(state)

    if jsonl is None:
        print("thinking")
        return

    scan_task_completions(jsonl, state)
    sf.write_text(json.dumps(state, sort_keys=True))

    if has_fresh_response(state):
        print("ready")
    else:
        print("thinking")


def cmd_resurrect(args: argparse.Namespace) -> None:
    """Bring back a cleaned-up agent using its known session UUID."""
    win = get_win()
    target = f"agents:{win}"
    session_id = args.session_id

    # Ensure agents session and window exist
    try:
        existing = subprocess.check_output(
            ["tmux", "list-windows", "-t", "agents", "-F", "#{window_name}"],
            text=True,
            stderr=subprocess.DEVNULL,
        ).strip()
        if win not in existing.splitlines():
            tmux("new-window", "-t", "agents", "-n", win)
    except subprocess.CalledProcessError:
        tmux("new-session", "-d", "-s", "agents", "-n", win)

    pane_id = tmux_out("split-window", "-t", target, "-d", "-P", "-F", "#{pane_id}")
    tmux("select-pane", "-t", pane_id, "-T", args.task)
    tag_pane(pane_id, args.task)
    tmux("select-layout", "-t", target, "even-horizontal")

    tmux("send-keys", "-t", pane_id, "-l", shlex.join(["codex", "resume", session_id]))
    tmux("send-keys", "-t", pane_id, "Enter")

    state = {
        "pane_id": pane_id,
        "session_id": session_id,
        "cwd": os.getcwd(),
        "sent_at": now_iso(),
    }
    jsonl = resolve_jsonl(state)
    if jsonl:
        state["jsonl_path"] = str(jsonl)
    save_state(win, args.task, state)
    print(f"Resurrected '{args.task}' in pane {pane_id} (session: {session_id})")


def cmd_status(args: argparse.Namespace) -> None:
    win = get_win()
    lines = subprocess.check_output(
        [
            "tmux",
            "list-panes",
            "-t",
            f"agents:{win}",
            "-F",
            "#{pane_id}\t#{@tmux_agents_task}\t#{pane_title}",
        ],
        text=True,
        stderr=subprocess.DEVNULL,
    ).strip()
    if lines:
        for line in lines.splitlines():
            pane_id, task, title = line.split("\t", 2)
            print(f"{pane_id}  {task or title}")


def cmd_cleanup(args: argparse.Namespace) -> None:
    win = get_win()

    if args.all:
        for sf in Path("/tmp").glob(f"tmux-codex-{win}-*.json"):
            state = json.loads(sf.read_text())
            pane_id = state["pane_id"]
            task = sf.stem.removeprefix(f"tmux-codex-{win}-")
            result = subprocess.run(["tmux", "kill-pane", "-t", pane_id])
            if result.returncode == 0:
                print(f"Killed pane {pane_id} ({task})")
            sf.unlink()
    else:
        pane_id = resolve_pane_id(win, args.task)
        tmux("kill-pane", "-t", pane_id)
        statefile(win, args.task).unlink(missing_ok=True)
        print(f"Killed pane {pane_id} ({args.task})")


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------


def main() -> None:
    parser = argparse.ArgumentParser(
        prog="agent.py",
        description="tmux-agents-codex management CLI",
        epilog="2026 github.com/mbrav",
    )
    sub = parser.add_subparsers(dest="cmd", required=True)

    p_spawn = sub.add_parser("spawn", help="spawn a Codex subagent pane")
    p_spawn.add_argument("task", help="task name (used for pane title and state file)")
    p_spawn.add_argument("prompt", help="prompt to pass to codex")

    p_pane = sub.add_parser("pane-id", help="resolve task name to tmux pane ID")
    p_pane.add_argument("task")

    p_prompt = sub.add_parser("prompt", help="send a follow-up prompt to an agent pane")
    p_prompt.add_argument("task")
    p_prompt.add_argument("text")

    p_result = sub.add_parser(
        "result", help="read last complete response from JSONL log"
    )
    p_result.add_argument("task")
    p_result.add_argument(
        "--wait", action="store_true", help="poll until response arrives"
    )

    p_resurrect = sub.add_parser(
        "resurrect", help="bring back a cleaned-up agent by session UUID"
    )
    p_resurrect.add_argument("task", help="task name to restore")
    p_resurrect.add_argument("session_id", help="session UUID from the original spawn")

    sub.add_parser("status", help="list pane IDs and titles in current agents window")

    p_ping = sub.add_parser(
        "ping", help="check if a new response is ready (no result text)"
    )
    p_ping.add_argument("task")

    p_clean = sub.add_parser("cleanup", help="kill one or all agent panes")
    p_clean_grp = p_clean.add_mutually_exclusive_group(required=True)
    p_clean_grp.add_argument("task", nargs="?", help="task name to kill")
    p_clean_grp.add_argument(
        "--all", action="store_true", help="kill all tracked panes"
    )

    args = parser.parse_args()

    dispatch = {
        "spawn": cmd_spawn,
        "pane-id": cmd_pane_id,
        "prompt": cmd_prompt,
        "result": cmd_result,
        "resurrect": cmd_resurrect,
        "status": cmd_status,
        "ping": cmd_ping,
        "cleanup": cmd_cleanup,
    }
    dispatch[args.cmd](args)


if __name__ == "__main__":
    main()
