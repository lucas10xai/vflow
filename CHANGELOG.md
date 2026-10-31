# Lịch sử thay đổi

Định dạng theo [Keep a Changelog](https://keepachangelog.com/vi/1.1.0/); đánh số phiên bản theo [SemVer](https://semver.org/lang/vi/) (xem [`docs/release-process.md`](docs/release-process.md)). Workflow phát hành lấy đúng mục `## [X.Y.Z]` của thẻ làm ghi chú phát hành — **giữ nguyên dạng tiêu đề này**.

## [Chưa phát hành]

(chưa có thay đổi nào sau 0.2.0)

## [0.2.0] - 2026-10-31

### Nhận dạng đa ngôn ngữ
- Thêm Whisper (OpenAI, giấy phép **MIT**) làm lựa chọn STT song song với `zipformer-vi-30m`: `whisper-tiny-multilingual` (đã có checksum trong registry) và `whisper-base`/`whisper-small` (thêm vào registry). Màn hình chọn model mới trong app liệt kê từng lựa chọn kèm đánh đổi thật (dung lượng, RAM, độ trễ) để người dùng tự quyết, **không đổi model mặc định**.
- Gỡ **SenseVoice** khỏi registry: không hỗ trợ tiếng Việt theo tài liệu chính thức, và giấy phép TRỌNG SỐ model (khác giấy phép mã nguồn MIT) mơ hồ về thương mại — xem `eval/reports/2026-10-30-multilingual.md`.
- Sửa lỗi: tham số `stt_language` (`vi`/`en`/tự nhận biết) của API trước đây chỉ được dùng để kiểm năng lực model, **không hề** đổi hành vi giải mã thật của Whisper (luôn tự nhận biết ngầm). Giờ áp dụng đúng tham số được chọn.
- Sửa lỗi: Whisper trả dấu câu kép ở một số câu do hậu xử lý cộng thêm dấu câu sẵn có trong văn bản gốc.
- Sửa lỗi: từ điển cá nhân (phiên âm) không hoạt động trên văn bản đã có dấu câu/viết hoa chuẩn (như Whisper trả về) vì so khớp theo dạng chưa chuẩn hoá.

### Chế độ Dịch
- Thêm chế độ Dịch: gửi văn bản tiếng Việt ra ngoài máy qua endpoint LLM do người dùng tự cấu hình để dịch sang ngôn ngữ khác, có lựa chọn độ trang trọng. Có bộ chặn (guard) từ chối kết quả là lời bình, quá ngắn/quá dài bất thường, hoặc vẫn còn nguyên tiếng Việt (dịch thất bại âm thầm thay vì trả sai). Chế độ `auto` (theo ứng dụng) **không bao giờ** tự chọn Dịch — phải người dùng chọn tay, vì đây là đường duy nhất chủ động gửi nội dung ra ngoài máy.

### Đã biết / đánh đổi (đọc kỹ trước khi đổi mặc định)
- **Whisper làm từ điển cá nhân (phiên âm) kém hiệu quả hơn hẳn zipformer**: trên bộ đo 36 câu, từ điển sửa đúng 2/36 câu cho zipformer nhưng 0/36 cho Whisper — lỗi của Whisper (nhận nhầm ngôn ngữ, lặp vô nghĩa) khác bản chất với lỗi phiên âm gần-âm mà từ điển hiện tại được thiết kế để bắt.
- **Mọi số đo trong `eval/reports/2026-10-30-multilingual.md` là từ giọng TỔNG HỢP** (`say` của macOS), **KHÔNG phải giọng người dùng thật** — WER/CER/RTF/RAM giữa `whisper-tiny/base/small` và `zipformer-vi-30m` trên 36 câu chỉ mang tính tham khảo; quyết định đổi mặc định cần đo lại bằng giọng thật trước.
- `whisper-base`/`whisper-small` chưa có số đo "sau post-processing/từ điển" qua engine thật (ngoài phạm vi registry hiện tại khi đo); chỉ có số "thô" qua gọi trực tiếp sherpa-onnx.

## [0.1.0] - 2026-10-27

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
