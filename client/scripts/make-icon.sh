#!/bin/bash
# Sinh biểu tượng app (client/Resources/AppIcon.icns) từ logo-main.png, và ảnh thanh menu/đầu cửa
# sổ (client/Resources/menubar-mark-18{,@2x,@3x}.png) từ logo-mark.png — cả hai do chủ dự án cung
# cấp, nằm trong client/Resources/branding/ (KHÔNG sửa hai tệp gốc đó).
# Chạy lại khi đổi logo; build-app.sh chỉ COPY các tệp sinh ra.
set -euo pipefail

SCRIPTS_DIR="$(cd "$(dirname "$0")" && pwd)"
CLIENT_DIR="$(cd "$SCRIPTS_DIR/.." && pwd)"
BRANDING="$CLIENT_DIR/Resources/branding"
LOGO_MAIN="$BRANDING/logo-main.png"
LOGO_MARK="$BRANDING/logo-mark.png"
RES="$CLIENT_DIR/Resources"

[ -f "$LOGO_MAIN" ] || { echo "LỖI: thiếu $LOGO_MAIN" >&2; exit 1; }
[ -f "$LOGO_MARK" ] || { echo "LỖI: thiếu $LOGO_MARK" >&2; exit 1; }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# ── 1. AppIcon.icns: thu nhỏ logo-main vào vùng an toàn ≈824/1024 (CoreGraphics), rồi sips -z từng
#       kích thước chuẩn của .iconset, rồi iconutil -c icns ───────────────────────────────────────
echo "• thu nhỏ logo-main.png vào vùng an toàn 824/1024 (CoreGraphics)…"
PADDED="$TMP/padded-1024.png"
swift "$SCRIPTS_DIR/pad-icon.swift" "$LOGO_MAIN" "$PADDED" 1024 0.8046875

echo "• sinh .iconset (sips)…"
ICONSET="$TMP/AppIcon.iconset"
mkdir -p "$ICONSET"
for s in 16 32 128 256 512; do
  sips -z "$s" "$s" "$PADDED" --out "$ICONSET/icon_${s}x${s}.png" >/dev/null
  d=$((s * 2))
  sips -z "$d" "$d" "$PADDED" --out "$ICONSET/icon_${s}x${s}@2x.png" >/dev/null
done

echo "• iconutil -c icns…"
mkdir -p "$RES"
iconutil -c icns "$ICONSET" -o "$RES/AppIcon.icns"
echo "  Xong: $RES/AppIcon.icns ($(du -h "$RES/AppIcon.icns" | cut -f1))"

# ── 2. Ảnh thanh menu / đầu cửa sổ: logo-mark.png thu nhỏ trực tiếp (sips), giữ nền trong suốt ────
echo "• sinh ảnh thanh menu từ logo-mark.png (18/36/54 px)…"
sips -z 18 18 "$LOGO_MARK" --out "$RES/menubar-mark-18.png" >/dev/null
sips -z 36 36 "$LOGO_MARK" --out "$RES/menubar-mark-18@2x.png" >/dev/null
sips -z 54 54 "$LOGO_MARK" --out "$RES/menubar-mark-18@3x.png" >/dev/null
echo "  Xong: $RES/menubar-mark-18{,@2x,@3x}.png"

echo "Hoàn tất. (hai tệp gốc trong $BRANDING không bị đổi.)"
