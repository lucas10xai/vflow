#!/usr/bin/env bash
# Chạy máy chủ PhoWhisper nền trên gpu-host (không sudo). Mọi thứ nằm trong ~/vflow-phowhisper.
# Token: đặt VFLOW_REMOTE_TOKEN, hoặc để trong ~/vflow-phowhisper/token (quyền 0600).
set -euo pipefail
BASE="${VFLOW_BASE:-$HOME/vflow-phowhisper}"
PIDFILE="$BASE/server.pid"
LOG="$BASE/logs/server.log"
HERE="$(cd "$(dirname "$0")" && pwd)"

if [[ -f "$PIDFILE" ]] && kill -0 "$(cat "$PIDFILE")" 2>/dev/null; then
  echo "Đang chạy (pid $(cat "$PIDFILE"))"; exit 0
fi
if [[ -z "${VFLOW_REMOTE_TOKEN:-}" ]]; then
  [[ -f "$BASE/token" ]] || { echo "Thiếu token: đặt VFLOW_REMOTE_TOKEN hoặc tạo $BASE/token (0600)" >&2; exit 1; }
  export VFLOW_REMOTE_TOKEN_FILE="$BASE/token"
fi
export VFLOW_MODEL_DIR="${VFLOW_MODEL_DIR:-$BASE/models/ct2/PhoWhisper-large-fp16}"
export VFLOW_BACKEND="${VFLOW_BACKEND:-ct2}"
export HF_HOME="$BASE/hf-cache"
export HF_HUB_OFFLINE=1
mkdir -p "$BASE/logs"
cd "$HERE"
nohup "$BASE/venv/bin/python" -B -u server.py >>"$LOG" 2>&1 </dev/null &
echo $! >"$PIDFILE"
echo "Đã chạy pid $(cat "$PIDFILE"), log: $LOG (chờ /healthz loaded:true)"
