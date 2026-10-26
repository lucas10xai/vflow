#!/bin/bash
# Chụp TOÀN BỘ màn hình chính của vflow ra PNG — sáng + tối — để xem/so sánh bố cục mà KHÔNG BAO GIỜ
# hiện cửa sổ lên màn hình thật (xem client/README.md mục "Công cụ chụp ảnh ngoài màn hình" và
# docs/specs/2026-10-26-vflow-design.md — sự cố U2 đã xảy ra: tuyệt đối không dùng screencapture).
#
# Dùng: client/scripts/snapshot.sh <thư mục đầu ra>
#
# Dựng VFlow (swift build) nếu cần, tạo HAI VFLOW_HOME CÔ LẬP tạm thời (không đụng ~/.vflow thật):
#   - "full":  có dữ liệu mẫu (lịch sử nhiều ngày, từ điển, snippets), engine THẬT (node bin/vflow.js
#              serve, không STT thật — chỉ cần /healthz + /v1/dictionary + /v1/snippets), quyền macOS
#              giả lập "đủ" (VFLOW_DEMO_PERMISSIONS=granted, KHÔNG đụng TCC thật).
#   - "empty": không dữ liệu, không chạy engine, quyền giả lập "thiếu".
# rồi gọi `VFlow --render-offscreen <mục> --appearance <sáng|tối> --out <path>` cho từng cặp
# (mục, giao diện) — quy trình y hệt công cụ `--render-offscreen` dùng trong test hồi quy bố cục
# (VFlowTests/LayoutRegressionTests.swift), không phải đường riêng.
set -euo pipefail

CLIENT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
REPO_DIR="$(cd "$CLIENT_DIR/.." && pwd)"
OUT_DIR="${1:-}"
if [ -z "$OUT_DIR" ]; then
  echo "Dùng: $0 <thư mục đầu ra>" >&2
  exit 64
fi
mkdir -p "$OUT_DIR"
OUT_DIR="$(cd "$OUT_DIR" && pwd)"

echo "==> Dựng VFlow (swift build)…"
(cd "$CLIENT_DIR" && swift build) >&2
VFLOW_BIN="$CLIENT_DIR/.build/out/Products/Debug/VFlow"
if [ ! -x "$VFLOW_BIN" ]; then
  # `swift build` không luôn dùng .build/out (tuỳ cấu hình máy) — dò đường chuẩn SwiftPM.
  VFLOW_BIN="$(cd "$CLIENT_DIR" && swift build --show-bin-path)/VFlow"
fi
if [ ! -x "$VFLOW_BIN" ]; then
  echo "LỖI: không thấy binary VFlow đã dựng ở $VFLOW_BIN" >&2
  exit 1
fi

NODE_BIN="$(command -v node || true)"
if [ -z "$NODE_BIN" ]; then
  for c in "$HOME/.local/bin/node" /opt/homebrew/bin/node /usr/local/bin/node; do
    [ -x "$c" ] && NODE_BIN="$c" && break
  done
fi

HOME_FULL="$(mktemp -d /tmp/vflow-snapshot-full.XXXXXX)"
HOME_EMPTY="$(mktemp -d /tmp/vflow-snapshot-empty.XXXXXX)"
ENGINE_PID=""

cleanup() {
  if [ -n "$ENGINE_PID" ] && kill -0 "$ENGINE_PID" 2>/dev/null; then
    kill "$ENGINE_PID" 2>/dev/null || true
    wait "$ENGINE_PID" 2>/dev/null || true
  fi
  rm -rf "$HOME_FULL" "$HOME_EMPTY"
}
trap cleanup EXIT

echo "==> Chuẩn bị dữ liệu mẫu (KHÔNG có tên riêng/khoá thật) ở ${HOME_FULL}"
"$NODE_BIN" "$CLIENT_DIR/scripts/snapshot-seed.mjs" "$HOME_FULL" "$REPO_DIR"

PORT=27611
if [ -n "$NODE_BIN" ]; then
  echo "==> Khởi động engine thật (node bin/vflow.js serve, cổng $PORT, chỉ 127.0.0.1)…"
  VFLOW_HOME="$HOME_FULL" VFLOW_PORT="$PORT" "$NODE_BIN" "$REPO_DIR/bin/vflow.js" serve --port "$PORT" \
    >"$HOME_FULL/engine.log" 2>&1 &
  ENGINE_PID=$!
  for _ in $(seq 1 40); do
    if curl -fsS "http://127.0.0.1:$PORT/healthz" >/dev/null 2>&1; then break; fi
    sleep 0.25
  done
  if ! curl -fsS "http://127.0.0.1:$PORT/healthz" >/dev/null 2>&1; then
    echo "CẢNH BÁO: engine không trả /healthz kịp — ảnh Từ điển/Snippets sẽ hiện \"đang chờ engine\" (vẫn trung thực, không phải lỗi script)." >&2
  fi
  # ClientConfig cần client.json trỏ đúng cổng đã chạy thật (file do snapshot-seed.mjs tạo sẵn với
  # cổng mặc định 7611 — cập nhật lại cho khớp cổng thật dùng ở đây).
  "$NODE_BIN" -e "const fs=require('fs');const p='$HOME_FULL/client.json';const c=JSON.parse(fs.readFileSync(p));c.port=$PORT;fs.writeFileSync(p,JSON.stringify(c,null,2));"
else
  echo "CẢNH BÁO: không thấy node — bỏ qua engine thật, Từ điển/Snippets sẽ hiện trạng thái lỗi/chờ (trung thực)." >&2
fi

capture() {
  local home="$1" perms="$2" target="$3" appearance="$4" name="$5"
  VFLOW_HOME="$home" VFLOW_DEMO_PERMISSIONS="$perms" "$VFLOW_BIN" \
    --render-offscreen "$target" --appearance "$appearance" --out "$OUT_DIR/$name.png" \
    --render-wait-ms 1200 --no-prompt --no-welcome >>"$OUT_DIR/snapshot.log" 2>&1 || \
    echo "LỖI chụp $name (xem $OUT_DIR/snapshot.log)" >&2
}

capture_overlay() {
  local state="$1" appearance="$2" name="$3"
  VFLOW_HOME="$HOME_EMPTY" "$VFLOW_BIN" --demo-overlay "$state" --appearance "$appearance" \
    --render-offscreen --out "$OUT_DIR/$name.png" --no-prompt >>"$OUT_DIR/snapshot.log" 2>&1 || \
    echo "LỖI chụp HUD $name (xem $OUT_DIR/snapshot.log)" >&2
}

: >"$OUT_DIR/snapshot.log"
echo "==> Chụp (ngoài màn hình — xem client/README.md)…"
for appearance in light dark; do
  capture "$HOME_FULL"  granted tongquan            "$appearance" "overview_permissions-ok_$appearance"
  capture "$HOME_EMPTY" denied  tongquan            "$appearance" "overview_permissions-missing_$appearance"
  capture "$HOME_FULL"  granted lichsu              "$appearance" "history_with-data_$appearance"
  capture "$HOME_EMPTY" granted lichsu              "$appearance" "history_empty_$appearance"
  capture "$HOME_FULL"  granted tudien              "$appearance" "dictionary_$appearance"
  capture "$HOME_FULL"  granted snippet             "$appearance" "snippets_$appearance"
  capture "$HOME_FULL"  granted "tudien:them-loi"   "$appearance" "dictionary_add-invalid_$appearance"
  capture "$HOME_FULL"  granted "caidat:general"        "$appearance" "settings_general_$appearance"
  capture "$HOME_FULL"  granted "caidat:cloud"           "$appearance" "settings_cloud_$appearance"
  capture "$HOME_FULL"  granted "caidat:historyPrivacy"  "$appearance" "settings_historyPrivacy_$appearance"
  capture "$HOME_FULL"  granted "caidat:advanced"        "$appearance" "settings_advanced_$appearance"
  capture "$HOME_EMPTY" denied  welcome             "$appearance" "welcome_$appearance"
  capture_overlay ghi  "$appearance" "hud_listening_$appearance"
  capture_overlay khoa "$appearance" "hud_locked_$appearance"
  capture_overlay dich "$appearance" "hud_transcribing_$appearance"
  capture_overlay xong "$appearance" "hud_done_$appearance"
  capture_overlay loi  "$appearance" "hud_error_$appearance"
done

echo "==> Tự kiểm: không tiến trình VFlow nào còn sống, không cửa sổ on-screen (xem log từng ảnh ở trên — mỗi lần chụp tự in VFLOW_OFFSCREEN_CHECK)."
if pgrep -f "$VFLOW_BIN" >/dev/null 2>&1; then
  echo "CẢNH BÁO: còn tiến trình VFlow sống sau khi chụp xong — kill thủ công: pgrep -f $VFLOW_BIN" >&2
fi

echo "==> Xong. Ảnh ở $OUT_DIR (xem $OUT_DIR/snapshot.log nếu có ảnh lỗi)."
ls "$OUT_DIR"/*.png 2>/dev/null | wc -l | xargs -I{} echo "    {} ảnh PNG."
