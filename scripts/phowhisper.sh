#!/usr/bin/env bash
# phowhisper.sh — bật/tắt máy chủ PhoWhisper trên gpu-host và SSH tunnel từ Mac (chạy từ Mac).
#
#   scripts/phowhisper.sh up            kiểm VRAM → run.sh → chờ /healthz loaded:true (qua ssh) → mở tunnel nền
#   scripts/phowhisper.sh down          đóng tunnel → stop.sh trên gpu-host
#   scripts/phowhisper.sh status        trạng thái tunnel, máy chủ, VRAM
#   scripts/phowhisper.sh exec -- CMD…  chạy CMD với VFLOW_REMOTE_TOKEN lấy từ gpu-host (chỉ trong env tiến trình con)
#
# GPU dùng chung với dịch vụ khác: `up` trước khi đo, `down` ngay sau khi đo; không để chạy nền.
# Token không bao giờ được in, ghi đĩa trên Mac hay ghi log.
#
# Biến môi trường (tuỳ chọn):
#   VFLOW_GPU_HOST            host SSH (mặc định gpu-host)
#   VFLOW_REMOTE_PORT         cổng (mặc định 7612, cả hai đầu tunnel)
#   VFLOW_GPU_MAX_OTHER_MIB   VRAM tối đa dịch vụ khác được chiếm để vẫn `up` (mặc định 10240)
#   VFLOW_HEALTH_TIMEOUT_S    thời gian chờ model tải (mặc định 180)
#   VFLOW_HOME                thư mục pid tunnel (mặc định ~/.vflow)
#
# Mã thoát: 0 thành công, 1 lỗi, 2 sai cú pháp, 3 từ chối vì dịch vụ khác đang chiếm VRAM, 255 lỗi SSH.
set -euo pipefail

HOST="${VFLOW_GPU_HOST:-gpu-host}"
PORT="${VFLOW_REMOTE_PORT:-7612}"
MAX_OTHER_MIB="${VFLOW_GPU_MAX_OTHER_MIB:-10240}"
HEALTH_TIMEOUT_S="${VFLOW_HEALTH_TIMEOUT_S:-180}"
VHOME="${VFLOW_HOME:-$HOME/.vflow}"
PIDFILE="$VHOME/phowhisper-tunnel.pid"
REMOTE_BASE='~/vflow-phowhisper'
SSH=(ssh -o BatchMode=yes -o ConnectTimeout=10 "$HOST")

die() { local code="$1"; shift; printf 'phowhisper.sh: %s\n' "$*" >&2; exit "$code"; }
usage() { sed -n '2,8p' "$0" | sed 's/^# \{0,1\}//' >&2; exit 2; }

for v in PORT MAX_OTHER_MIB HEALTH_TIMEOUT_S; do
  [[ "${!v}" =~ ^[0-9]+$ ]] || die 2 "$v phải là số nguyên"
done

# pid tunnel còn sống và đúng là ssh -L của cổng này? (in pid nếu đúng)
tunnel_pid() {
  [[ -f "$PIDFILE" ]] || return 1
  local pid; pid="$(cat "$PIDFILE")"
  [[ "$pid" =~ ^[0-9]+$ ]] || return 1
  local cmd; cmd="$(ps -p "$pid" -o command= 2>/dev/null || true)"
  [[ "$cmd" == *ssh* && "$cmd" == *"127.0.0.1:$PORT:127.0.0.1:$PORT"* ]] || return 1
  echo "$pid"
}

local_listening() { lsof -nP -iTCP:"$PORT" -sTCP:LISTEN >/dev/null 2>&1; }

# In "used_total_mib our_mib" (our = VRAM của server.pid nếu đang chạy). Lỗi ⇒ mã ≠ 0.
gpu_usage() {
  local out
  out="$("${SSH[@]}" "nvidia-smi --query-gpu=memory.used --format=csv,noheader,nounits | head -1; \
    p=\$(cat $REMOTE_BASE/server.pid 2>/dev/null || true); \
    nvidia-smi --query-compute-apps=pid,used_memory --format=csv,noheader,nounits | awk -F', *' -v p=\"\$p\" '\$1==p{s+=\$2} END{print s+0}'")" || return 1
  local used our
  used="$(sed -n 1p <<<"$out" | tr -d ' ')"
  our="$(sed -n 2p <<<"$out" | tr -d ' ')"
  [[ "$used" =~ ^[0-9]+$ && "$our" =~ ^[0-9]+$ ]] || return 1
  echo "$used $our"
}

remote_health() { "${SSH[@]}" "curl -s -m 3 http://127.0.0.1:$PORT/healthz" 2>/dev/null || true; }

cmd_up() {
  if pid="$(tunnel_pid)"; then
    echo "Tunnel đã mở (pid $pid)."
  elif local_listening; then
    lsof -nP -iTCP:"$PORT" -sTCP:LISTEN >&2 || true
    die 1 "cổng $PORT trên Mac đã có tiến trình khác nghe (không phải tunnel của script này)"
  fi

  local usage used our other
  usage="$(gpu_usage)" || die 1 "không đọc được nvidia-smi trên $HOST: không xác định được VRAM, từ chối khởi động"
  read -r used our <<<"$usage"
  other=$((used - our))
  echo "VRAM đang dùng trên $HOST: ${used} MiB (dịch vụ khác ${other} MiB, vflow ${our} MiB)."
  if (( other > MAX_OTHER_MIB )); then
    die 3 "dịch vụ khác đang chiếm ${other} MiB VRAM (> ${MAX_OTHER_MIB} MiB): từ chối khởi động PhoWhisper"
  fi

  "${SSH[@]}" "bash $REMOTE_BASE/app/run.sh" || die 1 "run.sh trên $HOST lỗi"
  echo "Chờ /healthz loaded:true (tối đa ${HEALTH_TIMEOUT_S} s)…"
  if ! "${SSH[@]}" "end=\$((SECONDS+$HEALTH_TIMEOUT_S)); while (( SECONDS < end )); do \
      curl -s -m 3 http://127.0.0.1:$PORT/healthz | grep -Eq '\"loaded\": *true' && exit 0; sleep 2; done; exit 1"; then
    echo "Máy chủ chưa sẵn sàng; /healthz: $(remote_health)" >&2
    "${SSH[@]}" "bash $REMOTE_BASE/app/stop.sh" >&2 || true
    die 1 "model không tải xong trong ${HEALTH_TIMEOUT_S} s (đã chạy stop.sh để trả GPU)"
  fi
  echo "Máy chủ sẵn sàng: $(remote_health)"

  if ! tunnel_pid >/dev/null; then
    mkdir -p "$VHOME"
    # IPQoS=cs0: xem eval/phowhisper-server/tunnel.sh (mặc định của ssh -N làm tải lên chậm ~40 lần).
    nohup ssh -N -o BatchMode=yes -o ExitOnForwardFailure=yes -o ServerAliveInterval=30 -o IPQoS=cs0 \
      -L "127.0.0.1:$PORT:127.0.0.1:$PORT" "$HOST" >/dev/null 2>&1 </dev/null &
    local tpid=$!
    echo "$tpid" >"$PIDFILE"
    local ok=0
    for _ in $(seq 40); do
      kill -0 "$tpid" 2>/dev/null || break
      if local_listening; then ok=1; break; fi
      sleep 0.25
    done
    if (( ok == 0 )); then
      kill "$tpid" 2>/dev/null || true
      rm -f "$PIDFILE"
      die 1 "không mở được tunnel 127.0.0.1:$PORT (máy chủ vẫn chạy: nhớ 'scripts/phowhisper.sh down')"
    fi
    echo "Đã mở tunnel 127.0.0.1:$PORT -> $HOST (pid $tpid, $PIDFILE)."
  fi
  cat <<EOF

Đặt token cho lệnh vflow (token KHÔNG được in ra; chỉ nằm trong biến môi trường):
  scripts/phowhisper.sh exec -- node bin/vflow.js compare --set <bộ> --models zipformer-vi-30m,phowhisper-large
hoặc trong shell hiện tại:
  export VFLOW_REMOTE_TOKEN="\$(ssh $HOST 'cat $REMOTE_BASE/token')"
Đo xong: scripts/phowhisper.sh down  (GPU dùng chung, đừng để chạy nền)
EOF
}

cmd_down() {
  local rc=0
  if pid="$(tunnel_pid)"; then
    kill "$pid" 2>/dev/null || true
    for _ in $(seq 20); do kill -0 "$pid" 2>/dev/null || break; sleep 0.25; done
    if kill -0 "$pid" 2>/dev/null; then echo "tunnel pid $pid chưa dừng" >&2; rc=1; else echo "Đã đóng tunnel (pid $pid)."; fi
  else
    echo "Không có tunnel do script này mở."
  fi
  [[ $rc -eq 0 ]] && rm -f "$PIDFILE"
  if local_listening; then
    echo "CẢNH BÁO: cổng $PORT trên Mac vẫn có tiến trình nghe:" >&2
    lsof -nP -iTCP:"$PORT" -sTCP:LISTEN >&2 || true
    rc=1
  fi
  "${SSH[@]}" "bash $REMOTE_BASE/app/stop.sh" || { echo "stop.sh trên $HOST lỗi" >&2; rc=1; }
  return $rc
}

cmd_status() {
  if pid="$(tunnel_pid)"; then echo "Tunnel: mở (pid $pid)"; else echo "Tunnel: đóng"; fi
  if local_listening; then echo "Cổng $PORT trên Mac: có tiến trình nghe"; else echo "Cổng $PORT trên Mac: không nghe"; fi
  local h; h="$(remote_health)"
  echo "Máy chủ trên $HOST: ${h:-không phản hồi (đã dừng?)}"
  local usage
  if usage="$(gpu_usage)"; then
    read -r used our <<<"$usage"
    echo "VRAM $HOST: ${used} MiB đang dùng (vflow ${our} MiB, dịch vụ khác $((used - our)) MiB)"
  else
    echo "VRAM $HOST: không xác định (nvidia-smi lỗi)"
  fi
}

cmd_exec() {
  [[ "${1:-}" == "--" ]] && shift
  [[ $# -gt 0 ]] || usage
  local token
  token="$("${SSH[@]}" "cat $REMOTE_BASE/token")" || die 1 "không đọc được token trên $HOST"
  [[ -n "$token" ]] || die 1 "token trên $HOST rỗng"
  VFLOW_REMOTE_TOKEN="$token" exec "$@"
}

case "${1:-}" in
  up) cmd_up ;;
  down) cmd_down ;;
  status) cmd_status ;;
  exec) shift; cmd_exec "$@" ;;
  *) usage ;;
esac
