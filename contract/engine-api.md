# Hợp đồng engine vflow (v0.1)

Engine là tiến trình Node chạy cục bộ. Client (Swift, CLI, test) chỉ nói chuyện qua HTTP này. Mọi worker phải tuân theo; muốn đổi thì hỏi coordinator.

## Ràng buộc chung
- Chỉ nghe `127.0.0.1` (mặc định cổng `7611`, đổi bằng `VFLOW_PORT`). Không bao giờ `0.0.0.0`.
- Mọi yêu cầu (trừ `/healthz`) cần `Authorization: Bearer <token>`; token sinh ngẫu nhiên 32 byte, lưu `~/.vflow/token` (quyền 0600). Từ chối nếu `Host` không phải `127.0.0.1:<cổng>` hoặc `localhost:<cổng>` (chặn DNS rebinding), không gửi CORS header.
- Âm thanh: **không ghi ra đĩa**, không log nội dung âm thanh hay văn bản; log chỉ có id, thời lượng, thời gian xử lý, mã lỗi.
- Lỗi: HTTP 4xx/5xx kèm `{"error":{"code":"<snake_case>","message":"<tiếng Việt>"}}`. Mã: `unauthorized`, `bad_audio`, `bad_request`, `model_unavailable`, `timeout`, `payload_too_large` (giới hạn 120 giây âm thanh), `internal`.

## GET /healthz (không cần token)
```json
{ "ok": true, "version": "0.1.0",
  "models": [ { "id": "zipformer-vi-30m", "kind": "local", "loaded": true },
              { "id": "phowhisper-large", "kind": "remote", "loaded": false, "reason": "tunnel_down" } ] }
```
`loaded:false` luôn kèm `reason` (không bao giờ im lặng).

## POST /v1/transcribe
Body: PCM thô `Content-Type: audio/L16; rate=16000; channels=1` (int16 little-endian) **hoặc** `audio/wav` (PCM 16-bit, mọi tần số; engine tự đổi về 16 kHz mono).
Query: `model` (mặc định lấy từ cấu hình), `mode=normal|clean|email|auto` (mặc định `normal`), `lang=vi|auto` (mặc định `vi`), `app` (gợi ý ứng dụng đang focus, dùng cho `auto`, ví dụ `com.apple.mail`).

Phản hồi 200:
```json
{ "id": "tr_01H…", "model": "zipformer-vi-30m", "mode": "clean", "language": "vi",
  "text_raw": "…", "text": "…",
  "audio_ms": 5230,
  "timings_ms": { "stt": 410, "post": 3, "total": 421 }, "rtf": 0.078,
  "post": { "applied": [ { "type": "dictionary", "from": "đi plôi", "to": "deploy" },
                          { "type": "filler_removed", "from": "ừm", "to": "" } ],
            "rewrite": { "used": false, "error": null } } }
```
Quy tắc: `text_raw` luôn là chữ gốc do STT trả về, không đổi. `text` luôn có giá trị dùng được. Nếu bước viết lại (`email`) lỗi hoặc quá thời gian thì `text` = văn bản đã qua từ điển nhưng CHƯA viết lại (không áp thêm `clean`), `rewrite = {used:false,error:"<mã>"}` (không báo thành công giả). Âm thanh rỗng/im lặng trả `text:""` kèm `"silence":true`, không phải lỗi.

## Từ điển cá nhân
`GET /v1/dictionary` → `{ "entries": [ { "term": "deploy", "spoken": ["đi plôi","đì ploi"], "kind": "term", "uses": 12, "last_used": "2026-10-26T01:00:00Z" } ] }`
`PUT /v1/dictionary` thay toàn bộ (kiểm schema, tối đa 5.000 mục). `POST /v1/corrections` với `{ "before": "…", "after": "…" }` → `{ "suggestions": [ { "term": "…", "spoken": ["…"] } ] }` (chỉ gợi ý, người dùng xác nhận mới ghi). Tệp lưu `~/.vflow/dictionary.json` (0600), không nằm trong repo. Hạt giống `config/dictionary.seed.json` chỉ chứa thuật ngữ chung, không có tên riêng/khoá.

## Cấu hình (`~/.vflow/config.json`, tất cả có mặc định)
`default_model`, `rewrite.url` (mặc định `http://127.0.0.1:20128/v1`), `rewrite.model`, `rewrite.timeout_ms` (mặc định 8000), `rewrite.key_file` (đường dẫn tệp chứa khoá; **không** chứa khoá trực tiếp trong cấu hình), `auto.apps` (bảng ánh xạ `{ "<bundleId>": "normal|clean|email" }` cho chế độ `auto`; có mặc định, sửa được). `remote.phowhisper.url`.

## Chế độ
- `normal`: STT + từ điển.
- `clean`: như `normal` + bỏ từ đệm (ừm, à, ờ, uh…) và sửa dấu cách/chấm câu cơ bản; thuần quy tắc, không gọi LLM.
- `email`: STT + từ điển + viết lại thành thư chuyên nghiệp qua endpoint OpenAI-compatible (`/chat/completions`); chỉ gửi **văn bản** (không âm thanh).
- `auto`: chọn theo `app` qua `auto.apps`. **Mặc định CHỈ chọn chế độ chạy trong máy, không bao giờ gọi LLM**: terminal/IDE (Terminal, iTerm2, Warp, VS Code, Cursor, Ghostty) → `dev`; ứng dụng thư và nhắn tin (Mail, Outlook, Slack, Telegram, Discord, Tin nhắn, WhatsApp…) → `clean`; còn lại → `normal`. `tidy` và `email` chỉ dùng khi người dùng CHỦ ĐỘNG chọn chúng (hoặc tự ánh xạ trong `auto.apps`); khi đó văn bản của app đó sẽ được gửi qua LLM.
- `tidy` ("Gọn"): STT + từ điển + snippets + quy tắc đọc kiểu lập trình + **LLM làm gọn** qua endpoint OpenAI-compatible: tự thêm dấu câu và viết hoa, bỏ từ đệm, hiểu tự sửa giữa câu (backtrack: "…thứ Sáu, à nhầm, thứ Năm" chỉ giữ "thứ Năm"), định dạng danh sách khi người nói liệt kê. Chỉ gửi **văn bản**. KHÔNG được thêm ý, số, tên hay thuật ngữ không có trong lời nói. Lỗi/quá giờ/bị chặn bởi guard ⇒ `text` = văn bản đã qua từ điển và `clean` bằng quy tắc (không LLM), `rewrite = {used:false, error:"<mã>"}` (mã thêm: `guard_rejected`, `cloud_disabled`).
- `dev` ("Lập trình"): như `clean` + quy tắc đọc kiểu lập trình (thuần quy tắc, không LLM, không gửi gì ra ngoài): "gạch dưới" → `_`, "gạch ngang" → `-`, "gạch chéo" → `/`, "hai chấm" → `:`, "chấm" giữa hai định danh (hoặc trước đuôi tệp đã biết) → `.`, "viết thường nối gạch dưới a b c" → `a_b_c` (snake_case), "camel case a b c" → `aBC` đúng quy ước, v.v. Chỉ áp dụng ở dạng cụm không nhập nhằng; không đổi từ tiếng Việt thường.

## Hành động sau khi dán (`post.actions`)
Phản hồi `post` có thêm `actions: string[]` (mặc định rỗng). Hiện chỉ có `"enter"`: khi lời nói KẾT THÚC bằng cụm "nhấn enter" hoặc "bấm enter" (đúng ở cuối, bỏ dấu/viết hoa/dấu câu khi so khớp) và `actions_enabled` bật, engine cắt cụm đó khỏi `text` và trả `actions:["enter"]`; client dán rồi gửi phím Return. Không hành động nào khác được tạo từ lời nói.

## Snippets (đoạn văn mẫu gọi bằng lời)
`GET /v1/snippets` → `{ "entries": [ { "trigger": "link lịch hẹn", "text": "https://…", "uses": 3, "last_used": "…" } ] }`. `PUT /v1/snippets` thay toàn bộ (kiểm schema: `trigger` 1–60 ký tự, `text` 1–5.000 ký tự có thể nhiều dòng, trigger không trùng sau khi bỏ dấu/hoa thường, tối đa 500 mục). Lưu `~/.vflow/snippets.json` (0600), không nằm trong repo. Mở rộng: khi cả câu nói (bỏ dấu/hoa thường/dấu câu) bằng một trigger, HOẶC có dạng "chèn <trigger>" ở bất kỳ vị trí nào trong câu ⇒ thay bằng `text` nguyên văn (không qua từ điển, làm gọn hay viết lại); `post.applied` có `{type:"snippet", from:"<trigger>", to:"snippet"}` (không ghi nội dung snippet vào log). Không mở rộng ở nơi khác để tránh kích hoạt nhầm.

## Command Mode (sửa/soạn văn bản bằng lời)
Client ghi âm lệnh, gọi `POST /v1/transcribe` (`mode=normal`) để lấy chữ, rồi gọi `POST /v1/command` JSON `{ "instruction": "<lệnh>", "selection": "<đoạn đang chọn, có thể rỗng>", "context": "<văn bản xung quanh, tuỳ chọn>", "app": "<bundle id>" }` ⇒ 200 `{ "text": "<văn bản thay thế/soạn mới>", "kind": "edit|draft", "timings_ms": { "llm": 900 } }`. Có `selection` ⇒ `edit` (chỉ trả đoạn thay thế, không lời dẫn). Không có ⇒ `draft`. Giới hạn 20.000 ký tự mỗi trường. Lỗi (không đặt model, thiếu khoá, `cloud_disabled`, quá giờ, phản hồi rỗng/lạ) ⇒ HTTP 502/503 `{ "error": { "code": "rewrite_unavailable|cloud_disabled|timeout|bad_request", "message": "<tiếng Việt>" } }`, KHÔNG trả văn bản giả; client không dán gì.

## Cài đặt người dùng (`GET/PUT /v1/settings`)
`GET` → `{ "cloud_llm": true, "llm_model": "ag/gemini-3.8-flash" | null, "llm_timeout_ms": 8000, "actions_enabled": true }` (không bao giờ trả khoá). `PUT` nhận tập con các trường (kiểm kiểu/giá trị; `llm_timeout_ms` 1.000–30.000; `llm_model` chuỗi ≤ 200 ký tự hoặc null), ghi vào `~/.vflow/config.json`, có hiệu lực ngay không cần khởi động lại. `cloud_llm=false` ⇒ `tidy`, `email` và `/v1/command` không gọi LLM: `tidy`/`email` trả `rewrite.error="cloud_disabled"` và dùng văn bản đã qua từ điển; `/v1/command` trả `cloud_disabled`. Chế độ `normal`, `clean`, `dev` không bao giờ gọi LLM.

## Ghi chú LLM (endpoint OpenAI-compatible, ví dụ 9Router)
Luôn gửi `"stream": false`. Máy chủ đã thấy trả luồng SSE (`data: {...}` từng dòng) dù không yêu cầu stream: client LLM của engine phải đọc được CẢ phản hồi JSON thường LẪN SSE (ghép `delta.content`), nếu không đọc được ⇒ `bad_response`. Khoá lấy từ `rewrite.key_file` (mặc định `~/.vflow/rewrite.key`), không bao giờ vào log/phản hồi/lỗi. `llm_model` trong `/v1/settings` ưu tiên hơn `rewrite.model` trong cấu hình.

## Bất biến cần test
1. Âm thanh không bao giờ được ghi xuống đĩa; log không chứa văn bản.
2. Viết lại/làm gọn lỗi ⇒ `text` là văn bản đã qua từ điển và quy tắc (chưa qua LLM), `text_raw` giữ nguyên chữ STT gốc, và `rewrite.error` có giá trị.
3. Thiếu/sai token ⇒ 401 `unauthorized`; `Host` lạ ⇒ từ chối.
4. Model thiếu/hỏng ⇒ `model_unavailable` kèm lý do, không rơi về model khác một cách âm thầm.
5. Khoá viết lại không xuất hiện trong bất kỳ log/phản hồi/lỗi nào.
6. LLM làm gọn không được thêm nội dung: nếu đầu ra có từ/số/thuật ngữ không có trong đầu vào (ngoài dấu câu và dấu đánh số) quá ngưỡng thì bị `guard_rejected`.
7. `snippet` không bao giờ bị sửa bởi từ điển/làm gọn/viết lại; chỉ mở rộng đúng hai dạng đã nêu.
8. `actions:["enter"]` chỉ xuất hiện khi cụm đứng ĐÚNG ở cuối lời nói và `actions_enabled` bật.
9. `cloud_llm=false` ⇒ không có yêu cầu mạng nào tới endpoint LLM (kiểm bằng máy chủ giả đếm yêu cầu).
10. Với cấu hình mặc định, `mode=auto` KHÔNG BAO GIỜ gọi LLM (kiểm bằng máy chủ giả đếm 0 yêu cầu qua mọi `app` trong `auto.apps` mặc định). Chỉ chọn thủ công `tidy`/`email` hoặc tự sửa `auto.apps` mới gửi chữ ra LLM.
