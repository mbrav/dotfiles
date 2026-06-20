#!/usr/bin/env python3
"""
agent.py — tmux-subagents-claude management CLI

Subcommands:
  spawn      <task> <prompt>     spawn a Claude subagent pane
  prompt     <task> <text>       send a follow-up prompt to an agent pane
  result     <task> [--wait]     read last complete response from JSONL log
  status     [--all]             status table of agents
  resurrect  <task> <uuid>       bring back a cleaned-up agent by session UUID
  capture    <task> [mode]       capture/stream pane output
  cleanup    <task|--all|--prune>  kill agents / purge state

State model
-----------
All agents for one source window live in a SINGLE JSON file keyed by the
window's (stable, deduped) NAME::

    /tmp/tmux-subagents-claude-<window>.json
    {
      "window": "obsidian",
      "agents_window_id": "@65",
      "agents": {
        "<task>": {"pane_id": "%120", "session_id": "<uuid>", "cwd": "<path>"}
      }
    }

The agents window mirrors the source window NAME (``agents:<window>``), matching
the ``tmux-named-session.sh`` convention so Prefix+a jumps straight to it. This
relies on ``automatic-rename off`` (set in tmux.conf) so window names are stable.
"""

import argparse
import json
import logging
import os
import re
import shlex
import subprocess
import sys
import time
import uuid
from pathlib import Path

# ---------------------------------------------------------------------------
# Logging — controlled entirely by environment variables
#
#   TMUX_AGENT_LOG        1/true/yes  → enable file logging (default: on)
#   TMUX_AGENT_LOG_PATH   path        → log file (default: /tmp/tmux-subagents-claude.log)
#   TMUX_AGENT_LOG_FORMAT format str  → Python logging format
#   TMUX_AGENT_DEBUG      1/true/yes  → set level to DEBUG (default: INFO)
# ---------------------------------------------------------------------------

PREFIX = "tmux-subagents-claude"
STATE_DIR = Path.home() / ".local" / "share" / PREFIX
LOG_ENABLED = os.environ.get("TMUX_AGENT_LOG", "1").lower() in ("1", "true", "yes")
LOG_PATH = os.environ.get("TMUX_AGENT_LOG_PATH", f"/tmp/{PREFIX}.log")
LOG_FORMAT = os.environ.get(
    "TMUX_AGENT_LOG_FORMAT", "%(asctime)s %(levelname)-5s %(name)s %(message)s"
)
LOG_DEBUG = os.environ.get("TMUX_AGENT_DEBUG", "").lower() in ("1", "true", "yes")

log = logging.getLogger(PREFIX)
log.setLevel(logging.DEBUG if LOG_DEBUG else logging.INFO)
log.propagate = False  # don't bleed into root logger / stdout

if LOG_ENABLED:
    fh = logging.FileHandler(LOG_PATH)
    fh.setFormatter(logging.Formatter(LOG_FORMAT))
    log.addHandler(fh)


# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

MODELS = [
    # Claude 4
    "claude-opus-4-8",
    "claude-opus-4-7",
    "claude-opus-4-5",
    "claude-sonnet-4-6",
    "claude-sonnet-4-5",
    "claude-haiku-4-5",
    "claude-haiku-4-5-20251001",
]

EFFORT_LEVELS = ["low", "medium", "high", "xhigh", "max", "auto"]


# ---------------------------------------------------------------------------
# tmux primitives
# ---------------------------------------------------------------------------


def tmux(*args: str) -> subprocess.CompletedProcess:
    """Run a tmux command, raising on non-zero exit."""
    return subprocess.run(["tmux", *args], check=True, text=True)


def tmux_out(*args: str) -> str:
    """Run a tmux command and return its stripped stdout."""
    return subprocess.check_output(["tmux", *args], text=True).strip()


# ---------------------------------------------------------------------------
# Window resolution (focus-independent, name-based)
# ---------------------------------------------------------------------------


def get_win() -> str:
    """Return the calling tmux window's NAME (e.g. ``obsidian``).

    Anchored to ``$TMUX_PANE`` (the pane this command runs in) so the result is
    independent of which window currently has focus. We key on the NAME so the
    agents window is human-readable and matches the ``tmux-named-session.sh`` /
    Prefix+a convention; this requires ``automatic-rename off`` (tmux.conf) so
    names stay put.
    """
    args = ["tmux", "display-message", "-p"]
    pane = os.environ.get("TMUX_PANE")
    if pane:
        args += ["-t", pane]
    args.append("#{window_name}")
    win = subprocess.check_output(args, text=True).strip()
    log.debug("get_win -> %s (TMUX_PANE=%s)", win, pane or "<unset>")
    return win


# ---------------------------------------------------------------------------
# Consolidated per-window state
# ---------------------------------------------------------------------------


def _winkey(win: str) -> str:
    """Filesystem-safe key for a window name (names are dir basenames in practice)."""
    return win.replace("/", "-").replace(" ", "_")


def winfile(win: str) -> Path:
    """Path to the JSON state file for *win* under STATE_DIR."""
    STATE_DIR.mkdir(parents=True, exist_ok=True)
    return STATE_DIR / f"{_winkey(win)}.json"


def load_win(win: str) -> dict:
    """Load the window's state, or return an empty skeleton if absent."""
    sf = winfile(win)
    if sf.exists():
        try:
            data = json.loads(sf.read_text())
            data.setdefault("window", win)
            data.setdefault("agents_window_id", None)
            data.setdefault("agents", {})
            log.debug("load_win %s: %d agent(s) from %s", win, len(data["agents"]), sf)
            return data
        except (json.JSONDecodeError, OSError) as e:
            log.warning("load_win %s: parse error (%s), returning empty state", win, e)
    else:
        log.debug("load_win %s: no state file, returning empty", win)
    return {"window": win, "agents_window_id": None, "agents": {}}


def save_win(win: str, data: dict) -> None:
    """Persist the window's state."""
    winfile(win).write_text(json.dumps(data, indent=2))
    log.debug(
        "save_win %s: %d agent(s) -> %s", win, len(data.get("agents", {})), winfile(win)
    )


def get_agent(win: str, task: str) -> dict:
    """Return one agent's metadata dict; exit 1 if unknown."""
    data = load_win(win)
    meta = data["agents"].get(task)
    if meta is None:
        log.warning(
            "get_agent: task '%s' not found in window '%s' (known: %s)",
            task,
            win,
            list(data["agents"].keys()),
        )
        print(f"No agent '{task}' tracked for window '{win}'", file=sys.stderr)
        sys.exit(1)
    return meta


# ---------------------------------------------------------------------------
# JSONL transcript helpers
# ---------------------------------------------------------------------------


def jsonl_path(meta: dict) -> Path:
    """Derive the Claude JSONL transcript path from an agent metadata dict."""
    cwd = meta.get("cwd", os.getcwd())
    # Claude encodes the cwd into a project dir name by replacing every
    # non-alphanumeric char with "-" (covers / . _ space). Match it exactly,
    # else paths with "_" (e.g. transcribe_audio -> transcribe-audio) miss.
    project_dir = re.sub(r"[^a-zA-Z0-9]", "-", cwd)
    path = (
        Path.home()
        / ".claude"
        / "projects"
        / project_dir
        / f"{meta['session_id']}.jsonl"
    )
    log.debug("jsonl_path cwd=%s -> %s", cwd, path)
    return path


def extract_last_response(jsonl: Path) -> str | None:
    """Return text of the last end_turn assistant message in the JSONL log, or None."""
    if not jsonl.exists():
        log.debug("extract_last_response: JSONL not found: %s", jsonl)
        return None
    last_text = None
    with open(jsonl) as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            try:
                record = json.loads(line)
            except json.JSONDecodeError as e:
                log.warning("extract_last_response: bad JSON line in %s: %s", jsonl, e)
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


def claude_session_statuses() -> dict[str, str]:
    """Return {sessionId: status} for all running claude sessions."""
    sessions_dir = Path.home() / ".claude" / "sessions"
    statuses: dict[str, str] = {}
    if sessions_dir.exists():
        for f in sessions_dir.glob("*.json"):
            try:
                data = json.loads(f.read_text())
                sid = data.get("sessionId")
                if sid:
                    statuses[sid] = data.get("status", "idle")
            except (json.JSONDecodeError, OSError) as e:
                log.warning("claude_session_statuses: skipping %s: %s", f.name, e)
    return statuses


# ---------------------------------------------------------------------------
# Agents window / pane management
# ---------------------------------------------------------------------------


def live_panes() -> set[str]:
    """Set of all live pane IDs across the server."""
    try:
        panes = set(tmux_out("list-panes", "-a", "-F", "#{pane_id}").splitlines())
        log.debug("live_panes: %d pane(s)", len(panes))
        return panes
    except subprocess.CalledProcessError:
        log.debug("live_panes: tmux error, returning empty set")
        return set()


def agents_window_id(win: str) -> str | None:
    """Return the window ID (@N) of the exact-named window in the agents session."""
    try:
        for line in tmux_out(
            "list-windows", "-t", "agents", "-F", "#{window_id} #{window_name}"
        ).splitlines():
            wid, _, name = line.partition(" ")
            if name == win:
                log.debug("agents_window_id %s -> %s", win, wid)
                return wid
    except subprocess.CalledProcessError:
        log.debug("agents_window_id %s: agents session not found", win)
    log.debug("agents_window_id %s -> None", win)
    return None


# Persistent anchor window. Without it, the last agent pane exiting (claude
# crash, the sandbox suspend/resume killing processes, or simply finishing)
# closes the only window in the agents session and tmux destroys the WHOLE
# session -- which then makes status/result/capture/cleanup fail with
# ``no sessions`` / ``can't find window: agents``. The keeper runs a long sleep
# so the session is never empty and always survives.
KEEPER_WINDOW = "__keeper__"
KEEPER_CMD = "exec sleep 2147483647"


def ensure_agents_session() -> None:
    """Ensure the detached ``agents`` session exists, anchored by a persistent
    keeper window so it never dies when all agent panes exit.
    """
    r = subprocess.run(
        [
            "tmux",
            "new-session",
            "-d",
            "-s",
            "agents",
            "-n",
            KEEPER_WINDOW,
            KEEPER_CMD,
        ],
        capture_output=True,
        text=True,
    )
    if r.returncode == 0:
        log.info("agents session created (keeper window: %s)", KEEPER_WINDOW)
        # detached new-session defaults to window-size manual; override so panes
        # resize to the attaching client rather than staying stuck at creation size.
        subprocess.run(
            ["tmux", "set-option", "-t", "agents", "window-size", "latest"], check=False
        )
        return
    if "duplicate session" in r.stderr:
        try:
            names = set(
                tmux_out(
                    "list-windows", "-t", "agents", "-F", "#{window_name}"
                ).splitlines()
            )
        except subprocess.CalledProcessError:
            names = set()
        if KEEPER_WINDOW not in names:
            subprocess.run(
                [
                    "tmux",
                    "new-window",
                    "-d",
                    "-t",
                    "agents",
                    "-n",
                    KEEPER_WINDOW,
                    KEEPER_CMD,
                ],
                capture_output=True,
                text=True,
            )
            log.info("keeper window added to existing agents session")
        else:
            log.debug("ensure_agents_session: session exists, keeper present")
        return
    log.error(
        "ensure_agents_session: unexpected tmux error (rc=%d): %s",
        r.returncode,
        r.stderr.strip(),
    )
    raise subprocess.CalledProcessError(r.returncode, r.args, r.stdout, r.stderr)


def ensure_agents_window(win: str) -> tuple[str, bool, str, str]:
    """Ensure the agents session and the window mirroring *win* exist.

    The agents session is anchored by a persistent keeper window (see
    ``ensure_agents_session``) so it survives all agents exiting. The agent
    window is named after the source window (``agents:<win>``), matching the
    tmux-named-session.sh / Prefix+a convention. Relies on ``automatic-rename
    off`` (tmux.conf) keeping the name stable.

    Returns (target, fresh_window, initial_pane_id, window_id).
    initial_pane_id is only meaningful when fresh_window=True.
    """
    ensure_agents_session()
    win_id = agents_window_id(win)
    if win_id is None:
        out = tmux_out(
            "new-window",
            "-t",
            "agents",
            "-n",
            win,
            "-P",
            "-F",
            "#{window_id} #{pane_id}",
        )
        win_id, pane_id = out.split()
        log.info("agents window created: win=%s id=%s pane=%s", win, win_id, pane_id)
        return f"agents:{win_id}", True, pane_id, win_id
    log.debug("ensure_agents_window: window exists win=%s id=%s", win, win_id)
    return f"agents:{win_id}", False, "", win_id


def resolve_pane_id(win: str, task: str) -> str:
    """Return the live pane ID for *task* from state; exit 1 if missing or dead."""
    meta = load_win(win)["agents"].get(task)
    pane_id = meta.get("pane_id") if meta else None
    if pane_id and pane_id in live_panes():
        log.debug("resolve_pane_id task=%s -> %s", task, pane_id)
        return pane_id
    log.warning(
        "resolve_pane_id task=%s pane=%s not found or dead (win=%s)", task, pane_id, win
    )
    print(f"pane not found: {task}", file=sys.stderr)
    sys.exit(1)


# ---------------------------------------------------------------------------
# Subcommands
# ---------------------------------------------------------------------------


def cmd_spawn(args: argparse.Namespace) -> None:
    """Spawn a new Claude subagent pane in the agents session."""
    win = get_win()
    agent_name = f"subagent-{win}-{args.task}"
    log.info("spawn agent=%s", agent_name)
    target, fresh_window, initial_pane, win_id = ensure_agents_window(win)

    if fresh_window:
        pane_id = initial_pane  # captured atomically at session/window creation
    else:
        pane_id = tmux_out("split-window", "-t", target, "-d", "-P", "-F", "#{pane_id}")

    log.debug(
        "spawn agent=%s pane=%s fresh_window=%s", agent_name, pane_id, fresh_window
    )

    # Generate a session ID and record state in the consolidated window file.
    session_id = str(uuid.uuid4())
    data = load_win(win)
    data["agents_window_id"] = win_id
    data["agents"][args.task] = {
        "pane_id": pane_id,
        "session_id": session_id,
        "cwd": os.getcwd(),
        "agent_name": agent_name,
    }
    save_win(win, data)

    # Side-by-side horizontal layout: | Agent 1 | Agent 2 | Agent 3 |
    tmux("select-layout", "-t", target, "even-horizontal")

    # Start claude interactively — prompt is sent as keystrokes after startup,
    # not as a CLI arg (which claude treats as a system prompt, leaving it idle).
    parts = ["claude", "--session-id", session_id]
    parts.extend(["--name", agent_name])
    parts.append("--dangerously-skip-permissions")

    if getattr(args, "model", None):
        parts.extend(["--model", args.model])
    if getattr(args, "tools", None):
        parts.extend(["--allowedTools", args.tools])
    if getattr(args, "effort", None):
        parts.extend(["--effort", args.effort])

    log.debug("spawn name=%s cmd: %s", agent_name, shlex.join(parts))
    tmux("send-keys", "-t", pane_id, shlex.join(parts), "Enter")

    # Wait for Claude's interactive prompt (❯) then send the initial prompt literally.
    deadline = time.time() + 30
    log.debug("spawn agent=%s waiting for ❯ (timeout=30s)", agent_name)
    _prompt_seen = False
    while time.time() < deadline:
        time.sleep(0.25)
        try:
            if "❯" in tmux_out("capture-pane", "-t", pane_id, "-p"):
                log.debug("spawn agent=%s prompt ready", agent_name)
                _prompt_seen = True
                break
        except subprocess.CalledProcessError:
            log.warning("spawn agent=%s pane vanished while waiting for ❯", agent_name)
            break
    if not _prompt_seen:
        log.warning(
            "spawn agent=%s ❯ never appeared within 30s (pane=%s)", agent_name, pane_id
        )

    # Repaint so Claude fills the (possibly resized) pane and anchors its input
    # box to the bottom before we paste the initial prompt.
    _force_redraw(pane_id)
    _paste_text(pane_id, args.prompt)
    tmux("send-keys", "-t", pane_id, "Enter")

    extras = []
    if getattr(args, "model", None):
        extras.append(f"model={args.model}")
    if getattr(args, "tools", None):
        extras.append(f"tools={args.tools}")
    if getattr(args, "effort", None):
        extras.append(f"effort={args.effort}")
    extra_str = f" [{', '.join(extras)}]" if extras else ""
    log.info(
        "spawned agent=%s pane=%s session=%s%s",
        agent_name,
        pane_id,
        session_id,
        f" {extra_str}" if extra_str else "",
    )
    print(
        f"Spawned {agent_name} in pane {pane_id} ({target}) [session: {session_id}]{extra_str}"
    )


def _capture_pane(pane_id: str) -> str:
    """Snapshot current pane (last screenful), empty string on failure."""
    try:
        return tmux_out("capture-pane", "-t", pane_id, "-p")
    except subprocess.CalledProcessError:
        return ""


# Matches the context-window usage in Claude's footer status line, e.g.
# "↑601 ↓131 R84.9k W1.9k $0.042 (sub) 90.0k/1000.0k (9.0%)" -> "90.0k/1000.0k (9.0%)".
_CONTEXT_RE = re.compile(r"(\d+(?:\.\d+)?k/\d+(?:\.\d+)?k\s*\(\d+(?:\.\d+)?%\))")


def _pane_context(pane_id: str) -> str:
    """Extract context-window usage (tokens/limit (pct)) from a pane footer.

    Returns the last match in the captured screenful, or "-" if none (pane
    starting, dead, or footer not rendered).
    """
    match = None
    for line in _capture_pane(pane_id).splitlines():
        m = _CONTEXT_RE.search(line)
        if m:
            # Normalise internal whitespace to a single space: "X/Y (Z%)".
            match = " ".join(m.group(1).split())
    return match or "-"


def _force_redraw(pane_id: str) -> None:
    """Force Claude's TUI to repaint and bottom-anchor its input box.

    Claude measures terminal height at startup; if the pane later grows (layout
    rebalance when sibling panes spawn/close), Claude does NOT repaint and leaves
    its input box mid-pane with a block of blank lines below the footer. That
    also breaks submit-verification — the box falls outside the captured tail, so
    a still-unsubmitted prompt reads as "submitted" and wedges ``prompt --wait``
    forever. A width nudge + layout restore delivers SIGWINCH, making Claude
    redraw full-height with the prompt pinned to the bottom.

    Nudges the window HEIGHT by one row and back: width is unchanged so Claude's
    text never rewraps (a width nudge reflows everything and can scroll the input
    box out of view), but the height change delivers SIGWINCH and re-anchors the
    box to the bottom.
    """
    try:
        h = int(tmux_out("display-message", "-p", "-t", pane_id, "#{window_height}"))
        tmux("resize-window", "-t", pane_id, "-y", str(h - 1))
        time.sleep(0.15)
        tmux("resize-window", "-t", pane_id, "-y", str(h))
        time.sleep(0.2)
    except (subprocess.CalledProcessError, ValueError) as e:
        log.warning("_force_redraw: failed for pane %s: %s", pane_id, e)


def _paste_text(pane_id: str, text: str) -> None:
    """Paste text via tmux load-buffer + paste-buffer -p (bracketed paste mode).

    send-keys -l converts bare \\n to Enter presses, splitting multiline prompts
    into separate submissions. Bracketed paste wraps the content in \\x1b[200~…\\x1b[201~
    so the receiving app sees it as a single paste block and preserves newlines.
    """
    buf = f"sp_{int(time.time() * 1000)}"
    subprocess.run(
        ["tmux", "load-buffer", "-b", buf, "-"],
        input=text.encode(),
        check=True,
    )
    try:
        tmux("paste-buffer", "-p", "-t", pane_id, "-b", buf)
    finally:
        subprocess.run(["tmux", "delete-buffer", "-b", buf], check=False)


def _reset_input_line(pane_id: str) -> None:
    """Clear the Claude input buffer before pasting.

    Do NOT send Escape: in current Claude (v2.1.x) Esc-Esc opens the rewind /
    checkpoint modal, so pasted text lands in that menu instead of the prompt and
    never submits — which used to wedge every ``prompt``/``prompt --wait``. A
    single C-u kills the readline-style input line and is harmless when empty.
    """
    tmux("send-keys", "-t", pane_id, "C-u")
    time.sleep(0.05)


def _verify_submitted(pane_id: str, text: str) -> bool:
    """After Enter, confirm the pasted text is no longer sitting on input line.

    Looks at the last ~6 lines (where the ❯ prompt lives). If a non-trivial
    tail of the submitted text is still visible there, submission failed.
    """
    time.sleep(0.3)
    snap_lines = _capture_pane(pane_id).splitlines()
    # Drop trailing blank lines: Claude can leave dead space below its footer,
    # which would push the input box out of a naive tail slice and mask a
    # still-unsubmitted prompt as submitted.
    while snap_lines and not snap_lines[-1].strip():
        snap_lines.pop()
    tail_lines = "\n".join(snap_lines[-6:])
    # Use the last meaningful chunk of the user text — short prefixes match noise.
    needle = text.strip().splitlines()[-1][-40:] if text.strip() else ""
    if not needle:
        return True
    return needle not in tail_lines


def _send_prompt(pane_id: str, text: str, verify: bool = True) -> bool:
    """Reset, paste, submit, optionally verify. Returns True on success."""
    # Repaint first so the input box is bottom-anchored: a mid-pane box (Claude
    # not having repainted after a resize) silently eats pastes and defeats
    # verification.
    _force_redraw(pane_id)
    _reset_input_line(pane_id)
    _paste_text(pane_id, text)
    time.sleep(0.05)
    tmux("send-keys", "-t", pane_id, "Enter")
    if not verify:
        return True
    if _verify_submitted(pane_id, text):
        return True
    log.warning("prompt verify failed once, retrying")
    _reset_input_line(pane_id)
    _paste_text(pane_id, text)
    time.sleep(0.05)
    tmux("send-keys", "-t", pane_id, "Enter")
    return _verify_submitted(pane_id, text)


def cmd_prompt(args: argparse.Namespace) -> None:
    """Send a follow-up prompt to a running agent pane.

    Hardens against the INSERT-mode-stuck failure: prior modal state is reset
    before paste, Enter is sent explicitly, and submission is verified.
    """
    win = get_win()
    agent_name = f"subagent-{win}-{args.task}"
    pane_id = resolve_pane_id(win, args.task)
    # Retrieve actual agent_name if it exists in metadata
    meta = load_win(win)["agents"].get(args.task, {})
    if meta.get("agent_name"):
        agent_name = meta["agent_name"]
    log.info(
        "prompt agent=%s pane=%s verify=%s wait=%s",
        agent_name,
        pane_id,
        args.verify,
        args.wait,
    )

    ok = _send_prompt(pane_id, args.text, verify=args.verify)
    if not ok:
        log.error("prompt agent=%s NOT submitted — pane likely modal/stuck", agent_name)
        print(
            f"prompt-not-submitted: agent '{agent_name}' pane {pane_id}. "
            "Pane may be in INSERT/modal state. Try `capture` to inspect, "
            "or `cleanup <task>` + `resurrect <task> <session-id>` to reset.",
            file=sys.stderr,
        )
        sys.exit(2)

    if args.wait:
        meta = get_agent(win, args.task)
        jsonl = jsonl_path(meta)
        # Baseline: snapshot current last response so we wait for a NEW one.
        baseline = extract_last_response(jsonl)
        log.info("prompt --wait agent=%s polling for new response", agent_name)
        _wait_iters = 0
        while True:
            time.sleep(2)
            _wait_iters += 1
            current = extract_last_response(jsonl)
            if current is not None and current != baseline:
                log.info(
                    "prompt --wait agent=%s new response after %ds",
                    agent_name,
                    _wait_iters * 2,
                )
                print(current)
                return
            if _wait_iters % 10 == 0:
                log.debug(
                    "prompt --wait agent=%s still waiting (%ds elapsed)",
                    agent_name,
                    _wait_iters * 2,
                )


def cmd_result(args: argparse.Namespace) -> None:
    """Print the last complete response; optionally wait for one."""
    win = get_win()
    meta = get_agent(win, args.task)
    session_id = meta["session_id"]
    agent_name = meta.get("agent_name", f"subagent-{win}-{args.task}")
    jsonl = jsonl_path(meta)
    log.debug(
        "result agent=%s session=%s jsonl=%s wait=%s",
        agent_name,
        session_id,
        jsonl,
        args.wait,
    )

    if args.wait:
        log.info("result agent=%s waiting for response", agent_name)
        print(
            f"Waiting for response from '{agent_name}' (session: {session_id})...",
            file=sys.stderr,
        )
        # Block while the agent is still `busy` so we don't hand back a stale
        # prior end_turn while it's working on a freshly-sent prompt. This
        # cannot detect staleness once the agent has gone back to `idle` — for
        # send-and-block on a guaranteed-NEW reply use `prompt --wait`, which
        # baselines the prior response before sending.
        _wait_iters = 0
        while True:
            status = claude_session_statuses().get(session_id, "starting")
            result = extract_last_response(jsonl)
            if status != "busy" and result is not None:
                log.info(
                    "result agent=%s response ready after %ds",
                    agent_name,
                    _wait_iters * 2,
                )
                print(result)
                return
            _wait_iters += 1
            if _wait_iters % 10 == 0:
                log.debug(
                    "result --wait agent=%s still waiting status=%s (%ds elapsed)",
                    agent_name,
                    status,
                    _wait_iters * 2,
                )
            time.sleep(2)
    else:
        result = extract_last_response(jsonl)
        if result is None:
            log.info("result agent=%s no complete response yet", agent_name)
            print(
                f"No complete response yet for agent '{agent_name}' (session: {session_id})",
                file=sys.stderr,
            )
            sys.exit(1)
        log.info("result agent=%s response found", agent_name)
        print(result)


def _status_rows(
    win: str, statuses: dict[str, str]
) -> list[tuple[str, str, str, str, str, str]]:
    """Build (project, pane, task, session, status, context) rows for one window's agents."""
    data = load_win(win)
    panes = live_panes()
    rows = []
    for task, meta in data["agents"].items():
        sid = meta.get("session_id", "?")
        pane = meta.get("pane_id", "?")
        agent_name = meta.get("agent_name", f"subagent-{win}-{task}")
        # A live pane is never "dead"; missing status just means it's still
        # starting up (the claude session-status file lags briefly).
        live = pane in panes
        status = statuses.get(sid, "starting") if live else "dead"
        # Disambiguate the "idle trap": an idle agent that has produced no
        # completed reply yet is "empty" (fresh / awaiting its first prompt),
        # vs "idle" which means it finished work and has output to read. Lets a
        # caller tell "nothing here yet" apart from "done".
        if status == "idle":
            try:
                if extract_last_response(jsonl_path(meta)) is None:
                    status = "empty"
            except (KeyError, OSError) as e:
                log.warning(
                    "_status_rows: error checking JSONL for agent '%s': %s",
                    agent_name,
                    e,
                )
        context = _pane_context(pane) if live else "-"
        log.debug(
            "status agent=%s pane=%s status=%s context=%s",
            agent_name,
            pane,
            status,
            context,
        )
        rows.append((win, pane, task, sid, status, context))
    return rows


def cmd_status(args: argparse.Namespace) -> None:
    """Print a status table of agent sessions."""
    statuses = claude_session_statuses()
    task_filter = getattr(args, "task", None)
    if getattr(args, "all", False):
        rows = []
        for sf in sorted(STATE_DIR.glob("*.json")) if STATE_DIR.exists() else []:
            win = json.loads(sf.read_text()).get("window", sf.stem)
            rows.extend(_status_rows(win, statuses))
    else:
        rows = _status_rows(get_win(), statuses)

    if task_filter:
        rows = [r for r in rows if r[1] == task_filter]
        if not rows:
            log.error("status: task '%s' not found", task_filter)
            print(f"unknown-task: {task_filter}", file=sys.stderr)
            sys.exit(2)
        # Single-agent query: print bare status for easy scripting
        print(rows[0][4])
        return

    if not rows:
        print("no sessions")
        return

    headers = ("PROJECT", "PANE", "TASK", "SESSION-ID", "STATUS", "CONTEXT")
    col_w = [max(len(headers[i]), max(len(r[i]) for r in rows)) for i in range(6)]
    fmt = "  ".join(f"{{:<{w}}}" for w in col_w)
    print(fmt.format(*headers))
    print(fmt.format(*("-" * w for w in col_w)))
    for row in rows:
        print(fmt.format(*row))


def cmd_resurrect(args: argparse.Namespace) -> None:
    """Bring back a cleaned-up agent using its known session UUID."""
    win = get_win()
    session_id = args.session_id
    agent_name = f"subagent-{win}-{args.task}"
    log.info("resurrect agent=%s session=%s win=%s", agent_name, session_id, win)

    target, fresh_window, initial_pane, win_id = ensure_agents_window(win)
    pane_id = (
        initial_pane
        if fresh_window
        else tmux_out("split-window", "-t", target, "-d", "-P", "-F", "#{pane_id}")
    )
    log.debug("resurrect agent=%s pane=%s", agent_name, pane_id)
    tmux("select-layout", "-t", target, "even-horizontal")

    tmux(
        "send-keys",
        "-t",
        pane_id,
        shlex.join(["claude", "--resume", session_id]),
        "Enter",
    )

    data = load_win(win)
    data["agents_window_id"] = win_id
    data["agents"][args.task] = {
        "pane_id": pane_id,
        "session_id": session_id,
        "cwd": os.getcwd(),
        "agent_name": agent_name,
    }
    save_win(win, data)
    log.info("resurrected agent=%s pane=%s session=%s", agent_name, pane_id, session_id)
    print(f"Resurrected {agent_name} in pane {pane_id} (session: {session_id})")


def cmd_capture(args: argparse.Namespace) -> None:
    """Capture or stream pane output: default screenful, full scrollback, log, or stop."""
    win = get_win()
    pane_id = resolve_pane_id(win, args.task)
    meta = load_win(win)["agents"].get(args.task, {})
    agent_name = meta.get("agent_name", f"subagent-{win}-{args.task}")
    mode = args.mode

    # Cheapness hint: if agent is idle and user wants a one-shot capture,
    # `result` reads the JSONL log instead of parsing terminal output.
    if mode in (None, "full"):
        sid = meta.get("session_id")
        if sid:
            status = claude_session_statuses().get(sid)
            if status == "idle":
                print(
                    f"hint: '{agent_name}' is idle — `result {args.task}` is cheaper "
                    "(reads JSONL log, not terminal scrollback).",
                    file=sys.stderr,
                )
    log.debug(
        "capture agent=%s pane=%s mode=%s", agent_name, pane_id, mode or "screenful"
    )

    if mode == "full":
        print(tmux_out("capture-pane", "-t", pane_id, "-p", "-S", "-3000"))
    elif mode == "log":
        logfile = f"/tmp/{args.task}.log"
        tmux("pipe-pane", "-t", pane_id, "-o", f"cat >> {logfile}")
        log.info("capture agent=%s streaming to %s", agent_name, logfile)
        print(f"Streaming to {logfile}")
    elif mode == "stop":
        tmux("pipe-pane", "-t", pane_id)
        log.info("capture agent=%s streaming stopped", agent_name)
        print("Stopped streaming")
    else:
        print(tmux_out("capture-pane", "-t", pane_id, "-p"))


def _kill_pane(pane_id: str) -> bool:
    """Kill a pane; return True if it existed."""
    return (
        subprocess.run(
            ["tmux", "kill-pane", "-t", pane_id], capture_output=True
        ).returncode
        == 0
    )


def cmd_cleanup(args: argparse.Namespace) -> None:
    """Kill one agent, all agents in this window, or prune dead state everywhere."""
    if args.prune:
        # Cross-window sweep: drop only entries whose pane is confirmed dead, and
        # remove window files that end up empty. Never touches live agents, so it
        # is safe to run alongside concurrent orchestrator sessions.
        log.info("cleanup --prune: cross-window sweep")
        panes = live_panes()
        removed = 0
        for sf in sorted(STATE_DIR.glob("*.json")) if STATE_DIR.exists() else []:
            try:
                data = json.loads(sf.read_text())
            except (json.JSONDecodeError, OSError):
                sf.unlink(missing_ok=True)
                print(f"Removed unreadable: {sf.name}")
                log.info("prune: removed unreadable %s", sf.name)
                removed += 1
                continue
            agents = data.get("agents", {})
            dead = [t for t, m in agents.items() if m.get("pane_id") not in panes]
            for t in dead:
                agent_name = agents[t].get("agent_name", t)
                log.info(
                    "prune: dead agent '%s' in %s (pane %s)",
                    agent_name,
                    sf.name,
                    agents[t].get("pane_id"),
                )
                del agents[t]
                print(f"Pruned dead agent '{agent_name}' from {sf.name}")
                removed += 1
            if agents:
                sf.write_text(json.dumps(data, indent=2))
            else:
                sf.unlink(missing_ok=True)
                log.info("prune: removed empty %s", sf.name)
                print(f"Removed empty: {sf.name}")
        log.info(
            "prune: %d dead entr%s removed", removed, "y" if removed == 1 else "ies"
        )
        print(f"{removed} dead entr{'y' if removed == 1 else 'ies'} pruned")
        return

    win = get_win()

    if args.all:
        log.info("cleanup --all win=%s", win)
        data = load_win(win)
        for task, meta in data["agents"].items():
            pane_id = meta.get("pane_id", "")
            agent_name = meta.get("agent_name", f"subagent-{win}-{task}")
            if _kill_pane(pane_id):
                log.info("cleanup: killed pane=%s agent=%s", pane_id, agent_name)
                print(f"Killed pane {pane_id} ({agent_name})")
            else:
                log.info("cleanup: pane=%s already gone agent=%s", pane_id, agent_name)
                print(f"Pane {pane_id} already gone ({agent_name})")
        winfile(win).unlink(missing_ok=True)
        log.debug("cleanup --all: removed state file for win=%s", win)
        return

    # Single task
    meta = get_agent(win, args.task)
    agent_name = meta.get("agent_name", f"subagent-{win}-{args.task}")
    pane_to_kill = meta.get("pane_id", "")
    log.info("cleanup agent=%s win=%s pane=%s", agent_name, win, pane_to_kill)
    if not _kill_pane(pane_to_kill):
        log.warning(
            "cleanup: pane %s already dead for agent '%s'", pane_to_kill, agent_name
        )
    data = load_win(win)
    data["agents"].pop(args.task, None)
    if data["agents"]:
        save_win(win, data)
    else:
        winfile(win).unlink(missing_ok=True)
        log.debug("cleanup: state file removed (no agents left) win=%s", win)
    log.info("cleanup done agent=%s pane=%s", agent_name, pane_to_kill)
    print(f"Killed pane {pane_to_kill} ({agent_name})")


# ---------------------------------------------------------------------------
# Agent slash-command shortcuts
# ---------------------------------------------------------------------------


def cmd_recap(args: argparse.Namespace) -> None:
    """Send /recap to an agent pane."""
    win = get_win()
    pane_id = resolve_pane_id(win, args.task)
    meta = load_win(win)["agents"].get(args.task, {})
    agent_name = meta.get("agent_name", f"subagent-{win}-{args.task}")
    log.info("recap agent=%s pane=%s", agent_name, pane_id)
    ok = _send_prompt(pane_id, "/recap")
    if not ok:
        log.error("recap agent=%s NOT submitted", agent_name)
        print(
            f"prompt-not-submitted: agent '{agent_name}' pane {pane_id}",
            file=sys.stderr,
        )
        sys.exit(2)
    print(f"Sent /recap to {agent_name} ({pane_id})")


def cmd_compact(args: argparse.Namespace) -> None:
    """Send /compact [description] to an agent pane."""
    win = get_win()
    pane_id = resolve_pane_id(win, args.task)
    meta = load_win(win)["agents"].get(args.task, {})
    agent_name = meta.get("agent_name", f"subagent-{win}-{args.task}")
    text = "/compact" if not args.description else f"/compact {args.description}"
    log.info("compact agent=%s pane=%s text=%r", agent_name, pane_id, text)
    ok = _send_prompt(pane_id, text)
    if not ok:
        log.error("compact agent=%s NOT submitted", agent_name)
        print(
            f"prompt-not-submitted: agent '{agent_name}' pane {pane_id}",
            file=sys.stderr,
        )
        sys.exit(2)
    print(f"Sent {text!r} to {agent_name} ({pane_id})")


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------


def main() -> None:
    """Parse CLI arguments and dispatch to the appropriate subcommand."""
    parser = argparse.ArgumentParser(
        prog="agent.py",
        description=f"{PREFIX} management CLI",
        epilog="2026 github.com/mbrav",
    )
    sub = parser.add_subparsers(dest="cmd", required=True)

    p_spawn = sub.add_parser("spawn", help="spawn a Claude subagent pane")
    p_spawn.add_argument("task", help="task name (pane title + state key)")
    p_spawn.add_argument("prompt", help="prompt to pass to claude")
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

    p_prompt = sub.add_parser("prompt", help="send a follow-up prompt to an agent pane")
    p_prompt.add_argument("task")
    p_prompt.add_argument("text")
    p_prompt.add_argument(
        "--wait",
        action="store_true",
        help="block until a NEW end_turn response arrives, then print it",
    )
    p_prompt.add_argument(
        "--no-verify",
        dest="verify",
        action="store_false",
        help="skip post-Enter verification (default: verify, fail loud if stuck)",
    )
    p_prompt.set_defaults(verify=True)

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

    p_status = sub.add_parser(
        "status", help="status table of agents for the current window"
    )
    p_status.add_argument(
        "task", nargs="?", default=None, help="show status for a single agent"
    )
    p_status.add_argument(
        "--all", action="store_true", help="show agents across all windows"
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

    p_clean = sub.add_parser("cleanup", help="kill agents / prune state")
    grp = p_clean.add_mutually_exclusive_group(required=True)
    grp.add_argument("task", nargs="?", help="task name to kill")
    grp.add_argument(
        "--all", action="store_true", help="kill all agents in this window"
    )
    grp.add_argument(
        "--prune",
        action="store_true",
        help="cross-window sweep: drop dead-pane entries + empty files (concurrency-safe)",
    )

    p_recap = sub.add_parser("recap", help="send /recap to an agent pane")
    p_recap.add_argument("task", help="task name")

    p_compact = sub.add_parser(
        "compact", help="send /compact [description] to an agent pane"
    )
    p_compact.add_argument("task", help="task name")
    p_compact.add_argument(
        "description",
        nargs="?",
        default=None,
        help="optional description passed to /compact",
    )

    args = parser.parse_args()

    dispatch = {
        "spawn": cmd_spawn,
        "prompt": cmd_prompt,
        "result": cmd_result,
        "status": cmd_status,
        "cleanup": cmd_cleanup,
        "resurrect": cmd_resurrect,
        "capture": cmd_capture,
        "recap": cmd_recap,
        "compact": cmd_compact,
    }
    dispatch[args.cmd](args)


if __name__ == "__main__":
    main()
