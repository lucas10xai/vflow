#!/bin/bash
# Sinh client/Resources/AppIcon.icns từ make-icon.swift (CoreGraphics, không tài nguyên bên
# ngoài). Chạy lại khi muốn đổi thiết kế biểu tượng; build-app.sh chỉ COPY tệp .icns có sẵn.
set -euo pipefail

SCRIPTS_DIR="$(cd "$(dirname "$0")" && pwd)"
CLIENT_DIR="$(cd "$SCRIPTS_DIR/.." && pwd)"
ICONSET="$(mktemp -d)/AppIcon.iconset"
OUT="$CLIENT_DIR/Resources/AppIcon.icns"

echo "• vẽ icon (CoreGraphics)…"
swift "$SCRIPTS_DIR/make-icon.swift" "$ICONSET"

echo "• iconutil -c icns…"
mkdir -p "$CLIENT_DIR/Resources"
iconutil -c icns "$ICONSET" -o "$OUT"
rm -rf "$(dirname "$ICONSET")"

echo "Xong: $OUT ($(du -h "$OUT" | cut -f1))"
