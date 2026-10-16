#!/bin/sh
# Restart Headroom proxy with tuned env; fall back to previous settings if it doesn't come up healthy.
PY=$HOME/.local/share/uv/tools/headroom-ai/bin/python
LOG=$HOME/.headroom/logs/proxy-stdio-8787.log
start() { nohup env "$@" "$PY" -m headroom.cli proxy --port 8787 --workers 1 >>"$LOG" 2>&1 & }
wait_healthy() { for i in $(seq 1 90); do curl -sf -m2 http://127.0.0.1:8787/health >/dev/null && return 0; sleep 1; done; return 1; }
pkill -f 'headroom.cli proxy --port 8787'; sleep 2
start HEADROOM_KOMPRESS_BACKEND=onnx_coreml
wait_healthy && { echo "tuned proxy healthy"; exit 0; }
echo "tuned proxy failed, reverting"
pkill -f 'headroom.cli proxy --port 8787'; sleep 2
cp "$HOME/.headroom/settings.json.bak-20261015" "$HOME/.headroom/settings.json"
start HEADROOM_KOMPRESS_BACKEND=auto
wait_healthy && echo "reverted proxy healthy"
