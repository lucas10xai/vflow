# Chính sách bảo mật

vflow chạy trên máy cá nhân, nghe phím toàn cục, đọc micro và có thể gửi văn bản tới máy chủ LLM do người dùng cấu hình — nên chúng tôi xem trọng lỗ hổng bảo mật và quyền riêng tư.

## Báo lỗ hổng một cách riêng tư

**Đừng mở issue công khai, đừng đăng lên mạng xã hội** trước khi lỗi được xử lý.

Cách báo (theo thứ tự ưu tiên):

1. **Báo cáo riêng của GitHub:** vào tab **Security** của repo › **Report a vulnerability** (Private vulnerability reporting). Chỉ người duy trì dự án thấy báo cáo của bạn.
2. Nếu tab Security của repo không có nút này, hãy **mở một issue công khai chỉ với nội dung "Cần liên hệ riêng về một vấn đề bảo mật"** — *không* ghi chi tiết kỹ thuật, không ghi cách tái hiện — để người duy trì liên hệ lại qua kênh riêng.

Hãy kèm theo (nếu có thể): phiên bản vflow (Cài đặt › Nâng cao › Phiên bản), phiên bản macOS, các bước tái hiện, tác động bạn nhận thấy. **Đừng gửi** âm thanh thật, văn bản giọng nói thật, token hay khoá API của bạn; hãy che chúng.

Dự án do một cá nhân duy trì và không cam kết thời hạn phản hồi, nhưng mọi báo cáo bảo mật sẽ được đọc và xử lý ưu tiên. Chúng tôi sẽ ghi công bạn trong ghi chú phát hành nếu bạn muốn.

## Phiên bản được hỗ trợ

Chỉ **bản phát hành mới nhất** trên trang Releases được vá lỗi bảo mật. Chưa có cập nhật tự động — hãy tự cập nhật.

## Phạm vi quan tâm

Ví dụ những điều coi là lỗ hổng:

- Engine nghe ra ngoài `127.0.0.1`, hoặc chấp nhận yêu cầu không có token / với `Host` lạ (DNS rebinding).
- Lộ token, khoá viết lại (`rewrite.key`) hay văn bản/âm thanh người dùng ở log, phản hồi lỗi, gói xuất dữ liệu hoặc chẩn đoán.
- Đọc/ghi/xoá tệp ngoài thư mục dữ liệu qua API (ví dụ path traversal ở `/v1/audio/<id>`).
- Âm thanh bị ghi xuống đĩa khi người dùng chưa bật *Lưu âm thanh*; nhập gói dữ liệu bật được *Lưu âm thanh* hoặc áp dụng token/khoá.
- Văn bản bị gửi tới LLM khi người dùng chưa cấu hình/đã tắt *Cho phép gửi chữ*.
- Cách lợi dụng vflow để leo thang đặc quyền hoặc qua mặt quyền macOS.

Ngoài phạm vi: lỗi của macOS hoặc của thư viện bên thứ ba (hãy báo cho nơi phát hành chúng; nếu vflow dùng chúng sai cách thì vẫn báo cho chúng tôi); việc app **chưa được Apple công chứng** (đã nêu rõ trong README, không phải lỗ hổng).

## Bản dựng

Bản phát hành do GitHub Actions dựng từ mã đã gắn thẻ và kèm SHA-256. App chưa được ký bằng chứng chỉ Apple Developer và chưa công chứng; hãy tự đối chiếu SHA-256 hoặc tự biên dịch nếu bạn cần mức tin cậy cao hơn.
