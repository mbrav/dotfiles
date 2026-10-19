#!/usr/bin/env python3
"""Speak each Claude action aloud with Kokoro TTS.

As a hook (PreToolUse, Stop, Notification) it reads the event from stdin,
turns it into a short phrase prefixed with the project name ("dotfiles:
Editing settings.json") and hands it to the daemon, starting the daemon on
first use. Exits quietly when kokoro-tts is not on PATH.

`kokoro.py --daemon` is the daemon: it runs under the kokoro-tts tool's
interpreter (which has kokoro_onnx and sounddevice), keeps the model loaded
and plays lines sent to a Unix socket. A line arriving while another plays
is dropped, except Stop and Notification, which cut it off. The daemon exits
after IDLE_EXIT seconds without a line.

Env:
  CLAUDE_KOKORO_VOICE   voice, default af_heart (kokoro-tts --help-voices)
  CLAUDE_KOKORO_SPEED   speech rate, default 1.0
  CLAUDE_KOKORO_VOLUME  1.0 as synthesized, 0.5 half, 0 mute; default 0.5
  KOKORO_MODEL_DIR      holds kokoro-v1.0.onnx and voices-v1.0.bin,
                        default ~/.local/share/kokoro-tts
"""

import json
import os
import shutil
import socket
import subprocess
import sys
import time

IDLE_EXIT = 1800
SOCKET = os.path.join(os.environ.get("TMPDIR", "/tmp"), f"claude-kokoro-{os.getuid()}.sock")
MODEL_DIR = os.environ.get("KOKORO_MODEL_DIR", os.path.expanduser("~/.local/share/kokoro-tts"))

TOOL_PHRASES = {
    "Read": "Reading {file}",
    "Edit": "Editing {file}",
    "MultiEdit": "Editing {file}",
    "Write": "Writing {file}",
    "NotebookEdit": "Editing notebook {file}",
    "Grep": "Searching files",
    "Glob": "Searching files",
    "WebFetch": "Fetching a page",
    "WebSearch": "Searching the web",
    "Agent": "Starting an agent",
    "Task": "Starting an agent",
    "TodoWrite": "Updating the task list",
    "AskUserQuestion": "I have a question",
    "ExitPlanMode": "Plan ready",
}
INTERRUPTING = {"Stop": "Done", "Notification": "Needs your attention"}


def phrase(event: dict) -> str:
    name = event.get("hook_event_name", "")
    if name in INTERRUPTING:
        return INTERRUPTING[name]
    tool = event.get("tool_name") or "an action"
    args = event.get("tool_input") or {}
    if tool == "Bash":
        # First word of the command: "Running git"
        words = str(args.get("command", "")).split(maxsplit=1)
        return f"Running {words[0] if words else 'a command'}"
    if tool == "Skill":
        return f"Running skill {args.get('skill', '')}".strip()
    if tool.startswith("mcp__"):
        return f"Calling tool {tool.rsplit('__', 1)[-1]}"
    if tool in TOOL_PHRASES:
        path = args.get("file_path") or args.get("notebook_path") or args.get("path") or ""
        return TOOL_PHRASES[tool].format(file=os.path.basename(path) or "a file")
    return f"Running {tool}"


def speaker(event: dict) -> str:
    """The project (git repo or folder name), plus the subagent type when a subagent made the call."""
    cwd = event.get("cwd") or os.getcwd()
    root = subprocess.run(
        ["git", "-C", cwd, "rev-parse", "--show-toplevel"], capture_output=True, text=True, check=False
    ).stdout.strip()
    name = os.path.basename(root or cwd.rstrip("/"))
    if agent := event.get("agent_type"):
        name = f"{name}, agent {agent}"
    return name


def send(message: bytes) -> bool:
    with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as conn:
        try:
            conn.connect(SOCKET)
        except OSError:
            return False
        conn.sendall(message)
    return True


def hook() -> int:
    kokoro_tts = shutil.which("kokoro-tts")
    if not kokoro_tts:
        return 0
    try:
        event = json.load(sys.stdin)
    except ValueError:
        return 0

    # Return to Claude at once; speaking happens in a detached child
    if os.fork():
        return 0
    os.setsid()

    who = speaker(event)
    message = json.dumps({
        "text": f"{who}: {phrase(event)}" if who else phrase(event),
        "voice": os.environ.get("CLAUDE_KOKORO_VOICE", "af_heart"),
        "speed": float(os.environ.get("CLAUDE_KOKORO_SPEED", "1.0")),
        "volume": float(os.environ.get("CLAUDE_KOKORO_VOLUME", "0.5")),
        "interrupt": event.get("hook_event_name") in INTERRUPTING,
    }).encode()

    if not send(message):
        # The tool's own interpreter sits next to its entry point
        python = os.path.join(os.path.dirname(os.path.realpath(kokoro_tts)), "python")
        subprocess.Popen(
            [python, os.path.realpath(__file__), "--daemon"],
            stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
            start_new_session=True,
        )
        for _ in range(60):
            time.sleep(0.25)
            if send(message):
                break
    os._exit(0)


def daemon() -> int:
    import fcntl

    # Hooks fire in bursts and each may start a daemon; only the lock holder runs
    lock = open(SOCKET + ".lock", "w")  # noqa: SIM115 - held for the process lifetime
    try:
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
    except BlockingIOError:
        return 0

    try:
        os.unlink(SOCKET)
    except FileNotFoundError:
        pass
    server = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    server.bind(SOCKET)
    os.chmod(SOCKET, 0o600)
    server.listen(8)
    server.settimeout(IDLE_EXIT)

    # Listen before loading the model so callers queue instead of starting another daemon
    import sounddevice as sd
    from kokoro_onnx import Kokoro

    kokoro = Kokoro(os.path.join(MODEL_DIR, "kokoro-v1.0.onnx"), os.path.join(MODEL_DIR, "voices-v1.0.bin"))

    playing_until = 0.0
    try:
        while True:
            try:
                conn, _ = server.accept()
            except TimeoutError:
                return 0
            with conn:
                conn.settimeout(2)
                try:
                    msg = json.loads(conn.makefile().read())
                except (OSError, ValueError):
                    continue
            text = str(msg.get("text", "")).strip()
            if not text:
                continue
            if time.monotonic() < playing_until:
                if not msg.get("interrupt"):
                    continue
                sd.stop()
            samples, rate = kokoro.create(
                text,
                voice=msg.get("voice") or "af_heart",
                speed=float(msg.get("speed") or 1.0),
                lang="en-us",
            )
            volume = float(msg.get("volume", 1.0))
            if volume != 1.0:
                samples = (samples * volume).clip(-1.0, 1.0)
            sd.play(samples, rate)
            playing_until = time.monotonic() + len(samples) / rate
    finally:
        server.close()
        try:
            os.unlink(SOCKET)
        except FileNotFoundError:
            pass


if __name__ == "__main__":
    sys.exit(daemon() if sys.argv[1:] == ["--daemon"] else hook())
