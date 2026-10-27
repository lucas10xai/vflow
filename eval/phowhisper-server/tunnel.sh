#!/usr/bin/env bash
# Chạy trên Mac: mở SSH tunnel 127.0.0.1:7612 -> gpu-host:127.0.0.1:7612 (chạy tiền cảnh, Ctrl-C để đóng).
set -euo pipefail
PORT="${VFLOW_REMOTE_PORT:-7612}"
HOST="${VFLOW_REMOTE_HOST:-gpu-host}" # alias SSH của máy GPU (đặt trong ~/.ssh/config) hoặc truyền tên thật
if lsof -nP -iTCP:"$PORT" -sTCP:LISTEN >/dev/null 2>&1; then
  echo "Cổng $PORT trên Mac đã có tiến trình nghe:" >&2
  lsof -nP -iTCP:"$PORT" -sTCP:LISTEN >&2
  exit 1
fi
echo "Mở tunnel 127.0.0.1:$PORT -> $HOST:127.0.0.1:$PORT"
# IPQoS=cs0: mặc định ssh -N đánh dấu gói "interactive" (DSCP EF); một số đường mạng tới máy GPU bóp các gói này
# (đo 2026-10-26: 478 KB mất ~33 s, với cs0 còn ~0,8 s).
exec ssh -N -o ExitOnForwardFailure=yes -o ServerAliveInterval=30 -o IPQoS=cs0 \
  -L "127.0.0.1:$PORT:127.0.0.1:$PORT" "$HOST"
