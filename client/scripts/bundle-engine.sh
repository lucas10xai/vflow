#!/bin/bash
# Đóng gói Node 22 + mã engine + node_modules (chỉ darwin-arm64) + model zipformer-vi-30m + LICENSES
# vào VFlow.app/Contents/Resources/ để app TỰ ĐỦ (không cần repo hay Node hệ thống trên máy chạy).
# Dùng: client/scripts/bundle-engine.sh <đường-dẫn-VFlow.app> [danh tính ký, mặc định "-" = ad-hoc]
# Gọi từ build-app.sh (mặc định có bundle); build-app.sh --no-bundle bỏ qua script này.
set -euo pipefail

APP="${1:?dùng: bundle-engine.sh <đường-dẫn-VFlow.app> [danh tính ký]}"
SIGN_IDENTITY="${2:--}"
SCRIPTS_DIR="$(cd "$(dirname "$0")" && pwd)"
CLIENT_DIR="$(cd "$SCRIPTS_DIR/.." && pwd)"
REPO="$(cd "$CLIENT_DIR/.." && pwd)"
CACHE="$CLIENT_DIR/.cache"
RES="$APP/Contents/Resources"
ENGINE_DEST="$RES/engine"
MODEL_ID="zipformer-vi-30m"

mkdir -p "$CACHE"

# ── 1. Node LTS 22.x chính thức (darwin-arm64), kiểm sha256 với SHASUMS256.txt chính thức ─────────
echo "• Node 22 LTS darwin-arm64…"
NODE_SHASUMS_URL="https://nodejs.org/dist/latest-v22.x/SHASUMS256.txt"
NODE_LINE="$(curl -fsSL --retry 3 "$NODE_SHASUMS_URL" | grep 'darwin-arm64\.tar\.gz$')"
[ -n "$NODE_LINE" ] || { echo "LỖI: không đọc được $NODE_SHASUMS_URL" >&2; exit 1; }
NODE_TARBALL="$(echo "$NODE_LINE" | awk '{print $2}')"
NODE_VERSION="$(echo "$NODE_TARBALL" | sed -E 's/^node-(v[0-9.]+)-darwin-arm64\.tar\.gz$/\1/')"
echo "  → $NODE_VERSION ($NODE_TARBALL)"

NODE_DIST="https://nodejs.org/dist/${NODE_VERSION}"
NODE_SHASUMS_PINNED="$(curl -fsSL --retry 3 "$NODE_DIST/SHASUMS256.txt")"
NODE_SHA_EXPECTED="$(echo "$NODE_SHASUMS_PINNED" | grep "  ${NODE_TARBALL}\$" | awk '{print $1}')"
[ -n "$NODE_SHA_EXPECTED" ] || { echo "LỖI: không thấy sha256 của $NODE_TARBALL trong $NODE_DIST/SHASUMS256.txt" >&2; exit 1; }

NODE_TARBALL_PATH="$CACHE/$NODE_TARBALL"
if [ ! -f "$NODE_TARBALL_PATH" ]; then
  echo "  tải ${NODE_DIST}/${NODE_TARBALL}…"
  curl -fsSL --retry 3 -o "$NODE_TARBALL_PATH.part" "$NODE_DIST/$NODE_TARBALL"
  mv "$NODE_TARBALL_PATH.part" "$NODE_TARBALL_PATH"
else
  echo "  đã có trong cache: $NODE_TARBALL_PATH"
fi
NODE_SHA_GOT="$(shasum -a 256 "$NODE_TARBALL_PATH" | awk '{print $1}')"
if [ "$NODE_SHA_GOT" != "$NODE_SHA_EXPECTED" ]; then
  echo "LỖI: sha256 của $NODE_TARBALL không khớp (mong đợi $NODE_SHA_EXPECTED, nhận $NODE_SHA_GOT) — xoá cache và thử lại." >&2
  rm -f "$NODE_TARBALL_PATH"
  exit 1
fi
echo "  sha256 OK: $NODE_SHA_GOT"

NODE_EXTRACT_DIR="$CACHE/${NODE_TARBALL%.tar.gz}"
if [ ! -x "$NODE_EXTRACT_DIR/bin/node" ]; then
  echo "  giải nén…"
  rm -rf "$NODE_EXTRACT_DIR"
  tar -xzf "$NODE_TARBALL_PATH" -C "$CACHE"
fi

# ── 2. Mã engine: bin/, engine/ (bỏ *.test.js; đã có eval/*.js theo quyết định coordinator vì
#       bin/vflow.js import tĩnh eval/metrics.js, eval/bench.js, eval/evaluate.js — xem README "Nợ
#       kỹ thuật"), config/dictionary.seed.json, package.json ─────────────────────────────────────
echo "• mã engine…"
rm -rf "$ENGINE_DEST"
mkdir -p "$ENGINE_DEST"
cp -R "$REPO/bin" "$ENGINE_DEST/bin"
cp -R "$REPO/engine" "$ENGINE_DEST/engine"
find "$ENGINE_DEST/bin" "$ENGINE_DEST/engine" -name "*.test.js" -delete
mkdir -p "$ENGINE_DEST/eval"
cp "$REPO"/eval/*.js "$ENGINE_DEST/eval/" 2>/dev/null || true
find "$ENGINE_DEST/eval" -name "*.test.js" -delete
mkdir -p "$ENGINE_DEST/config"
cp "$REPO/config/dictionary.seed.json" "$ENGINE_DEST/config/dictionary.seed.json"
cp "$REPO/package.json" "$ENGINE_DEST/package.json"
cp "$REPO/package-lock.json" "$ENGINE_DEST/package-lock.json"

# ── 3. node_modules: chỉ dependency chạy thật, chỉ bản darwin-arm64 của sherpa-onnx-node (npm ci
#       chạy trên chính máy arm64 này nên optionalDependencies tự loại các nền tảng khác) ─────────
echo "• npm ci --omit=dev (chỉ darwin-arm64)…"
( cd "$ENGINE_DEST" && "$NODE_EXTRACT_DIR/bin/node" "$NODE_EXTRACT_DIR/lib/node_modules/npm/bin/npm-cli.js" ci --omit=dev --no-audit --no-fund >/dev/null )
rm -f "$ENGINE_DEST/package-lock.json"
# Kiểm không lẫn gói nền tảng khác (win-x64…) — phải không có, nếu có là lỗi npm ci trên máy sai kiến trúc.
if ls "$ENGINE_DEST/node_modules" 2>/dev/null | grep -qE '^sherpa-onnx-(win|linux)'; then
  echo "LỖI: node_modules lẫn gói sherpa-onnx không phải darwin-arm64 — kiểm lại máy/kiến trúc chạy npm ci." >&2
  exit 1
fi
[ -d "$ENGINE_DEST/node_modules/sherpa-onnx-darwin-arm64" ] || { echo "LỖI: thiếu sherpa-onnx-darwin-arm64 sau npm ci." >&2; exit 1; }

# ── 4. Node (chỉ nhị phân bin/node — không npm/npx/include/share để nhỏ gọn) ────────────────────
mkdir -p "$ENGINE_DEST/node/bin"
cp "$NODE_EXTRACT_DIR/bin/node" "$ENGINE_DEST/node/bin/node"
chmod +x "$ENGINE_DEST/node/bin/node"

# ── 5. Model zipformer-vi-30m từ ~/.vflow/models (đã kiểm checksum theo manifest; KHÔNG tải lại) ──
echo "• model ${MODEL_ID}…"
SRC_MODEL="$HOME/.vflow/models/$MODEL_ID"
if [ ! -f "$SRC_MODEL/manifest.json" ]; then
  echo "LỖI: không thấy $SRC_MODEL/manifest.json — chạy 'vflow models pull $MODEL_ID' trước khi đóng gói." >&2
  exit 1
fi
DEST_MODELS="$RES/models"
mkdir -p "$DEST_MODELS"
rm -rf "$DEST_MODELS/$MODEL_ID"
cp -R "$SRC_MODEL" "$DEST_MODELS/$MODEL_ID"
# Kiểm lại sha256 từng tệp khai trong manifest sau khi chép vào bundle — không tin suông bản gốc.
python3 -I - "$DEST_MODELS/$MODEL_ID" <<'PYEOF'
import json, hashlib, sys, pathlib
d = pathlib.Path(sys.argv[1])
m = json.loads((d / "manifest.json").read_text())
for role, f in m["files"].items():
    p = d / f["path"]
    got = hashlib.sha256(p.read_bytes()).hexdigest()
    if got != f["sha256"]:
        print(f"LỖI: sai sha256 sau khi chép {role} ({p}): mong đợi {f['sha256']}, nhận {got}", file=sys.stderr)
        sys.exit(1)
print(f"  sha256 OK: {len(m['files'])} tệp")
PYEOF

# ── 6. LICENSES/ ────────────────────────────────────────────────────────────────────────────────
echo "• LICENSES…"
LIC="$RES/LICENSES"
mkdir -p "$LIC"
cp "$NODE_EXTRACT_DIR/LICENSE" "$LIC/NODE.txt" 2>/dev/null || echo "CẢNH BÁO: không thấy LICENSE trong bản Node tải về" >&2
curl -fsSL --retry 2 -o "$LIC/SHERPA-ONNX-APACHE-2.0.txt" "https://raw.githubusercontent.com/k2-fsa/sherpa-onnx/master/LICENSE" \
  || echo "CẢNH BÁO: không tải được giấy phép sherpa-onnx (mạng?) — xem https://github.com/k2-fsa/sherpa-onnx/blob/master/LICENSE" >&2
curl -fsSL --retry 2 -o "$LIC/ONNXRUNTIME-MIT.txt" "https://raw.githubusercontent.com/microsoft/onnxruntime/main/LICENSE" \
  || echo "CẢNH BÁO: không tải được giấy phép onnxruntime (mạng?) — xem https://github.com/microsoft/onnxruntime/blob/main/LICENSE" >&2
cat > "$LIC/MODEL-ZIPFORMER-VI-30M.txt" <<'EOF'
Model: zipformer-vi-30m (Zipformer-30M-RNNT-6000h, sherpa-onnx, int8)
Giấy phép: CC-BY-NC-ND-4.0 — theo model gốc hynt/Zipformer-30M-RNNT-6000h trên Hugging Face.
https://huggingface.co/hynt/Zipformer-30M-RNNT-6000h
https://creativecommons.org/licenses/by-nc-nd/4.0/

CHỈ DÙNG CÁ NHÂN, PHI THƯƠNG MẠI. Không được sửa đổi/phân phối lại dưới giấy phép khác
(ND = NoDerivatives). Xem manifest.json cạnh model trong bundle để biết checksum/nguồn gốc từng tệp.
EOF

# ── 7. Ký MỌI nhị phân lồng nhau (cùng danh tính truyền vào — ổn định nếu có, ad-hoc nếu không) ──
echo "• ký nhị phân lồng nhau (danh tính: $SIGN_IDENTITY)…"
find "$ENGINE_DEST" \( -name "*.node" -o -name "*.dylib" \) -print0 | while IFS= read -r -d '' f; do
  codesign --force -s "$SIGN_IDENTITY" "$f"
done
codesign --force -s "$SIGN_IDENTITY" "$ENGINE_DEST/node/bin/node"

SIZE="$(du -sh "$APP" | cut -f1)"
echo "Xong: engine đóng gói vào $ENGINE_DEST ($SIZE tổng cộng $APP)"
