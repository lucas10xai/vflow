# Lịch sử thay đổi

Định dạng theo [Keep a Changelog](https://keepachangelog.com/vi/1.1.0/); đánh số phiên bản theo [SemVer](https://semver.org/lang/vi/) (xem [`docs/release-process.md`](docs/release-process.md)). Workflow phát hành lấy đúng mục `## [X.Y.Z]` của thẻ làm ghi chú phát hành — **giữ nguyên dạng tiêu đề này**.

## [Chưa phát hành]

(chưa có thay đổi nào sau 0.1.0)

## [0.1.0] - chưa phát hành (điền ngày khi gắn thẻ)

Bản đầu tiên. Tổng hợp từ lịch sử `git log` của repo (các đợt M0–M4, E1–E2, C1–C4, U1–U3, V1–V2, nhóm A và các bản sửa).

### Nhận dạng giọng nói và engine
- Engine Node cục bộ (`127.0.0.1`, token Bearer) nhận dạng tiếng Việt bằng model `zipformer-vi-30m` qua sherpa-onnx trên CPU; có model streaming tuỳ chọn và nhà cung cấp STT từ xa (PhoWhisper-large qua máy chủ riêng, theo `contract/remote-stt.md`).
- Tải model có kiểm sha256 (`vflow models pull`); CLI `vflow` (transcribe, models, serve, snippets, settings, bench, eval, doctor, record-set, compare).
- Công cụ đo WER/CER/RTF/RAM và bộ câu thoại mẫu trong `eval/`.
- Ghi âm dài tới 20 phút (STT chia đoạn có chồng lấn để RAM không tăng theo độ dài).

### Hậu xử lý và chế độ
- Từ điển cá nhân (kèm hạt giống thuật ngữ chung), gợi ý từ mới từ các lần sửa lặp lại, **dạy từ bằng giọng** (nghe thử → thêm vào từ điển).
- Chế độ Thường · Làm sạch · Lập trình · Gọn · Thư · Tự động theo ứng dụng (mặc định chỉ chọn chế độ chạy trong máy, không gọi LLM); luật theo ứng dụng sửa được.
- **Lệnh dấu câu bằng giọng** và **ký hiệu theo ngữ cảnh** (terminal/IDE/chat); quy tắc đọc kiểu lập trình (snake_case, camelCase…).
- **Snippets**, hành động "nhấn enter" ở cuối câu, giọng điệu (neutral/formal/casual), chế độ nói nhỏ.
- Làm gọn/viết lại/Command Mode qua endpoint tương thích OpenAI do người dùng tự cấu hình, có guard chống thêm nội dung và bản dự phòng cục bộ khi lỗi/quá giờ.
- Thống kê cục bộ (số từ, chuỗi ngày, WPM, ứng dụng dùng nhiều), xuất/nhập dữ liệu, chẩn đoán không chứa bí mật.
- **Lưu âm thanh tuỳ chọn, mặc định TẮT:** có ngân sách MB, hạn ngày, tự dựng lại mục lục an toàn, xuất ZIP.

### App macOS
- Giữ ⌥ trái để nói, đúp ⌥ trái ghi hands-free, Esc huỷ, Command Mode (⌥ + ⌃); chèn chữ bằng clipboard + ⌘V rồi khôi phục clipboard.
- App thường: Dock, ⌘-Tab, cửa sổ chính (Tổng quan, Thống kê, Lịch sử, Từ điển, Snippets) và cửa sổ Cài đặt riêng; biểu tượng thanh menu phụ.
- Thanh trạng thái ghi âm với sóng âm, xem chữ chạy trực tiếp, tuỳ chọn vị trí (dưới màn hình / cạnh notch) và cỡ; giao diện sáng/tối/theo hệ thống; chọn micro, tự dừng khi im lặng, phục hồi khi micro đổi tuyến.
- Phím tắt tuỳ chỉnh, chèn lại câu vừa rồi, lịch sử theo ngày, tờ Chào mừng hướng dẫn cấp 3 quyền, cảnh báo xung đột với app đọc chính tả khác.
- Đóng gói tự đủ (Node 22 + engine), ký ad-hoc hoặc bằng danh tính ký cục bộ; script cài/gỡ; công cụ chụp ảnh giao diện ngoài màn hình (`client/scripts/snapshot.sh`).

### Giấy phép và tài liệu
- Mã nguồn theo **Apache-2.0** (`LICENSE`); `NOTICE` liệt kê thành phần bên thứ ba; model `zipformer-vi-30m` là **CC-BY-NC-ND-4.0** (chỉ phi thương mại, cấm bản sửa đổi) và **không kèm theo bản phát hành công khai**.
- `README.md` cho người dùng, `CONTRIBUTING.md`, `SECURITY.md`, quy trình phát hành và quyết định giấy phép trong `docs/`.
- Workflow GitHub Actions phát hành bản dựng không kèm model, chưa công chứng.

### Đã biết / chưa làm
- Chưa có số đo chất lượng công khai; model thuần Việt kém ở từ tiếng Anh xen câu.
- Chỉ Apple Silicon, macOS 14+. App **chưa được Apple công chứng** — người dùng phải tự gỡ chặn (xem README).
- Tăng cường từ khoá (`vocab_boost`/hotwords) đã thử và **gỡ bỏ** sau khi đo không cải thiện.
