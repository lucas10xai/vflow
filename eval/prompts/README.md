# Bộ câu thoại mẫu `vi-en-40`

40 câu tiếng Việt xen thuật ngữ tiếng Anh, theo cách một lập trình viên / chủ hệ thống AI nói khi ra lệnh cho agent và khi họp: câu lệnh ngắn, mô tả lỗi, câu hỏi, số liệu, tên lệnh, cổng, URL. Dùng để đo WER/CER của các model STT trên giọng thật (đợt M2).

- `vi-en-40.txt`: mỗi dòng một câu, dạng `NN. <câu>` (NN = 01…40). Câu viết ở **dạng chữ mong muốn sau cùng** (ví dụ `localhost:3000`, `90%`, `CI/CD`).
- `terms.json`: các thuật ngữ tiếng Anh có mặt trong 40 câu (để đo riêng tỉ lệ đúng thuật ngữ).
- `prompts.test.js`: kiểm định dạng, thuật ngữ có mặt, không có IP/khoá/email.

Không có mật khẩu, IP thật, tên người hay thông tin cá nhân. Tên sản phẩm chung (Docker, Tailscale, n8n, Orca, Supabase…) được phép.

## Cách ghi âm

1. Phòng yên tĩnh, tắt quạt/điều hoà nếu được. Dùng mic sẽ dùng thật (mic MacBook hoặc tai nghe), miệng cách mic khoảng **20–30 cm** (mic laptop) hoặc **3–5 cm, lệch sang bên** (mic tai nghe), không thổi thẳng vào mic.
2. Đọc **tự nhiên** như đang nói với agent/đồng nghiệp: đúng tốc độ, giọng và cách phát âm thuật ngữ hằng ngày của mình (không cố đọc chuẩn tiếng Anh nếu bình thường không nói vậy — mục tiêu là đo đúng giọng dùng thật). Không đọc số thứ tự `NN.`.
3. Số, cổng, URL, ký hiệu đọc thành lời như khi nói bình thường: `5678` → "năm sáu bảy tám" hoặc "năm nghìn sáu trăm bảy mươi tám", `localhost:3000` → "localhost hai chấm ba nghìn", `/v1/chat/completions` → "gạch chéo v một gạch chéo chat gạch chéo completions", `90%` → "chín mươi phần trăm", `CI/CD` → "CI CD". Nếu đọc khác chữ trong câu, ghi chú lại trong `NN.txt` (xem dưới) để người chấm biết.
4. Mỗi câu một tệp, để khoảng lặng ~0,5 giây ở đầu và cuối, đọc lại nếu vấp.
5. Định dạng: WAV PCM 16-bit, mono, **16 kHz** (nếu thu ở 44,1/48 kHz cũng được, engine tự đổi tần số, nhưng ghi rõ).

## Đặt tên tệp

Mỗi câu một cặp tệp, cùng số thứ tự với dòng trong `vi-en-40.txt`:

```
01.wav   âm thanh câu 01
01.txt   văn bản tham chiếu câu 01 (chép nguyên câu, KHÔNG có "01. " ở đầu)
02.wav
02.txt
…
40.wav
40.txt
```

`NN.txt` là văn bản tham chiếu dùng để tính WER. Nếu lúc đọc lỡ nói khác câu gốc (thêm/bớt từ), **sửa `NN.txt` theo đúng lời đã nói** thay vì ghi âm lại.

Ghi âm là dữ liệu giọng nói của người dùng: lưu ngoài repo (ví dụ `~/.vflow/eval/vi-en-40/`), không commit. `scripts/hp.sh sync` không gửi `*.wav` > 5 MB nhưng vẫn gửi tệp nhỏ, nên đừng đặt bản ghi trong cây repo.

## Chưa xác định

- Cách chuẩn hoá số/URL khi chấm WER (chữ số so với chữ viết) chưa chốt; quyết ở M2.
- Độ dài mỗi câu khi đọc ước lượng 3–25 giây, chưa đo bằng giọng thật.
