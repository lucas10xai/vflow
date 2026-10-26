#!/bin/bash
# Dựng client/build/VFlow.app (bản release), ký ad-hoc và kiểm chữ ký.
# Dùng: client/scripts/build-app.sh [--clean]   (--clean: xoá .build trung gian sau khi dựng)
set -euo pipefail

CLIENT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP="$CLIENT_DIR/build/VFlow.app"
cd "$CLIENT_DIR"

echo "• swift build -c release (VFlow)…"
swift build -c release --product VFlow -j "${VFLOW_BUILD_JOBS:-2}"
BIN="$(swift build -c release --product VFlow --show-bin-path)/VFlow"
[ -x "$BIN" ] || { echo "LỖI: không thấy nhị phân $BIN" >&2; exit 1; }

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp "$BIN" "$APP/Contents/MacOS/VFlow"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleIdentifier</key><string>org.aios.vflow</string>
  <key>CFBundleName</key><string>vflow</string>
  <key>CFBundleDisplayName</key><string>vflow</string>
  <key>CFBundleExecutable</key><string>VFlow</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>0.1.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>CFBundleDevelopmentRegion</key><string>vi</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSUIElement</key><true/>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSMicrophoneUsageDescription</key>
  <string>vflow dùng micro để ghi giọng nói của anh trong lúc giữ phím ⌥ trái, rồi chuyển thành chữ ngay trên máy này. Âm thanh chỉ nằm trong bộ nhớ, không ghi xuống đĩa và không gửi ra ngoài máy.</string>
</dict>
</plist>
PLIST
plutil -lint "$APP/Contents/Info.plist" >/dev/null

echo "• ký ad-hoc…"
codesign --force --deep -s - --identifier org.aios.vflow "$APP"
codesign --verify --deep --strict "$APP"
echo "• chữ ký OK"

if [ "${1:-}" = "--clean" ]; then
  rm -rf "$CLIENT_DIR/.build"
  echo "• đã xoá client/.build"
fi
echo "Xong: $APP ($(du -sh "$APP" | cut -f1))"
