#!/bin/bash
# Dựng bản đầy đủ (build-app.sh, có đóng gói engine) rồi cài vào /Applications/vflow.app.
# Dùng: client/scripts/install-app.sh
#
# - Thoát NHẸ NHÀNG (AppleScript `tell application id "org.aios.vflow" to quit`, chờ tối đa 15s,
#   KHÔNG kill -9) CHỈ khi có tiến trình vflow có đường dẫn thực thi nằm trong client/build/VFlow.app
#   hoặc /Applications/vflow.app — không đụng Haynoi hay app nào khác. Trước đây gửi quit qua
#   `System Events … quit (first process whose unix id is N)`: đã đo thật KHÔNG làm vflow thoát (script
#   chờ hết 15s rồi từ chối cài đè đúng thiết kế, nhưng vô dụng vì tiến trình chưa hề thoát) — gửi theo
#   BUNDLE ID mới thoát được (~1s). Sau khi yêu cầu thoát, CHỜ rồi KIỂM LẠI bằng pgrep rằng cả tiến
#   trình vflow VÀ engine con của nó đã thoát hẳn; còn sống ⇒ DỪNG (mã khác 0), KHÔNG chép đè, KHÔNG
#   kill -9 (trước đây script chỉ in cảnh báo rồi vẫn tiếp tục chép đè — đã đo thấy "báo OK" dù tiến
#   trình cũ vẫn sống, sửa ở đây).
# - Sao chép bằng `ditto`; nếu đã có bản cũ ở /Applications/vflow.app thì giữ CHỈ MỘT bản sao lưu gần
#   nhất ngoài /Applications (~/.vflow/backup/, xoá các bản `vflow.app.bak.*` cũ hơn do chính script
#   này tạo).
# - Không dùng sudo; thiếu quyền ghi /Applications thì DỪNG, không tự ý làm gì thêm.
# - Nếu TRƯỚC ĐÓ có bản đang chạy (vừa thoát nhẹ nhàng ở bước trên) thì SAU KHI cài xong tự mở lại
#   bản mới và in PID + thời điểm bắt đầu.
#
# Biến môi trường (chỉ dùng cho test tự động bằng shim, KHÔNG dùng khi cài thật):
#   VFLOW_INSTALL_SRC_APP, VFLOW_INSTALL_DEST_APP, VFLOW_INSTALL_BACKUP_DIR — đổi đường dẫn.
#   VFLOW_INSTALL_SKIP_BUILD=1 — bỏ qua bước build-app.sh (test tự chuẩn bị sẵn SRC_APP giả).
#   VFLOW_INSTALL_NO_REOPEN=1 — không tự mở lại sau khi cài (test không có GUI thật để `open`).
set -euo pipefail

CLIENT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SRC_APP="${VFLOW_INSTALL_SRC_APP:-$CLIENT_DIR/build/VFlow.app}"
DEST_APP="${VFLOW_INSTALL_DEST_APP:-/Applications/vflow.app}"
BACKUP_DIR="${VFLOW_INSTALL_BACKUP_DIR:-$HOME/.vflow/backup}"
# Mặc định 15s (thật); test tự động rút ngắn bằng VFLOW_INSTALL_QUIT_TIMEOUT_SECONDS để không phải
# chờ 15s thật cho kịch bản "tiến trình cứng đầu".
QUIT_TIMEOUT_SECONDS="${VFLOW_INSTALL_QUIT_TIMEOUT_SECONDS:-15}"
# shellcheck source=./lib-signing.sh
source "$CLIENT_DIR/scripts/lib-signing.sh"

if [ "${VFLOW_INSTALL_SKIP_BUILD:-0}" = "1" ]; then
  echo "• VFLOW_INSTALL_SKIP_BUILD=1: bỏ qua build-app.sh (chỉ dùng khi kiểm tự động)"
else
  echo "• dựng bản đầy đủ (build-app.sh)…"
  "$CLIENT_DIR/scripts/build-app.sh"
fi

# ── Cảnh báo (KHÔNG chặn): cài bản KHÔNG kèm model mà máy cũng chưa có model ─────────────────────────
# Bản kèm model chép model sang ~/.vflow/models ở lần chạy đầu; bản không kèm model thì chỉ chạy ngay nếu
# model đã có ở đó, còn không thì lần mở đầu sẽ hiện màn hình xin tải (≈ 26 MB, phải đồng ý giấy phép).
MODEL_ID="zipformer-vi-30m"
DATA_HOME="${VFLOW_HOME:-$HOME/.vflow}"
if [ ! -f "$SRC_APP/Contents/Resources/models/$MODEL_ID/manifest.json" ] \
   && [ ! -f "$DATA_HOME/models/$MODEL_ID/manifest.json" ]; then
  echo "CẢNH BÁO: đang cài bản KHÔNG kèm model và $DATA_HOME/models/$MODEL_ID cũng chưa có." >&2
  echo "          Lần mở đầu vflow sẽ hiện màn hình xin tải model (≈ 26 MB, giấy phép CC-BY-NC-ND-4.0, phải bấm đồng ý);" >&2
  echo "          chưa tải thì chưa đọc chính tả được." >&2
fi

# ── Thoát nhẹ nhàng các bản vflow đang chạy từ build cũ hoặc /Applications, rồi XÁC NHẬN đã thoát ──
# Khớp cả "VFlow.app" (dựng từ client/build) lẫn "vflow.app" (đã cài ở /Applications) — case-
# insensitive (-i) vì ditto tạo DEST_APP đúng theo tên viết hoa/thường được truyền vào, khác với tên
# thư mục nguồn "VFlow.app" trong client/build.
WAS_RUNNING=0
quit_running_instances() {
  local allowed_prefixes=("$SRC_APP" "$DEST_APP")
  local pids
  pids="$(pgrep -if 'vflow\.app/contents/macos/vflow' || true)"
  [ -z "$pids" ] && return 0

  local to_quit=()
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
    to_quit+=("$pid")
  done
  [ ${#to_quit[@]} -eq 0 ] && return 0
  WAS_RUNNING=1

  # Bắt pid của engine con NGAY (trước khi gửi quit) — sau khi tiến trình cha thoát, engine mồ côi
  # đổi ppid về 1 nên không còn dò được bằng `pgrep -P`; bắt trước để vẫn `kill -0` đúng pid sau này.
  local engine_pids=()
  for pid in "${to_quit[@]}"; do
    while IFS= read -r epid; do
      [ -n "$epid" ] && engine_pids+=("$epid")
    done < <(pgrep -P "$pid" -f 'vflow\.js serve' 2>/dev/null || true)
  done

  # Thoát bằng BUNDLE ID ("tell application id org.aios.vflow to quit"), KHÔNG dùng System Events
  # theo unix id: đã đo thật — `System Events … quit (first process whose unix id is N)` KHÔNG làm
  # vflow thoát (chờ hết ${QUIT_TIMEOUT_SECONDS}s rồi script từ chối cài đè, đúng thiết kế nhưng vô
  # dụng vì tiến trình chưa hề thoát), còn `tell application id "org.aios.vflow" to quit` thoát được
  # sau ~1s. Bundle id CỐ ĐỊNH "org.aios.vflow" cho cả bản dựng từ client/build và bản đã cài ở
  # /Applications (xem build-app.sh, CFBundleIdentifier) — gọi MỘT LẦN là đủ, quit theo id tự tác
  # động lên mọi tiến trình cùng bundle id, không cần lặp theo từng pid.
  echo "  thoát nhẹ nhàng (bundle id org.aios.vflow)…"
  osascript -e 'tell application id "org.aios.vflow" to quit' >/dev/null 2>&1 || true

  echo "  chờ tối đa ${QUIT_TIMEOUT_SECONDS}s để thoát hẳn (tiến trình vflow + engine con)…"
  local waited=0
  while [ "$waited" -lt "$QUIT_TIMEOUT_SECONDS" ]; do
    local still_alive=0
    for pid in "${to_quit[@]}" "${engine_pids[@]:-}"; do
      [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null && still_alive=1
    done
    [ "$still_alive" -eq 0 ] && break
    sleep 1
    waited=$((waited + 1))
  done

  local failed=0
  for pid in "${to_quit[@]}"; do
    if kill -0 "$pid" 2>/dev/null; then
      echo "LỖI: tiến trình vflow (pid $pid) VẪN CÒN SỐNG sau ${QUIT_TIMEOUT_SECONDS}s." >&2
      failed=1
    fi
  done
  for pid in "${engine_pids[@]:-}"; do
    [ -z "$pid" ] && continue
    if kill -0 "$pid" 2>/dev/null; then
      echo "LỖI: engine con (pid $pid, vflow.js serve) VẪN CÒN SỐNG sau ${QUIT_TIMEOUT_SECONDS}s." >&2
      failed=1
    fi
  done
  if [ "$failed" = "1" ]; then
    echo "DỪNG: không cài đè khi tiến trình vflow cũ (hoặc engine con) chưa thoát hẳn — KHÔNG kill -9, KHÔNG chép đè. Hãy tự thoát vflow (⌘Q) rồi chạy lại install-app.sh." >&2
    exit 1
  fi
  echo "  đã thoát hẳn."
}
echo "• thoát các bản vflow đang chạy (nếu có, chỉ ${SRC_APP} hoặc ${DEST_APP})…"
quit_running_instances

# ── Quyền ghi /Applications (hoặc thư mục đích, khi test) ──────────────────────────────────────
DEST_PARENT="$(dirname "$DEST_APP")"
if [ ! -w "$DEST_PARENT" ]; then
  echo "DỪNG: không có quyền ghi $DEST_PARENT. Không dùng sudo tự động — cần chủ dự án cấp quyền hoặc cài thủ công." >&2
  exit 1
fi

# ── Sao lưu bản cũ (nếu có) ra ngoài /Applications rồi thay thế ─────────────────────────────────
if [ -d "$DEST_APP" ]; then
  mkdir -p "$BACKUP_DIR"
  BACKUP_PATH="$BACKUP_DIR/vflow.app.bak.$(date +%Y%m%d-%H%M%S)"
  echo "• đã có bản cũ ở ${DEST_APP} — sao lưu sang ${BACKUP_PATH}…"
  ditto "$DEST_APP" "$BACKUP_PATH"
  echo "  dung lượng bản sao lưu: $(du -sh "$BACKUP_PATH" | cut -f1)"
  rm -rf "$DEST_APP"

  # Giữ CHỈ MỘT bản sao lưu gần nhất (bản vừa tạo) — xoá mọi bản `vflow.app.bak.*` cũ hơn do chính
  # script này tạo trong $BACKUP_DIR.
  for old in "$BACKUP_DIR"/vflow.app.bak.*; do
    [ -e "$old" ] || continue
    [ "$old" = "$BACKUP_PATH" ] && continue
    echo "  xoá bản sao lưu cũ: $old"
    rm -rf "$old"
  done
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

# ── Có bản đang chạy trước khi cài ⇒ tự mở lại bản mới, in PID + thời điểm bắt đầu ──────────────
if [ "$WAS_RUNNING" = "1" ] && [ "${VFLOW_INSTALL_NO_REOPEN:-0}" != "1" ]; then
  echo "• trước đó có bản đang chạy — mở lại $DEST_APP…"
  open "$DEST_APP"
  NEW_PID=""
  for _ in $(seq 1 10); do
    NEW_PID="$(pgrep -if 'vflow\.app/contents/macos/vflow' | head -1 || true)"
    [ -n "$NEW_PID" ] && break
    sleep 1
  done
  if [ -n "$NEW_PID" ]; then
    START="$(ps -p "$NEW_PID" -o lstart= 2>/dev/null || echo "?")"
    echo "  đã mở lại: pid $NEW_PID, bắt đầu lúc $START"
  else
    echo "  CẢNH BÁO: đã gọi \`open\` nhưng chưa thấy tiến trình mới sau 10s — kiểm tay." >&2
  fi
fi
