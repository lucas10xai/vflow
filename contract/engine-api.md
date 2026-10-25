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
Quy tắc: `text` luôn có giá trị dùng được; nếu bước viết lại (`email`) lỗi hoặc quá thời gian thì `text = text_raw`, `rewrite = {used:false,error:"<mã>"}` (không báo thành công giả). Âm thanh rỗng/im lặng trả `text:""` kèm `"silence":true`, không phải lỗi.

## Từ điển cá nhân
`GET /v1/dictionary` → `{ "entries": [ { "term": "deploy", "spoken": ["đi plôi","đì ploi"], "kind": "term", "uses": 12, "last_used": "2026-10-26T01:00:00Z" } ] }`
`PUT /v1/dictionary` thay toàn bộ (kiểm schema, tối đa 5.000 mục). `POST /v1/corrections` với `{ "before": "…", "after": "…" }` → `{ "suggestions": [ { "term": "…", "spoken": ["…"] } ] }` (chỉ gợi ý, người dùng xác nhận mới ghi). Tệp lưu `~/.vflow/dictionary.json` (0600), không nằm trong repo. Hạt giống `config/dictionary.seed.json` chỉ chứa thuật ngữ chung, không có tên riêng/khoá.

## Cấu hình (`~/.vflow/config.json`, tất cả có mặc định)
`default_model`, `rewrite.url` (mặc định `http://127.0.0.1:20128/v1`), `rewrite.model`, `rewrite.timeout_ms` (mặc định 8000), `rewrite.key_file` (đường dẫn tệp chứa khoá; **không** chứa khoá trực tiếp trong cấu hình). `remote.phowhisper.url`.

## Chế độ
- `normal`: STT + từ điển.
- `clean`: như `normal` + bỏ từ đệm (ừm, à, ờ, uh…) và sửa dấu cách/chấm câu cơ bản; thuần quy tắc, không gọi LLM.
- `email`: STT + từ điển + viết lại thành thư chuyên nghiệp qua endpoint OpenAI-compatible (`/chat/completions`); chỉ gửi **văn bản** (không âm thanh).
- `auto`: chọn theo `app`: ứng dụng thư → `email`, ứng dụng nhắn tin/terminal → `clean`, còn lại → `normal`.

## Bất biến cần test
1. Âm thanh không bao giờ được ghi xuống đĩa; log không chứa văn bản.
2. Viết lại lỗi ⇒ `text == text_raw` và `rewrite.error` có giá trị.
3. Thiếu/sai token ⇒ 401 `unauthorized`; `Host` lạ ⇒ từ chối.
4. Model thiếu/hỏng ⇒ `model_unavailable` kèm lý do, không rơi về model khác một cách âm thầm.
5. Khoá viết lại không xuất hiện trong bất kỳ log/phản hồi/lỗi nào.
