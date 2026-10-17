#!/usr/bin/env bash
# SessionStart hook: make sure the Headroom proxy is up before Claude routes through it.
#
# No-op when the proxy is already healthy. Deliberately never kills anything: the
# proxy's worker processes all share the cmdline ".../bin/headroom", so a pkill
# pattern cannot tell a wedged proxy from a busy one serving another session.
# Use "$HEADROOM_WORKSPACE_DIR/restart-proxy.sh" for a forced restart.
#
# Always exits 0 - a proxy problem should not stop the session from starting.

set -o pipefail

# Same environment the shells get: HOST/PORT from ~/.profile, dirs from _aliases.
# Sourced before `set -u`: on Debian ~/.profile pulls in ~/.bashrc, whose
# `[ -z "$PS1" ]` guard aborts under nounset in a non-interactive shell.
# shellcheck source=/dev/null
[ -f "$HOME/.profile" ] && . "$HOME/.profile"
# shellcheck source=/dev/null
[ -f "$HOME/.config/scripts/_aliases" ] && . "$HOME/.config/scripts/_aliases"

set -u

# Hooks do not inherit the interactive PATH
PATH="$HOME/.local/bin:$PATH"

host="${HEADROOM_HOST:-127.0.0.1}"
port="${HEADROOM_PORT:-8787}"
workspace="${HEADROOM_WORKSPACE_DIR:-$HOME/.headroom}"
log="$workspace/logs/proxy-stdio-$port.log"
lock="$workspace/.ensure-proxy-$port.lock"

# Launch-time settings. ":=" so anything already exported by ~/.profile or
# _aliases wins. These pin current upstream defaults rather than change
# behaviour: all three protect Anthropic prompt-cache hits or stop internal
# x-headroom-* headers reaching the provider, so a future default flip
# should not silently cost cache hits or leak headers.
: "${HEADROOM_BETA_HEADER_STICKY:=enabled}"
: "${HEADROOM_PROXY_PYTHON_FORWARDER_MODE:=byte_faithful}"
: "${HEADROOM_STRIP_INTERNAL_HEADERS:=enabled}"
: "${HEADROOM_PROXY_STRIP_INTERNAL_HEADERS:=enabled}"
export HEADROOM_BETA_HEADER_STICKY HEADROOM_PROXY_PYTHON_FORWARDER_MODE
export HEADROOM_STRIP_INTERNAL_HEADERS HEADROOM_PROXY_STRIP_INTERNAL_HEADERS

healthy() { curl -sf -m 2 "http://$host:$port/health" >/dev/null 2>&1; }

if ! command -v headroom >/dev/null; then
  # Remote proxy (HEADROOM_HOST set, no CLI here): nothing to start, only report
  [ -n "${HEADROOM_HOST:-}" ] && ! healthy && echo "Remote Headroom proxy at $host:$port is unhealthy"
  exit 0
fi
healthy && exit 0

# Port already taken: either still starting up, or wedged. Give it a few seconds
# rather than spawning a second proxy that cannot bind anyway.
if lsof -nP -iTCP:"$port" -sTCP:LISTEN >/dev/null 2>&1; then
  for _ in 1 2 3 4 5; do
    sleep 1
    healthy && exit 0
  done
  echo "Headroom proxy on $host:$port is listening but unhealthy; run $workspace/restart-proxy.sh"
  exit 0
fi

# Atomic guard so parallel sessions do not race to spawn duplicate proxies
mkdir "$lock" 2>/dev/null || exit 0
trap 'rmdir "$lock" 2>/dev/null' EXIT

mkdir -p "$(dirname "$log")"

# The proxy appends forever; keep one generation so logs cannot fill the disk
if [ -f "$log" ] && [ "$(wc -c <"$log")" -gt 10485760 ]; then
  mv -f "$log" "$log.1"
fi
nohup headroom proxy --port "$port" --workers "${HEADROOM_WORKERS:-1}" >>"$log" 2>&1 &

for _ in 1 2 3 4 5 6 7; do
  sleep 1
  healthy && {
    echo "Headroom proxy started on $host:$port"
    exit 0
  }
done

echo "Headroom proxy did not come up within 7s; see $log"
exit 0
