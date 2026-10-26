#!/bin/bash
# Dựng bản đầy đủ (build-app.sh, có đóng gói engine) rồi cài vào /Applications/vflow.app.
# Dùng: client/scripts/install-app.sh
#
# - Thoát NHẸ NHÀNG (AppleScript quit, chờ tối đa 10s, KHÔNG kill -9) CHỈ các tiến trình vflow có
#   đường dẫn thực thi nằm trong client/build/VFlow.app hoặc /Applications/vflow.app — không đụng
#   Haynoi hay app nào khác.
# - Sao chép bằng `ditto`; nếu đã có bản cũ ở /Applications/vflow.app thì giữ một bản sao lưu .bak
#   ngoài /Applications (~/.vflow/backup/).
# - Không dùng sudo; thiếu quyền ghi /Applications thì DỪNG, không tự ý làm gì thêm.
# - Không tự mở app sau khi cài.
set -euo pipefail

CLIENT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SRC_APP="$CLIENT_DIR/build/VFlow.app"
DEST_APP="/Applications/vflow.app"
BACKUP_DIR="$HOME/.vflow/backup"
# shellcheck source=./lib-signing.sh
source "$CLIENT_DIR/scripts/lib-signing.sh"

echo "• dựng bản đầy đủ (build-app.sh)…"
"$CLIENT_DIR/scripts/build-app.sh"

# ── Thoát nhẹ nhàng các bản vflow đang chạy từ build cũ hoặc /Applications ──────────────────────
quit_running_instances() {
  local allowed_prefixes=("$SRC_APP" "$DEST_APP")
  local pids
  pids="$(pgrep -f 'VFlow\.app/Contents/MacOS/VFlow' || true)"
  [ -z "$pids" ] && return 0
  for pid in $pids; do
    local exe
    exe="$(ps -p "$pid" -o comm= 2>/dev/null || true)"
    [ -z "$exe" ] && continue
    local matched=0
    for prefix in "${allowed_prefixes[@]}"; do
      case "$exe" in
        "$prefix"/*) matched=1 ;;
      esac
    done
    if [ "$matched" != "1" ]; then
      echo "  bỏ qua tiến trình không thuộc vflow build/cài đặt: $exe (pid $pid)"
      continue
    fi
    echo "  thoát nhẹ nhàng: $exe (pid $pid)…"
    osascript -e "tell application \"System Events\"" \
              -e "  if exists (first process whose unix id is $pid) then" \
              -e "    quit (first process whose unix id is $pid)" \
              -e "  end if" \
              -e "end tell" >/dev/null 2>&1 || true
    local waited=0
    while kill -0 "$pid" 2>/dev/null && [ "$waited" -lt 10 ]; do
      sleep 1
      waited=$((waited + 1))
    done
    if kill -0 "$pid" 2>/dev/null; then
      echo "  CẢNH BÁO: $exe (pid $pid) chưa thoát sau 10s — KHÔNG kill -9, bỏ qua (anh tự thoát thủ công nếu cần)." >&2
    fi
  done
}
echo "• thoát các bản vflow đang chạy (nếu có, chỉ ${SRC_APP} hoặc ${DEST_APP})…"
quit_running_instances

# ── Quyền ghi /Applications ──────────────────────────────────────────────────────────────────
if [ ! -w /Applications ]; then
  echo "DỪNG: không có quyền ghi /Applications. Không dùng sudo tự động — cần chủ dự án cấp quyền hoặc cài thủ công." >&2
  exit 1
fi

# ── Sao lưu bản cũ (nếu có) ra ngoài /Applications rồi thay thế ─────────────────────────────────
if [ -d "$DEST_APP" ]; then
  mkdir -p "$BACKUP_DIR"
  BACKUP_PATH="$BACKUP_DIR/vflow.app.bak.$(date +%Y%m%d-%H%M%S)"
  echo "• đã có bản cũ ở ${DEST_APP} — sao lưu sang ${BACKUP_PATH}…"
  ditto "$DEST_APP" "$BACKUP_PATH"
  rm -rf "$DEST_APP"
fi

echo "• sao chép vào $DEST_APP (ditto)…"
ditto "$SRC_APP" "$DEST_APP"
xattr -dr com.apple.quarantine "$DEST_APP" 2>/dev/null || true

echo "• kiểm chữ ký…"
codesign --verify --deep --strict "$DEST_APP"
echo "  OK"

echo "Xong: $DEST_APP ($(du -sh "$DEST_APP" | cut -f1))"
case "$(vflow_signing_state)" in
  valid)
    echo "LƯU Ý: đã ký bằng danh tính ổn định \"$VFLOW_SIGN_IDENTITY_NAME\" (xem build-app.sh) — quyền macOS (Micro/Theo dõi đầu vào/Trợ năng) THƯỜNG được giữ qua các lần cài lại, không đảm bảo tuyệt đối."
    ;;
  untrusted)
    echo "LƯU Ý: có chứng chỉ \"$VFLOW_SIGN_IDENTITY_NAME\" trong keychain nhưng CHƯA được tin cậy ⇒ bản cài vào /Applications vẫn ký AD-HOC, macOS sẽ đòi cấp quyền macOS (Micro/Theo dõi đầu vào/Trợ năng) lại. Chạy client/scripts/make-signing-identity.sh --yes để THÊM tin cậy (không cần tạo lại)."
    ;;
  none)
    echo "LƯU Ý: chữ ký ad-hoc của bản trong /Applications khác bản trong client/build (ký lại mỗi lần cài) nên macOS sẽ đòi cấp quyền macOS (Micro/Theo dõi đầu vào/Trợ năng) lại cho bản này — đó là bản dùng thật. Chạy client/scripts/make-signing-identity.sh --yes để tránh việc này."
    ;;
esac
