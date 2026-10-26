#!/usr/bin/env bash
# Dừng máy chủ do run.sh khởi động (chỉ đúng pid trong server.pid).
set -euo pipefail
BASE="${VFLOW_BASE:-$HOME/vflow-phowhisper}"
PIDFILE="$BASE/server.pid"
[[ -f "$PIDFILE" ]] || { echo "Không có $PIDFILE: không chạy"; exit 0; }
PID="$(cat "$PIDFILE")"
if kill -0 "$PID" 2>/dev/null && grep -q "server.py" "/proc/$PID/cmdline" 2>/dev/null; then
  kill "$PID"
  for _ in $(seq 20); do kill -0 "$PID" 2>/dev/null || break; sleep 0.5; done
  kill -0 "$PID" 2>/dev/null && { echo "pid $PID chưa dừng sau 10 s" >&2; exit 1; }
  echo "Đã dừng pid $PID"
else
  echo "pid $PID không còn chạy (hoặc không phải server.py)"
fi
rm -f "$PIDFILE"
