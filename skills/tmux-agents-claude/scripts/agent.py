#!/usr/bin/env python3
"""
agent.py — tmux-agents-claude management CLI

Subcommands:
  spawn   <task> <prompt>       spawn a Claude subagent pane
  pane-id <task>                resolve task name → tmux pane ID
  send    <task> <text>         send text to a running agent pane
  result  <task> [--wait]       read last complete response from JSONL log
  cleanup <task|--all>          kill one or all agent panes
"""

import argparse
import json
import os
import shlex
import subprocess
import sys
import time
import uuid
from datetime import datetime, timezone
from pathlib import Path


# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

MODELS = [
    # Claude 4
    "claude-opus-4-7",
    "claude-opus-4-5",
    "claude-sonnet-4-6",
    "claude-sonnet-4-5",
    "claude-haiku-4-5-20251001",
]

EFFORT_LEVELS = ["low", "medium", "high", "xhigh", "max", "auto"]


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------


def get_win() -> str:
    """Return current tmux window name via tmux query."""
    return subprocess.check_output(
        ["tmux", "display-message", "-p", "#{window_name}"], text=True
    ).strip()


def statefile(win: str, task: str) -> Path:
    """Return path to the JSON state file for a task."""
    return Path(f"/tmp/tmux-claude-{win}-{task}.json")


def load_state(win: str, task: str) -> dict:
    """Load and return task state dict; exit 1 if missing."""
    sf = statefile(win, task)
    if not sf.exists():
        print(f"No state file found for task: {task}", file=sys.stderr)
        sys.exit(1)
    return json.loads(sf.read_text())


def tmux(*args: str) -> subprocess.CompletedProcess:
    """Run a tmux command, raising on non-zero exit."""
    return subprocess.run(["tmux", *args], check=True, text=True)


def tmux_out(*args: str) -> str:
    """Run a tmux command and return its stripped stdout."""
    return subprocess.check_output(["tmux", *args], text=True).strip()


def resolve_pane_id(win: str, task: str) -> str:
    """Return pane ID for task: JSON state file first, pane-title fallback."""
    sf = statefile(win, task)
    if sf.exists():
        pane_id = json.loads(sf.read_text())["pane_id"]
        live = tmux_out("list-panes", "-t", f"agents:{win}", "-F", "#{pane_id}")
        if pane_id in live.splitlines():
            return pane_id

    # Fallback: search by pane title
    lines = tmux_out(
        "list-panes", "-t", f"agents:{win}", "-F", "#{pane_id} #{pane_title}"
    ).splitlines()
    for line in lines:
        parts = line.split(None, 1)
        if len(parts) == 2 and parts[1] == task:
            return parts[0]

    print(f"pane not found: {task}", file=sys.stderr)
    sys.exit(1)


def jsonl_path(state: dict) -> Path:
    """Derive the Claude JSONL transcript path from state dict."""
    cwd = state.get("cwd", os.getcwd())
    project_dir = cwd.replace("/", "-").replace(".", "-")
    return (
        Path.home()
        / ".claude"
        / "projects"
        / project_dir
        / f"{state['session_id']}.jsonl"
    )


def now_iso() -> str:
    """Return current UTC time as millisecond-precision ISO 8601 string."""
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%S.%f")[:-3] + "Z"


def parse_iso(ts: str) -> datetime:
    """Parse an ISO 8601 timestamp string into a timezone-aware datetime."""
    return datetime.fromisoformat(ts.replace("Z", "+00:00"))


def last_end_turn_timestamp(jsonl: Path) -> datetime | None:
    """Return the timestamp of the last end_turn assistant record, or None."""
    if not jsonl.exists():
        return None
    last_ts = None
    with open(jsonl) as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            try:
                record = json.loads(line)
            except json.JSONDecodeError:
                continue
            if record.get("type") != "assistant":
                continue
            if record.get("message", {}).get("stop_reason") != "end_turn":
                continue
            ts = record.get("timestamp")
            if ts:
                last_ts = parse_iso(ts)
    return last_ts


def extract_last_response(jsonl: Path) -> str | None:
    """Return text of the last end_turn assistant message in the JSONL log, or None."""
    if not jsonl.exists():
        return None
    last_text = None
    with open(jsonl) as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            try:
                record = json.loads(line)
            except json.JSONDecodeError:
                continue
            if record.get("type") != "assistant":
                continue
            msg = record.get("message", {})
            if msg.get("stop_reason") != "end_turn":
                continue
            texts = [
                c["text"]
                for c in msg.get("content", [])
                if isinstance(c, dict) and c.get("type") == "text"
            ]
            if texts:
                last_text = "\n".join(texts)
    return last_text


# ---------------------------------------------------------------------------
# Subcommands
# ---------------------------------------------------------------------------


def cmd_spawn(args: argparse.Namespace) -> None:
    """Spawn a new Claude subagent pane in the agents session."""
    win = get_win()
    target = f"agents:{win}"

    # Ensure the agents session and target window exist
    session_exists = (
        subprocess.run(
            ["tmux", "has-session", "-t", "agents"], capture_output=True
        ).returncode
        == 0
    )
    fresh_window = False
    if not session_exists:
        tmux("new-session", "-d", "-s", "agents", "-n", win)
        fresh_window = True
    elif (
        win
        not in tmux_out(
            "list-windows", "-t", "agents", "-F", "#{window_name}"
        ).splitlines()
    ):
        tmux("new-window", "-t", "agents", "-n", win)
        fresh_window = True

    # Use the initial pane if the window was just created, otherwise split
    if fresh_window:
        pane_id = tmux_out("list-panes", "-t", target, "-F", "#{pane_id}")
    else:
        pane_id = tmux_out("split-window", "-t", target, "-d", "-P", "-F", "#{pane_id}")

    # Name the pane
    tmux("select-pane", "-t", pane_id, "-T", args.task)

    # Generate session ID and write state
    session_id = str(uuid.uuid4())
    state = {
        "pane_id": pane_id,
        "session_id": session_id,
        "cwd": os.getcwd(),
        "sent_at": now_iso(),
    }
    statefile(win, args.task).write_text(json.dumps(state))

    # Side-by-side horizontal layout: | Agent 1 | Agent 2 | Agent 3 |
    tmux("select-layout", "-t", target, "even-horizontal")

    # Start claude interactively — prompt is sent as keystrokes after startup,
    # not as a CLI arg (which claude treats as a system prompt, leaving it idle)
    parts = ["claude", "--session-id", session_id]
    if getattr(args, "dangerously_skip_permissions", False):
        parts.append("--dangerously-skip-permissions")
    if getattr(args, "model", None):
        parts.extend(["--model", args.model])
    if getattr(args, "tools", None):
        parts.extend(["--allowedTools", args.tools])
    if getattr(args, "effort", None):
        parts.extend(["--effort", args.effort])

    tmux("send-keys", "-t", pane_id, shlex.join(parts), "Enter")

    # Wait for Claude's interactive prompt (❯) then send initial prompt literally
    deadline = time.time() + 30
    while time.time() < deadline:
        time.sleep(1)
        if "❯" in tmux_out("capture-pane", "-t", pane_id, "-p"):
            break

    tmux("send-keys", "-t", pane_id, "-l", args.prompt)
    tmux("send-keys", "-t", pane_id, "Enter")

    extras = []
    if getattr(args, "dangerously_skip_permissions", False):
        extras.append("skip-perms")
    if getattr(args, "model", None):
        extras.append(f"model={args.model}")
    if getattr(args, "tools", None):
        extras.append(f"tools={args.tools}")
    if getattr(args, "effort", None):
        extras.append(f"effort={args.effort}")
    extra_str = f" [{', '.join(extras)}]" if extras else ""
    print(
        f"Spawned '{args.task}' in pane {pane_id} ({target}) [session: {session_id}]{extra_str}"
    )


def cmd_pane_id(args: argparse.Namespace) -> None:
    """Print the tmux pane ID for a named task."""
    win = get_win()
    print(resolve_pane_id(win, args.task))


def cmd_session_id(args: argparse.Namespace) -> None:
    """Print the Claude session UUID for a named task."""
    win = get_win()
    state = load_state(win, args.task)
    print(state["session_id"])


def cmd_prompt(args: argparse.Namespace) -> None:
    """Send a follow-up prompt to a running agent pane."""
    win = get_win()
    pane_id = resolve_pane_id(win, args.task)
    tmux("send-keys", "-t", pane_id, "-l", args.text)
    tmux("send-keys", "-t", pane_id, "Enter")
    # Update sent_at so ping knows to wait for a fresh response
    sf = statefile(win, args.task)
    if sf.exists():
        state = json.loads(sf.read_text())
        state["sent_at"] = now_iso()
        sf.write_text(json.dumps(state))


def cmd_result(args: argparse.Namespace) -> None:
    """Print the last complete response; optionally wait for one."""
    win = get_win()
    state = load_state(win, args.task)
    session_id = state["session_id"]
    jsonl = jsonl_path(state)

    if args.wait:
        print(
            f"Waiting for response from '{args.task}' (session: {session_id})...",
            file=sys.stderr,
        )
        while True:
            result = extract_last_response(jsonl)
            if result is not None:
                print(result)
                return
            time.sleep(2)
    else:
        result = extract_last_response(jsonl)
        if result is None:
            print(
                f"No complete response yet for task '{args.task}' (session: {session_id})",
                file=sys.stderr,
            )
            sys.exit(1)
        print(result)


def active_claude_session_ids() -> set[str]:
    """Return session IDs currently tracked in ~/.claude/sessions/."""
    sessions_dir = Path.home() / ".claude" / "sessions"
    ids: set[str] = set()
    if sessions_dir.exists():
        for f in sessions_dir.glob("*.json"):
            try:
                sid = json.loads(f.read_text()).get("sessionId")
                if sid:
                    ids.add(sid)
            except (json.JSONDecodeError, OSError):
                pass
    return ids


def cmd_ping(args: argparse.Namespace) -> None:
    """Print a status table of all agent sessions in the current window."""
    win = get_win()
    state_files = sorted(Path("/tmp").glob(f"tmux-claude-{win}-*.json"))
    if not state_files:
        print("no sessions")
        return

    active_ids = active_claude_session_ids()
    rows = []
    for sf in state_files:
        task = sf.stem.removeprefix(f"tmux-claude-{win}-")
        state = json.loads(sf.read_text())
        session_id = state.get("session_id", "?")
        pane_id = state.get("pane_id", "?")
        if session_id not in active_ids:
            rows.append((pane_id, task, session_id, "dead"))
            continue
        sent_at_str = state.get("sent_at")
        if not sent_at_str:
            status = "thinking"
        else:
            sent_at = parse_iso(sent_at_str)
            last_ts = last_end_turn_timestamp(jsonl_path(state))
            status = (
                "ready" if (last_ts is not None and last_ts > sent_at) else "thinking"
            )
        rows.append((pane_id, task, session_id, status))

    col_w = [max(len(r[i]) for r in rows) for i in range(4)]
    col_w[0] = max(col_w[0], len("PANE"))
    col_w[1] = max(col_w[1], len("TASK"))
    col_w[2] = max(col_w[2], len("SESSION-ID"))
    col_w[3] = max(col_w[3], len("STATUS"))
    fmt = f"{{:<{col_w[0]}}}  {{:<{col_w[1]}}}  {{:<{col_w[2]}}}  {{:<{col_w[3]}}}"
    print(fmt.format("PANE", "TASK", "SESSION-ID", "STATUS"))
    print(fmt.format("-" * col_w[0], "-" * col_w[1], "-" * col_w[2], "-" * col_w[3]))
    for pane_id, task, session_id, status in rows:
        print(fmt.format(pane_id, task, session_id, status))


def cmd_resurrect(args: argparse.Namespace) -> None:
    """Bring back a cleaned-up agent using its known session UUID."""
    win = get_win()
    target = f"agents:{win}"
    session_id = args.session_id

    # Ensure agents session and window exist
    session_exists = (
        subprocess.run(
            ["tmux", "has-session", "-t", "agents"], capture_output=True
        ).returncode
        == 0
    )
    if not session_exists:
        tmux("new-session", "-d", "-s", "agents", "-n", win)
    elif (
        win
        not in tmux_out(
            "list-windows", "-t", "agents", "-F", "#{window_name}"
        ).splitlines()
    ):
        tmux("new-window", "-t", "agents", "-n", win)

    pane_id = tmux_out("split-window", "-t", target, "-d", "-P", "-F", "#{pane_id}")
    tmux("select-pane", "-t", pane_id, "-T", args.task)
    tmux("select-layout", "-t", target, "even-horizontal")

    tmux(
        "send-keys",
        "-t",
        pane_id,
        shlex.join(["claude", "--session-id", session_id]),
        "Enter",
    )

    state = {
        "pane_id": pane_id,
        "session_id": session_id,
        "cwd": os.getcwd(),
        "sent_at": now_iso(),
    }
    statefile(win, args.task).write_text(json.dumps(state))
    print(f"Resurrected '{args.task}' in pane {pane_id} (session: {session_id})")


def cmd_capture(args: argparse.Namespace) -> None:
    """Capture or stream pane output: default screenful, full scrollback, log, or stop."""
    win = get_win()
    pane_id = resolve_pane_id(win, args.task)
    mode = args.mode

    if mode == "full":
        result = tmux_out("capture-pane", "-t", pane_id, "-p", "-S", "-3000")
        print(result)
    elif mode == "log":
        logfile = f"/tmp/{args.task}.log"
        tmux("pipe-pane", "-t", pane_id, "-o", f"cat >> {logfile}")
        print(f"Streaming to {logfile}")
    elif mode == "stop":
        tmux("pipe-pane", "-t", pane_id)
        print("Stopped streaming")
    else:
        result = tmux_out("capture-pane", "-t", pane_id, "-p")
        print(result)


def cmd_cleanup(args: argparse.Namespace) -> None:
    """Kill one or all agent panes, remove their state files, and purge stale state files."""
    win = get_win()

    if args.all:
        for sf in Path("/tmp").glob(f"tmux-claude-{win}-*.json"):
            state = json.loads(sf.read_text())
            pane_id = state["pane_id"]
            task = sf.stem.removeprefix(f"tmux-claude-{win}-")
            result = subprocess.run(["tmux", "kill-pane", "-t", pane_id])
            if result.returncode == 0:
                print(f"Killed pane {pane_id} ({task})")
            sf.unlink()
        # Also purge stale state files across all windows
        active_ids = active_claude_session_ids()
        removed = 0
        for sf in Path("/tmp").glob("tmux-claude-*.json"):
            try:
                sid = json.loads(sf.read_text()).get("session_id")
            except (json.JSONDecodeError, OSError):
                sid = None
            if sid not in active_ids:
                sf.unlink(missing_ok=True)
                print(f"removed stale: {sf.name}")
                removed += 1
        if removed:
            print(f"{removed} stale file(s) removed")
    else:
        pane_id = resolve_pane_id(win, args.task)
        tmux("kill-pane", "-t", pane_id)
        statefile(win, args.task).unlink(missing_ok=True)
        print(f"Killed pane {pane_id} ({args.task})")


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------


def main() -> None:
    """Parse CLI arguments and dispatch to the appropriate subcommand."""
    parser = argparse.ArgumentParser(
        prog="agent.py",
        description="tmux-agents-claude management CLI",
        epilog="2026 github.com/mbrav",
    )
    sub = parser.add_subparsers(dest="cmd", required=True)

    p_spawn = sub.add_parser("spawn", help="spawn a Claude subagent pane")
    p_spawn.add_argument("task", help="task name (used for pane title and state file)")
    p_spawn.add_argument("prompt", help="prompt to pass to claude")
    p_spawn.add_argument(
        "--dangerously-skip-permissions",
        action="store_true",
        dest="dangerously_skip_permissions",
        help="pass --dangerously-skip-permissions to claude",
    )
    p_spawn.add_argument(
        "--model",
        metavar="MODEL",
        choices=MODELS,
        help=f"model to use: {', '.join(MODELS)}",
    )
    p_spawn.add_argument(
        "--tools",
        metavar="TOOLS",
        help="comma-separated allowed tools passed to --allowedTools (e.g. Read,Edit,Bash)",
    )
    p_spawn.add_argument(
        "--effort",
        metavar="LEVEL",
        choices=EFFORT_LEVELS,
        help=f"thinking effort level: {', '.join(EFFORT_LEVELS)}",
    )

    p_pane = sub.add_parser("pane-id", help="resolve task name to tmux pane ID")
    p_pane.add_argument("task")

    p_sid = sub.add_parser(
        "session-id", help="resolve task name to Claude session UUID"
    )
    p_sid.add_argument("task")

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

    sub.add_parser(
        "ping", help="list pane IDs, tasks, session IDs and status for current window"
    )

    p_capture = sub.add_parser("capture", help="capture or stream pane terminal output")
    p_capture.add_argument("task", help="task name")
    p_capture.add_argument(
        "mode",
        nargs="?",
        choices=["full", "log", "stop"],
        default=None,
        help="full=3000-line scrollback, log=stream to /tmp/<task>.log, stop=stop streaming (default: last screenful)",
    )

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
        "session-id": cmd_session_id,
        "prompt": cmd_prompt,
        "result": cmd_result,
        "resurrect": cmd_resurrect,
        "ping": cmd_ping,
        "capture": cmd_capture,
        "cleanup": cmd_cleanup,
    }
    dispatch[args.cmd](args)


if __name__ == "__main__":
    main()
