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
# Thống kê "tắt" (item 7): seed GIỐNG HOME_FULL nhưng config.json đặt sẵn stats_enabled:false trước
# khi engine khởi động, để /v1/stats.enabled=false đúng trạng thái thật (không giả lập ở client).
HOME_STATS_OFF="$(mktemp -d /tmp/vflow-snapshot-statsoff.XXXXXX)"
ENGINE_PIDS=()

cleanup() {
  for pid in "${ENGINE_PIDS[@]:-}"; do
    [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null && kill "$pid" 2>/dev/null && wait "$pid" 2>/dev/null
  done
  rm -rf "$HOME_FULL" "$HOME_EMPTY" "$HOME_STATS_OFF"
}
trap cleanup EXIT

echo "==> Chuẩn bị dữ liệu mẫu (KHÔNG có tên riêng/khoá thật) ở ${HOME_FULL}"
"$NODE_BIN" "$CLIENT_DIR/scripts/snapshot-seed.mjs" "$HOME_FULL" "$REPO_DIR"
echo "==> Chuẩn bị dữ liệu mẫu (thống kê TẮT) ở ${HOME_STATS_OFF}"
"$NODE_BIN" "$CLIENT_DIR/scripts/snapshot-seed.mjs" "$HOME_STATS_OFF" "$REPO_DIR"
"$NODE_BIN" -e "require('fs').writeFileSync('$HOME_STATS_OFF/config.json', JSON.stringify({stats_enabled:false}, null, 2));"

start_engine() {
  local home="$1" port="$2"
  VFLOW_HOME="$home" VFLOW_PORT="$port" "$NODE_BIN" "$REPO_DIR/bin/vflow.js" serve --port "$port" \
    >"$home/engine.log" 2>&1 &
  ENGINE_PIDS+=("$!")
  for _ in $(seq 1 40); do
    if curl -fsS "http://127.0.0.1:$port/healthz" >/dev/null 2>&1; then break; fi
    sleep 0.25
  done
  if ! curl -fsS "http://127.0.0.1:$port/healthz" >/dev/null 2>&1; then
    echo "CẢNH BÁO: engine ($home, cổng $port) không trả /healthz kịp — ảnh liên quan sẽ hiện \"đang chờ engine\" (vẫn trung thực, không phải lỗi script)." >&2
  fi
  # ClientConfig cần client.json trỏ đúng cổng đã chạy thật — tạo mới (HOME_EMPTY chưa qua
  # snapshot-seed.mjs nên chưa có tệp này) hoặc cập nhật lại cổng (snapshot-seed.mjs tạo sẵn với
  # cổng mặc định 7611). KHÔNG BAO GIỜ để trống ⇒ rơi về cổng 7611 thật (xem quy tắc cứng).
  "$NODE_BIN" -e "
    const fs=require('fs');const p='$home/client.json';
    const c = fs.existsSync(p) ? JSON.parse(fs.readFileSync(p)) : { repo: '$REPO_DIR' };
    c.port=$port;
    fs.writeFileSync(p,JSON.stringify(c,null,2));
  "
}

PORT=27611
PORT_EMPTY=27612
PORT_STATS_OFF=27613
if [ -n "$NODE_BIN" ]; then
  echo "==> Khởi động engine thật (node bin/vflow.js serve, chỉ 127.0.0.1)…"
  start_engine "$HOME_FULL" "$PORT"
  # HOME_EMPTY: không dữ liệu (lịch sử/từ điển/snippets rỗng, thống kê 0 từ) — cũng cần engine THẬT
  # để tab Thống kê/Từ điển/Snippets hiện đúng trạng thái "rỗng" chứ không phải "đang chờ engine".
  start_engine "$HOME_EMPTY" "$PORT_EMPTY"
  start_engine "$HOME_STATS_OFF" "$PORT_STATS_OFF"
else
  echo "CẢNH BÁO: không thấy node — bỏ qua engine thật, Từ điển/Snippets/Thống kê sẽ hiện trạng thái lỗi/chờ (trung thực)." >&2
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
  # V5: lưới chế độ với Dịch đã chọn + ô chọn ngôn ngữ đích/mức trang trọng (chỉ hiện ở chế độ Dịch).
  capture "$HOME_FULL"  granted "tongquan:dich"     "$appearance" "overview_translate_$appearance"
  # V5: sheet "Dịch câu này" dựng độc lập (không qua .sheet thật — xem AppController.captureTranslationSheetOffscreen).
  capture "$HOME_FULL"  granted "dich-sheet"        "$appearance" "translate_sheet_$appearance"
  capture "$HOME_FULL"      granted thongke         "$appearance" "stats_with-data_$appearance"
  capture "$HOME_EMPTY"     granted thongke         "$appearance" "stats_empty_$appearance"
  capture "$HOME_STATS_OFF" granted thongke         "$appearance" "stats_disabled_$appearance"
  capture "$HOME_FULL"  granted lichsu              "$appearance" "history_with-data_$appearance"
  capture "$HOME_EMPTY" granted lichsu              "$appearance" "history_empty_$appearance"
  capture "$HOME_FULL"  granted tudien              "$appearance" "dictionary_with-suggestions_$appearance"
  capture "$HOME_FULL"  granted snippet             "$appearance" "snippets_$appearance"
  capture "$HOME_FULL"  granted "tudien:them-loi"   "$appearance" "dictionary_add-invalid_$appearance"
  # Cài đặt: 5 mục sau khi gộp (cũ: hotkeys→voice, cloud→advanced, historyPrivacy→data).
  capture "$HOME_FULL"  granted "caidat:general"        "$appearance" "settings_general_$appearance"
  capture "$HOME_FULL"  granted "caidat:voice"           "$appearance" "settings_voice_$appearance"
  capture "$HOME_FULL"  granted "caidat:apps"            "$appearance" "settings_apps_$appearance"
  capture "$HOME_FULL"  granted "caidat:data"            "$appearance" "settings_data_$appearance"
  capture "$HOME_FULL"  granted "caidat:advanced"        "$appearance" "settings_advanced_$appearance"
  # F2: màn hình chọn model — HOME_FULL chỉ có zipformer-vi-30m tải sẵn (snapshot-seed.mjs không
  # tải model nào), nên ảnh "models" tự nhiên có CẢ model đã tải (zipformer, Sẵn sàng) LẪN chưa tải
  # (whisper-*, …) mà không cần chuẩn bị gì thêm. Biến thể "có model đa ngôn ngữ đang NẠP" (Ngôn ngữ
  # khi nói MỞ KHOÁ) không có ở đây — cần tải/nạp thật một model Whisper (hàng trăm MB, tốn thời
  # gian/băng thông đáng kể cho MỖI lần chạy script này) nên KHÔNG đưa vào vòng lặp thường xuyên này;
  # xem README mục "Model nhận dạng giọng nói" cho cách tự chụp riêng khi cần.
  capture "$HOME_FULL"  granted "models"                  "$appearance" "models_$appearance"
  capture "$HOME_FULL"  granted "models:dangtai"          "$appearance" "models_downloading_$appearance"
  capture "$HOME_EMPTY" denied  welcome             "$appearance" "welcome_$appearance"
  capture_overlay ghi      "$appearance" "hud_listening_$appearance"
  capture_overlay khoa     "$appearance" "hud_locked_$appearance"
  capture_overlay dich-nghe "$appearance" "hud_translate-listening_$appearance"
  capture_overlay dich     "$appearance" "hud_transcribing_$appearance"
  capture_overlay xong     "$appearance" "hud_done_$appearance"
  capture_overlay loi      "$appearance" "hud_error_$appearance"
done

echo "==> Tự kiểm: không tiến trình VFlow nào còn sống, không cửa sổ on-screen (xem log từng ảnh ở trên — mỗi lần chụp tự in VFLOW_OFFSCREEN_CHECK)."
if pgrep -f "$VFLOW_BIN" >/dev/null 2>&1; then
  echo "CẢNH BÁO: còn tiến trình VFlow sống sau khi chụp xong — kill thủ công: pgrep -f $VFLOW_BIN" >&2
fi

echo "==> Xong. Ảnh ở $OUT_DIR (xem $OUT_DIR/snapshot.log nếu có ảnh lỗi)."
ls "$OUT_DIR"/*.png 2>/dev/null | wc -l | xargs -I{} echo "    {} ảnh PNG."
