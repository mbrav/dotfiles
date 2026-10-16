#!/bin/sh
# Restart Headroom proxy with tuned env; fall back to previous settings if it doesn't come up healthy.
PY=$HOME/.local/share/uv/tools/headroom-ai/bin/python
WORKSPACE=${HEADROOM_WORKSPACE_DIR:-$HOME/.config/headroom}
PORT=${HEADROOM_PORT:-8787}
WORKERS=${HEADROOM_WORKERS:-1}
LOG=$WORKSPACE/logs/proxy-stdio-$PORT.log
BAK=$WORKSPACE/settings.json.bak-20261015
mkdir -p "$WORKSPACE/logs"
start() { nohup env "$@" "$PY" -m headroom.cli proxy --port "$PORT" --workers "$WORKERS" >>"$LOG" 2>&1 & }
wait_healthy() {
  for _ in $(seq 1 90); do
    curl -sf -m2 "http://127.0.0.1:$PORT/health" >/dev/null && return 0
    sleep 1
  done
  return 1
}
pkill -f "headroom.cli proxy --port $PORT"
sleep 2
start HEADROOM_KOMPRESS_BACKEND=onnx_coreml
wait_healthy && {
  echo "tuned proxy healthy"
  exit 0
}
echo "tuned proxy failed, reverting"
pkill -f "headroom.cli proxy --port $PORT"
sleep 2
# Only restore the backup if it is actually there; otherwise keep current settings
if [ -f "$BAK" ]; then
  cp "$BAK" "$WORKSPACE/settings.json"
else
  echo "no backup at $BAK, keeping current settings.json"
fi
start HEADROOM_KOMPRESS_BACKEND=auto
wait_healthy && echo "reverted proxy healthy"
