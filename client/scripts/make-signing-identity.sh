#!/bin/bash
# Tạo / tin cậy / xoá chứng chỉ TỰ KÝ ổn định "vflow Local Signing" dùng để ký VFlow.app, thay cho
# ký ad-hoc (`-s -`). TCC (quyền Theo dõi đầu vào/Trợ năng) gắn với chữ ký; ký ad-hoc đổi chữ ký mỗi
# lần build-app.sh chạy lại ⇒ macOS đòi cấp lại quyền. Một danh tính TỰ KÝ cố định (CN cố định, khoá
# riêng giữ trong keychain, ĐÃ ĐƯỢC TIN CẬY cho codeSigning) giữ nguyên chữ ký + ký được giữa các
# lần dựng ⇒ quyền được giữ.
#
# BẰNG CHỨNG ĐO THẬT (tự kiểm trên keychain tạm trước khi sửa script này):
#  - openssl trong PATH hiện là Homebrew OpenSSL 3.6.3; .p12 do nó xuất bị `security import` từ
#    chối: "MAC verification failed during PKCS12 import (wrong password?)". /usr/bin/openssl
#    (LibreSSL 3.3.6 của macOS) xuất .p12 thì `security import` thành công ("1 identity
#    imported."). ⇒ dùng CỐ ĐỊNH /usr/bin/openssl cho `req` và `pkcs12 -export`, không dùng openssl
#    trong PATH (có thể là bản khác, hành vi không đảm bảo).
#  - Sau `security import ... -T /usr/bin/codesign`, chứng chỉ tự ký CHƯA được hệ thống tin cậy:
#    `security find-identity -v -p codesigning` báo "0 valid identities found";
#    `security find-identity -p codesigning` (không -v) thấy chứng chỉ kèm
#    "(CSSMERR_TP_NOT_TRUSTED)"; `codesign -s "<tên>" ...` báo "no identity found" (exit 1).
#    ⇒ PHẢI thêm bước TIN CẬY (`security add-trusted-cert -p codeSign`) thì mới ký được. Bản cũ của
#    script này KHÔNG có bước này nên không bao giờ thật sự tạo ra chữ ký dùng được — build-app.sh
#    dò bằng `find-identity -v` nên luôn rơi về ad-hoc trong im lặng.
#  - `security set-key-partition-list -S ... -s` cần nhập mật khẩu keychain không tương tác được từ
#    script ⇒ bỏ; thay bằng `-T /usr/bin/codesign` lúc import (đủ trong đa số trường hợp) + ghi chú
#    rõ hộp thoại có thể hiện ra lần ký đầu.
#
# Dùng: client/scripts/make-signing-identity.sh --yes             (THẬT: hiện hộp thoại keychain +
#                                                                   hộp thoại tin cậy — cần anh
#                                                                   chủ dự án xác nhận trực tiếp)
#       client/scripts/make-signing-identity.sh --dry-run         (chỉ in các lệnh SẼ chạy)
#       client/scripts/make-signing-identity.sh --yes --remove    (xoá danh tính + bỏ tin cậy)
#       client/scripts/make-signing-identity.sh --dry-run --remove
#
# Idempotent theo 3 trạng thái hiện tại của keychain (dò bằng client/scripts/lib-signing.sh):
#   none      ⇒ tạo chứng chỉ, nhập vào keychain, rồi tin cậy.
#   untrusted ⇒ đã có chứng chỉ (ví dụ lần chạy trước bị ngắt giữa import và tin cậy) ⇒ CHỈ thêm
#               bước tin cậy, KHÔNG tạo chứng chỉ mới (tránh để lại nhiều bản trùng).
#   valid     ⇒ đã sẵn sàng ⇒ thoát 0, không làm gì thêm.
#
# Biến môi trường CHỈ DÙNG CHO TEST (KHÔNG dùng khi chạy thật cho chủ dự án):
#   VFLOW_SIGN_KEYCHAIN=<đường dẫn .keychain-db>  đổi keychain đích (mặc định: login keychain).
#   VFLOW_SIGN_SKIP_TRUST=1                       bỏ bước tin cậy (để test không đổi Certificate
#                                                  Trust Settings thật) — danh tính tạo ra sẽ ở
#                                                  trạng thái "untrusted", KHÔNG ký được.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=./lib-signing.sh
source "$SCRIPT_DIR/lib-signing.sh"

YES=0
DRY_RUN=0
REMOVE=0
for arg in "$@"; do
  case "$arg" in
    --yes) YES=1 ;;
    --dry-run) DRY_RUN=1 ;;
    --remove) REMOVE=1 ;;
    *) echo "LỖI: cờ không rõ: $arg (dùng --yes hoặc --dry-run; thêm --remove để xoá thay vì tạo)" >&2; exit 64 ;;
  esac
done
if [ "$YES" = "1" ] && [ "$DRY_RUN" = "1" ]; then
  echo "LỖI: không dùng --yes và --dry-run cùng lúc." >&2
  exit 64
fi
if [ "$YES" = "0" ] && [ "$DRY_RUN" = "0" ]; then
  echo "LỖI: cần một trong hai cờ --yes (chạy thật, cần chủ dự án duyệt) hoặc --dry-run (chỉ xem trước); thêm --remove để xoá." >&2
  exit 64
fi

NAME="$VFLOW_SIGN_IDENTITY_NAME"
KEYCHAIN="${VFLOW_SIGN_KEYCHAIN:-$HOME/Library/Keychains/login.keychain-db}"
SKIP_TRUST="${VFLOW_SIGN_SKIP_TRUST:-0}"
if [ "$SKIP_TRUST" = "1" ]; then
  echo "CẢNH BÁO TO: VFLOW_SIGN_SKIP_TRUST=1 — bỏ qua bước tin cậy chứng chỉ. CHỈ dùng cho test tự động; danh tính tạo ra sẽ ở trạng thái \"untrusted\" (KHÔNG ký được). TUYỆT ĐỐI không dùng cờ này khi chạy --yes thật cho chủ dự án." >&2
fi

echo "• kiểm trạng thái danh tính ký mã \"$NAME\" trong keychain ($KEYCHAIN)…"
STATE="$(vflow_signing_state "$KEYCHAIN")"
echo "  trạng thái hiện tại: $STATE"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
KEY="$TMP/vflow-signing.key"
CERT="$TMP/vflow-signing.crt"
P12="$TMP/vflow-signing.p12"
EXPORTED_CERT="$TMP/vflow-signing-exported.crt"

GEN_CERT_CMD=(/usr/bin/openssl req -x509 -newkey rsa:2048 -keyout "$KEY" -out "$CERT" -days 3650 -nodes
  -subj "/CN=$NAME"
  -addext "extendedKeyUsage=codeSigning"
  -addext "basicConstraints=critical,CA:false"
  -addext "keyUsage=critical,digitalSignature")
EXPORT_P12_CMD=(/usr/bin/openssl pkcs12 -export -out "$P12" -inkey "$KEY" -in "$CERT" -passout "pass:<ngẫu nhiên, chỉ dùng tạm>")
IMPORT_CMD=(security import "$P12" -k "$KEYCHAIN" -P "<mật khẩu tạm>" -T /usr/bin/codesign)
TRUST_CMD=(security add-trusted-cert -r trustRoot -p codeSign -k "$KEYCHAIN" "<chứng chỉ>")
DELETE_IDENTITY_CMD=(security delete-identity -c "$NAME" -t "$KEYCHAIN")

# ── --remove ─────────────────────────────────────────────────────────────────────────────────────
if [ "$REMOVE" = "1" ]; then
  if [ "$STATE" = "none" ]; then
    echo "  Chưa có \"$NAME\" trong keychain này — không có gì để xoá (idempotent)."
    exit 0
  fi
  if [ "$DRY_RUN" = "1" ]; then
    echo "• --dry-run --remove: lệnh SẼ chạy với --yes --remove:"
    printf '    %s\n' "${DELETE_IDENTITY_CMD[*]}"
    echo "  (-t: xoá cả tin cậy codeSigning của chứng chỉ này, không chỉ cert+khoá)"
    exit 0
  fi
  echo "CẢNH BÁO: bước này xoá chứng chỉ+khoá riêng \"$NAME\" khỏi keychain ($KEYCHAIN) và bỏ tin cậy codeSigning — có thể hiện hộp thoại mật khẩu keychain."
  security delete-identity -c "$NAME" -t "$KEYCHAIN"
  AFTER_STATE="$(vflow_signing_state "$KEYCHAIN")"
  if [ "$AFTER_STATE" != "none" ]; then
    echo "LỖI: sau khi xoá, trạng thái vẫn là \"$AFTER_STATE\" (mong đợi \"none\") — có thể còn bản trùng tên, kiểm lại Keychain Access." >&2
    exit 1
  fi
  echo "Xong: đã xoá danh tính \"$NAME\" khỏi $KEYCHAIN."
  exit 0
fi

# ── Tạo / tin cậy ────────────────────────────────────────────────────────────────────────────────
if [ "$STATE" = "valid" ]; then
  echo "  Đã có \"$NAME\" và đã được tin cậy — không làm gì thêm (idempotent)."
  exit 0
fi

if [ "$DRY_RUN" = "1" ]; then
  echo "• --dry-run: các lệnh SẼ chạy với --yes (không chạy thật ở đây):"
  if [ "$STATE" = "none" ]; then
    printf '    %s\n' "${GEN_CERT_CMD[*]}"
    printf '    %s\n' "${EXPORT_P12_CMD[*]}"
    printf '    %s\n' "${IMPORT_CMD[*]}"
  else
    echo "    (đã có chứng chỉ \"$NAME\" trong keychain, trạng thái: untrusted — bỏ qua bước tạo/nhập, chỉ tin cậy)"
  fi
  if [ "$SKIP_TRUST" = "1" ]; then
    echo "    (VFLOW_SIGN_SKIP_TRUST=1 — bỏ qua bước tin cậy, không chạy: ${TRUST_CMD[*]})"
  else
    printf '    %s\n' "${TRUST_CMD[*]}"
  fi
  echo "  (khoá riêng + chứng chỉ sinh ra trong thư mục tạm, xoá sau khi nhập vào keychain xong; không ghi vào repo)"
  exit 0
fi

if [ "$STATE" = "none" ]; then
  echo "CẢNH BÁO: bước này sẽ hiện hộp thoại hệ thống hỏi mật khẩu keychain ($KEYCHAIN) để cho phép codesign dùng khoá riêng mới — cần chủ dự án xác nhận trực tiếp trên máy."
  P12_PASS="$(/usr/bin/openssl rand -base64 24)"

  echo "• tạo chứng chỉ tự ký RSA 2048, hạn 10 năm, CN=\"$NAME\", extendedKeyUsage=codeSigning (bằng /usr/bin/openssl — xem bằng chứng ở đầu tệp)…"
  /usr/bin/openssl req -x509 -newkey rsa:2048 -keyout "$KEY" -out "$CERT" -days 3650 -nodes \
    -subj "/CN=$NAME" \
    -addext "extendedKeyUsage=codeSigning" \
    -addext "basicConstraints=critical,CA:false" \
    -addext "keyUsage=critical,digitalSignature"

  echo "• đóng gói PKCS#12 (mật khẩu tạm, chỉ dùng để nhập ngay sau đây)…"
  /usr/bin/openssl pkcs12 -export -out "$P12" -inkey "$KEY" -in "$CERT" -passout "pass:$P12_PASS"

  echo "• nhập vào keychain ($KEYCHAIN), cho phép /usr/bin/codesign dùng khoá riêng (-T)…"
  security import "$P12" -k "$KEYCHAIN" -P "$P12_PASS" -T /usr/bin/codesign
  cp "$CERT" "$EXPORTED_CERT"
else
  echo "• đã có chứng chỉ \"$NAME\" (trạng thái: untrusted) — chỉ thêm bước tin cậy, không tạo lại."
  security find-certificate -c "$NAME" -p "$KEYCHAIN" > "$EXPORTED_CERT"
fi

if [ "$SKIP_TRUST" = "1" ]; then
  echo "• VFLOW_SIGN_SKIP_TRUST=1 — BỎ QUA bước tin cậy (chỉ hợp lệ khi test); danh tính vẫn ở trạng thái \"untrusted\", chưa ký được."
else
  echo "• tin cậy chứng chỉ cho mục đích ký mã (sẽ hiện hộp thoại hỏi mật khẩu để đổi Certificate Trust Settings — cần chủ dự án xác nhận)…"
  security add-trusted-cert -r trustRoot -p codeSign -k "$KEYCHAIN" "$EXPORTED_CERT"
fi

echo "• kiểm lại trạng thái sau khi chạy…"
FINAL_STATE="$(vflow_signing_state "$KEYCHAIN")"
echo "  trạng thái: $FINAL_STATE"
if [ "$SKIP_TRUST" != "1" ] && [ "$FINAL_STATE" != "valid" ]; then
  echo "LỖI: sau khi tin cậy, vẫn không thấy \"$NAME\" ở trạng thái valid — kiểm lại Keychain Access." >&2
  exit 1
fi
if [ "$SKIP_TRUST" = "1" ] && [ "$FINAL_STATE" != "untrusted" ]; then
  echo "LỖI: trạng thái sau khi chạy ($FINAL_STATE) khác dự kiến (untrusted) khi bỏ qua tin cậy." >&2
  exit 1
fi

echo "LƯU Ý: lần ký đầu, macOS có thể hiện hộp thoại \"codesign muốn dùng khoá riêng của bạn\" (hoặc tương tự) — bấm \"Luôn cho phép\" (Always Allow) để không bị hỏi lại mỗi lần build. Nếu không thấy hộp thoại này thì \"-T /usr/bin/codesign\" lúc nhập đã đủ."
if [ "$FINAL_STATE" = "valid" ]; then
  echo "Xong: danh tính ký mã \"$NAME\" đã sẵn sàng (đã tin cậy) trong $KEYCHAIN. build-app.sh/install-app.sh sẽ tự dùng nó từ lần dựng kế tiếp."
fi
