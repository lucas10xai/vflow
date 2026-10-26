#!/bin/bash
# Gỡ /Applications/vflow.app: thoát nhẹ nhàng rồi xoá. KHÔNG đụng ~/.vflow (token, từ điển, lịch sử).
# Dùng: client/scripts/uninstall-app.sh
set -euo pipefail

DEST_APP="/Applications/vflow.app"

if [ ! -d "$DEST_APP" ]; then
  echo "Không có $DEST_APP — không có gì để gỡ."
  exit 0
fi

echo "• thoát vflow đang chạy từ $DEST_APP (nếu có)…"
pids="$(pgrep -f 'VFlow\.app/Contents/MacOS/VFlow' || true)"
for pid in $pids; do
  exe="$(ps -p "$pid" -o comm= 2>/dev/null || true)"
  case "$exe" in
    "$DEST_APP"/*)
      echo "  thoát nhẹ nhàng: $exe (pid $pid)…"
      osascript -e "tell application \"System Events\"" \
                -e "  if exists (first process whose unix id is $pid) then" \
                -e "    quit (first process whose unix id is $pid)" \
                -e "  end if" \
                -e "end tell" >/dev/null 2>&1 || true
      waited=0
      while kill -0 "$pid" 2>/dev/null && [ "$waited" -lt 10 ]; do
        sleep 1
        waited=$((waited + 1))
      done
      if kill -0 "$pid" 2>/dev/null; then
        echo "  CẢNH BÁO: chưa thoát sau 10s — KHÔNG kill -9, dừng gỡ cài đặt. Thoát thủ công rồi chạy lại." >&2
        exit 1
      fi
      ;;
    *)
      echo "  bỏ qua tiến trình không thuộc $DEST_APP: $exe (pid $pid)"
      ;;
  esac
done

echo "• xoá ${DEST_APP}…"
rm -rf "$DEST_APP"
echo "Xong. Dữ liệu người dùng ở ~/.vflow (token, từ điển, lịch sử, cấu hình) KHÔNG bị đụng tới."
