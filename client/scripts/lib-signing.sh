#!/bin/bash
# Thư viện dùng chung: dò TRẠNG THẬT của danh tính ký mã ổn định "vflow Local Signing" trong
# keychain, và các thông báo/quyết định đi kèm — dùng bởi build-app.sh, install-app.sh và
# make-signing-identity.sh. Nguồn bằng `source`, KHÔNG tự chạy gì khi được nạp (không `set -e`/
# `set -u` ở đây để không đổi hành vi của script gọi `source`).
#
# BẰNG CHỨNG ĐO THẬT (keychain tạm, trước khi viết thư viện này): sau `security import ... -T
# /usr/bin/codesign`, chứng chỉ tự ký CHƯA được hệ thống tin cậy cho codeSigning:
#   - `security find-identity -v -p codesigning` ⇒ "0 valid identities found" (không thấy).
#   - `security find-identity -p codesigning` (KHÔNG -v) ⇒ thấy chứng chỉ, kèm hậu tố
#     "(CSSMERR_TP_NOT_TRUSTED)" trong mục "Matching identities".
#   - `codesign -s "<tên>" ...` ⇒ "no identity found" (exit 1).
# ⇒ 3 trạng thái phân biệt được chỉ bằng hai lệnh find-identity trên (không cần đụng tới
#   `codesign` để dò trạng thái):
#     "none"      — không thấy tên này ở cả hai lệnh trên.
#     "untrusted" — thấy ở lệnh KHÔNG -v nhưng KHÔNG thấy ở lệnh CÓ -v (có cert+khoá, chưa tin cậy).
#     "valid"     — thấy ở lệnh CÓ -v (đã tin cậy, ký được ngay).
# Dò bằng "-v -p codesigning" MỘT MÌNH (như build-app.sh/install-app.sh làm trước khi có thư viện
# này) sẽ không bao giờ phân biệt được "none" và "untrusted" — cả hai đều ký ad-hoc, nhưng chỉ
# "untrusted" cần nhắc chạy `make-signing-identity.sh --yes` để THÊM TIN CẬY (không cần tạo lại).

VFLOW_SIGN_IDENTITY_NAME="vflow Local Signing"

# In đúng một trong "none"|"untrusted"|"valid" ra stdout (không có xuống dòng khác, không in gì
# khác ra stdout — để gọi bằng $(...) an toàn).
# $1 (tuỳ chọn): đường dẫn keychain cụ thể để kiểm; mặc định: search list hiện tại của người dùng.
vflow_signing_state() {
  local keychain="${1:-}"
  local name="$VFLOW_SIGN_IDENTITY_NAME"
  if security find-identity -v -p codesigning ${keychain:+"$keychain"} 2>/dev/null | grep -qF "\"$name\""; then
    echo "valid"
    return 0
  fi
  if security find-identity -p codesigning ${keychain:+"$keychain"} 2>/dev/null | grep -qF "\"$name\""; then
    echo "untrusted"
    return 0
  fi
  echo "none"
}

# Trả về (qua stdout, không xuống dòng) danh tính để truyền cho `codesign -s`: tên ổn định nếu
# "valid", "-" (ad-hoc) nếu "none"/"untrusted" (chưa tin cậy ⇒ codesign dùng tên này sẽ lỗi
# "no identity found" — KHÔNG được dùng khi chưa "valid").
vflow_signing_codesign_arg() {
  local state="$1"
  if [ "$state" = "valid" ]; then
    printf '%s' "$VFLOW_SIGN_IDENTITY_NAME"
  else
    printf '%s' "-"
  fi
}

# In thông báo tiếng Việt đúng với trạng thái ra STDERR (để không lẫn vào giá trị trả về của các
# hàm khác khi gọi bằng $(...)). Dùng bởi build-app.sh trước khi ký.
vflow_signing_report() {
  local state="$1"
  case "$state" in
    valid)
      echo "• ký ổn định bằng \"$VFLOW_SIGN_IDENTITY_NAME\": quyền macOS (Micro/Theo dõi đầu vào/Trợ năng) thường được giữ qua các lần dựng (xem README mục Chữ ký)." >&2
      ;;
    untrusted)
      echo "• có chứng chỉ \"$VFLOW_SIGN_IDENTITY_NAME\" trong keychain nhưng CHƯA được tin cậy để ký mã (CSSMERR_TP_NOT_TRUSTED) ⇒ ký AD-HOC tạm thời, macOS sẽ đòi cấp lại quyền macOS mỗi lần dựng lại." >&2
      echo "  Chạy client/scripts/make-signing-identity.sh --yes để THÊM bước tin cậy (không cần tạo lại chứng chỉ)." >&2
      ;;
    none)
      echo "• chưa có danh tính ký ổn định ⇒ ký ad-hoc: macOS sẽ đòi cấp lại quyền macOS (Micro/Theo dõi đầu vào/Trợ năng) mỗi lần dựng lại." >&2
      echo "  Chạy client/scripts/make-signing-identity.sh --yes để tạo danh tính ký ổn định (cần chủ dự án duyệt)." >&2
      ;;
    *)
      echo "LỖI: trạng thái ký không rõ: \"$state\"" >&2
      return 1
      ;;
  esac
}

# In designated requirement của $1 (đường dẫn .app đã ký) và cảnh báo nếu nó vẫn dựa trên cdhash
# (nghĩa là ký "ổn định" KHÔNG thật sự có tác dụng giữ quyền macOS giữa các lần dựng — ad-hoc luôn
# cho ra designated requirement kiểu "designated => cdhash H\"...\"" vì không có chứng chỉ neo).
vflow_signing_check_dr() {
  local app="$1"
  local dr
  dr="$(codesign -dr- "$app" 2>&1 || true)"
  echo "$dr"
  if echo "$dr" | grep -q "cdhash"; then
    echo "CẢNH BÁO: designated requirement vẫn dựa trên cdhash (ad-hoc) — ký \"ổn định\" KHÔNG có tác dụng giữ quyền macOS giữa các lần dựng/cài. Chạy client/scripts/make-signing-identity.sh --yes." >&2
  fi
}
