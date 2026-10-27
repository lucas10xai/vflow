---

### Tải về và cài đặt

- `vflow-<phiên bản>-macos-arm64.zip` — app cho **Mac Apple Silicon, macOS 14 trở lên** (không có bản Intel). Kèm `LICENSE` và `NOTICE`.
- `…zip.sha256` — đối chiếu bằng: `shasum -a 256 -c vflow-<phiên bản>-macos-arm64.zip.sha256` (chạy trong thư mục chứa cả hai tệp).

### ⚠️ App CHƯA được Apple công chứng — bạn phải tự gỡ chặn

Dự án chưa dùng chứng chỉ Apple Developer, nên bản dựng này chỉ ký ad-hoc và **macOS sẽ chặn ở lần mở đầu tiên** ("không thể xác minh…" hoặc "đã bị hỏng"). Làm một trong hai cách:

1. Bấm đúp VFlow.app một lần, rồi vào **Cài đặt hệ thống › Quyền riêng tư & Bảo mật › Bảo mật › Vẫn mở**.
2. Hoặc chạy trong Terminal: `xattr -dr com.apple.quarantine /Applications/VFlow.app`

Chỉ làm vậy với tệp tải từ **trang Releases chính thức của repo này**. Hướng dẫn đầy đủ, lý do bị chặn và rủi ro: mục **"Gỡ chặn macOS cho app chưa công chứng"** trong `README.md`. Sau mỗi lần cập nhật, macOS có thể đòi cấp lại 3 quyền (Micro, Theo dõi đầu vào, Trợ năng).

### Model KHÔNG kèm theo

Bản phát hành này **không chứa model nhận dạng giọng nói**. Lần đầu mở app, bạn tải model `zipformer-vi-30m` (~26 MB) và phải đồng ý giấy phép của nó: **CC-BY-NC-ND-4.0 — chỉ dùng phi thương mại, cấm bản sửa đổi** (tác giả hynt). Mã nguồn vflow là **Apache-2.0**. Dùng thương mại cần đổi model hoặc xin phép tác giả model — xem `NOTICE`.

### Quyền riêng tư

Âm thanh không rời máy và mặc định không ghi xuống đĩa. Chỉ chế độ Gọn/Thư/Command Mode gửi **văn bản** tới máy chủ tương thích OpenAI do **bạn** tự cấu hình, và chỉ khi bạn tự đặt model + khoá. Không telemetry, không tự cập nhật.
