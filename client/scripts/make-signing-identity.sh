#!/bin/bash
# Tạo chứng chỉ TỰ KÝ ổn định "vflow Local Signing" để ký VFlow.app, thay cho ký ad-hoc (`-s -`).
# Lý do: TCC (quyền Theo dõi đầu vào/Trợ năng) gắn với chữ ký; ký ad-hoc đổi chữ ký mỗi lần
# `build-app.sh` chạy lại ⇒ macOS đòi cấp lại quyền. Một danh tính TỰ KÝ cố định (CN cố định, khoá
# riêng giữ trong login keychain) giữ nguyên chữ ký giữa các lần dựng ⇒ quyền được giữ.
#
# Dùng: client/scripts/make-signing-identity.sh --yes        (THẬT: hiện hộp thoại keychain)
#       client/scripts/make-signing-identity.sh --dry-run    (chỉ in các lệnh SẼ chạy, không làm gì)
#
# QUAN TRỌNG: việc đổi login keychain cần chủ dự án tự duyệt (hộp thoại mật khẩu keychain) — KHÔNG
# tự động chạy với --yes trong CI/agent. Idempotent: đã có danh tính cùng tên thì thoát 0, không
# tạo thêm bản trùng.
set -euo pipefail

IDENTITY_NAME="vflow Local Signing"
YES=0
DRY_RUN=0
for arg in "$@"; do
  case "$arg" in
    --yes) YES=1 ;;
    --dry-run) DRY_RUN=1 ;;
    *) echo "LỖI: cờ không rõ: $arg (dùng --yes hoặc --dry-run)" >&2; exit 64 ;;
  esac
done
if [ "$YES" = "1" ] && [ "$DRY_RUN" = "1" ]; then
  echo "LỖI: không dùng --yes và --dry-run cùng lúc." >&2
  exit 64
fi
if [ "$YES" = "0" ] && [ "$DRY_RUN" = "0" ]; then
  echo "LỖI: cần một trong hai cờ --yes (chạy thật, cần chủ dự án duyệt) hoặc --dry-run (chỉ xem trước)." >&2
  exit 64
fi

echo "• kiểm tra danh tính ký mã \"$IDENTITY_NAME\" đã có trong keychain chưa…"
if security find-identity -v -p codesigning 2>/dev/null | grep -qF "\"$IDENTITY_NAME\""; then
  echo "  Đã có \"$IDENTITY_NAME\" — không làm gì thêm (idempotent)."
  exit 0
fi
echo "  Chưa có."

KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
KEY="$TMP/vflow-signing.key"
CERT="$TMP/vflow-signing.crt"
P12="$TMP/vflow-signing.p12"

GEN_CERT_CMD=(openssl req -x509 -newkey rsa:2048 -keyout "$KEY" -out "$CERT" -days 3650 -nodes
  -subj "/CN=$IDENTITY_NAME"
  -addext "extendedKeyUsage=codeSigning"
  -addext "basicConstraints=critical,CA:false"
  -addext "keyUsage=critical,digitalSignature")
EXPORT_P12_CMD=(openssl pkcs12 -export -out "$P12" -inkey "$KEY" -in "$CERT" -passout "pass:<ngẫu nhiên, chỉ dùng tạm>")
IMPORT_CMD=(security import "$P12" -k "$KEYCHAIN" -P "<mật khẩu tạm>" -T /usr/bin/codesign -T /usr/bin/security)
PARTITION_CMD=(security set-key-partition-list -S "apple-tool:,apple:,codesign:" -s "$KEYCHAIN")

if [ "$DRY_RUN" = "1" ]; then
  echo "• --dry-run: các lệnh SẼ chạy với --yes (không chạy thật ở đây):"
  printf '    %s\n' "${GEN_CERT_CMD[*]}"
  printf '    %s\n' "${EXPORT_P12_CMD[*]}"
  printf '    %s\n' "${IMPORT_CMD[*]}"
  printf '    %s\n' "${PARTITION_CMD[*]}"
  echo "  (khoá riêng + chứng chỉ sinh ra trong thư mục tạm, xoá sau khi nhập vào keychain xong; không ghi vào repo)"
  exit 0
fi

echo "CẢNH BÁO: bước này sẽ hiện hộp thoại hệ thống hỏi mật khẩu login keychain (Keychain Access/Touch ID) để cho phép codesign dùng khoá riêng mới — cần chủ dự án xác nhận trực tiếp trên máy."
P12_PASS="$(openssl rand -base64 24)"

echo "• tạo chứng chỉ tự ký RSA 2048, hạn 10 năm, CN=\"$IDENTITY_NAME\", extendedKeyUsage=codeSigning…"
openssl req -x509 -newkey rsa:2048 -keyout "$KEY" -out "$CERT" -days 3650 -nodes \
  -subj "/CN=$IDENTITY_NAME" \
  -addext "extendedKeyUsage=codeSigning" \
  -addext "basicConstraints=critical,CA:false" \
  -addext "keyUsage=critical,digitalSignature"

echo "• đóng gói PKCS#12 (mật khẩu tạm, chỉ dùng để nhập ngay sau đây)…"
openssl pkcs12 -export -out "$P12" -inkey "$KEY" -in "$CERT" -passout "pass:$P12_PASS"

echo "• nhập vào login keychain, cho phép /usr/bin/codesign dùng khoá riêng (-T)…"
security import "$P12" -k "$KEYCHAIN" -P "$P12_PASS" -T /usr/bin/codesign -T /usr/bin/security

echo "• cấp quyền partition-list cho codesign (có thể hiện hộp thoại mật khẩu keychain lần nữa)…"
if ! security set-key-partition-list -S "apple-tool:,apple:,codesign:" -s "$KEYCHAIN" >/dev/null; then
  echo "  CẢNH BÁO: set-key-partition-list lỗi hoặc bị huỷ — build-app.sh có thể vẫn hỏi mật khẩu keychain mỗi lần ký cho tới khi cấp quyền thủ công trong Keychain Access (chọn khoá riêng \"$IDENTITY_NAME\" › Get Info › Access Control › thêm /usr/bin/codesign)." >&2
fi

echo "• kiểm lại danh tính đã sẵn sàng…"
if ! security find-identity -v -p codesigning | grep -qF "\"$IDENTITY_NAME\""; then
  echo "LỖI: không thấy danh tính \"$IDENTITY_NAME\" sau khi nhập — kiểm lại Keychain Access." >&2
  exit 1
fi
echo "Xong: danh tính ký mã \"$IDENTITY_NAME\" đã sẵn sàng trong login keychain. build-app.sh/install-app.sh sẽ tự dùng nó từ lần dựng kế tiếp."
