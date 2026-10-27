# Hợp đồng engine vflow (v0.1)

Engine là tiến trình Node chạy cục bộ. Client (Swift, CLI, test) chỉ nói chuyện qua HTTP này. Mọi worker phải tuân theo; muốn đổi thì hỏi coordinator.

## Ràng buộc chung
- Chỉ nghe `127.0.0.1` (mặc định cổng `7611`, đổi bằng `VFLOW_PORT`). Không bao giờ `0.0.0.0`.
- Mọi yêu cầu (trừ `/healthz`) cần `Authorization: Bearer <token>`; token sinh ngẫu nhiên 32 byte, lưu `~/.vflow/token` (quyền 0600). Từ chối nếu `Host` không phải `127.0.0.1:<cổng>` hoặc `localhost:<cổng>` (chặn DNS rebinding), không gửi CORS header.
- Âm thanh: **mặc định KHÔNG ghi ra đĩa**. Ngoại lệ DUY NHẤT là lịch sử âm thanh do NGƯỜI DÙNG chủ động bật (`audio_history`, mặc định `false` — xem mục "Lịch sử âm thanh"). Không log nội dung âm thanh hay văn bản; log chỉ có id, thời lượng, thời gian xử lý, mã lỗi.
- Lỗi: HTTP 4xx/5xx kèm `{"error":{"code":"<snake_case>","message":"<tiếng Việt>"}}`. Mã: `unauthorized`, `bad_audio`, `bad_request`, `model_unavailable`, `timeout`, `payload_too_large` (giới hạn 1200 giây/20 phút âm thanh ở `/v1/transcribe`, 30 giây ở `/v1/partial`), `too_long` (413 — `/v1/teach` nhận tối đa 15 giây, không tự cắt), `not_found` (404 — `/v1/audio/<id>` không có), `internal`, `rewrite_unavailable`, `cloud_disabled`, `busy` (429 — `/v1/partial` hoặc `/v1/teach` đang bận, client tự bỏ qua/thử lại).

## GET /healthz (không cần token)
```json
{ "ok": true, "version": "0.1.0", "max_audio_seconds": 1200,
  "models": [ { "id": "zipformer-vi-30m", "kind": "local", "loaded": true },
              { "id": "phowhisper-large", "kind": "remote", "loaded": false, "reason": "tunnel_down" } ] }
```
`loaded:false` luôn kèm `reason` (không bao giờ im lặng). `max_audio_seconds` là giới hạn thật của `/v1/transcribe` (mục "Ghi âm dài").

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
            "rewrite": { "used": false, "error": null },
            "degraded": false, "degraded_reason": null } }
```
Quy tắc: `text_raw` luôn là chữ gốc do STT trả về, không đổi. `text` luôn có giá trị dùng được. Nếu bước viết lại (`email`) lỗi hoặc quá thời gian thì `text` = văn bản đã qua từ điển nhưng CHƯA viết lại (không áp thêm `clean`), `rewrite = {used:false,error:"<mã>"}` (không báo thành công giả). Âm thanh rỗng/im lặng trả `text:""` kèm `"silence":true`, không phải lỗi.

`post.degraded`/`post.degraded_reason` (item 7): `true` kèm một trong `"llm_timeout"|"llm_error"|"guard"|"cloud_disabled"` khi kết quả là bản dự phòng cục bộ thay cho đám mây đã định — do LLM quá `llm_timeout_ms`/lỗi/bị guard chặn (`tidy`/`email`), hoặc do `auto` tra `app_rules`/`auto.apps` ra `tidy`/`email` nhưng `cloud_llm` đang tắt (mode trả về đã là `clean`, không phải `tidy`/`email`). `false`/`null` khi không có gì suy giảm (gồm cả khi người dùng CHỌN THẲNG `normal`/`clean`/`dev`, hoặc `tidy`/`email` thành công).

`audio_id` (A6): trường TUỲ CHỌN, giá trị luôn BẰNG `id` của phản hồi. CHỈ có khi `audio_history=true` VÀ dictation thành công (`text` cuối không rỗng, không `silence`) VÀ WAV đã ghi xong và còn tồn tại sau lần quét ngân sách (xem mục "Lịch sử âm thanh"). VẮNG MẶT (không phải `null`) khi tắt cài đặt, khi im lặng, khi `text` rỗng (vd chế độ `clean` bỏ hết từ đệm), khi ghi đĩa lỗi, hoặc khi tệp lớn hơn cả ngân sách nên bị đuổi ngay. Dictation vẫn thành công khi không có `audio_id`. Ví dụ thật (cổng thử 17611, `audio_history=true`):
```json
{ "id": "tr_mvpyanl1ae825c5bc1d2", "model": "zipformer-vi-30m", "mode": "dev", "language": "vi",
  "text_raw": "rồi cũng hỗ trợ cho lâu lâu cũng cho gạo cho này kia", "text": "rồi cũng hỗ trợ cho lâu lâu cũng cho gạo cho này kia",
  "audio_ms": 3740, "timings_ms": { "stt": 31, "post": 2, "total": 42 }, "rtf": 0.008,
  "post": { "applied": [], "actions": [], "rewrite": { "used": false, "error": null }, "degraded": false, "degraded_reason": null },
  "audio_id": "tr_mvpyanl1ae825c5bc1d2" }
```

## Từ điển cá nhân
`GET /v1/dictionary` → `{ "entries": [ { "term": "deploy", "spoken": ["đi plôi","đì ploi"], "kind": "term", "uses": 12, "last_used": "2026-10-26T01:00:00Z" } ] }`
`PUT /v1/dictionary` thay toàn bộ (kiểm schema, tối đa 5.000 mục). `POST /v1/corrections` với `{ "before": "…", "after": "…" }` → `{ "suggestions": [ { "term": "…", "spoken": ["…"] } ] }` (phản hồi ngay chỉ là gợi ý, KHÔNG tự thêm vào từ điển — người dùng xác nhận mới ghi qua `PUT /v1/dictionary`; đồng thời, nếu `learn_from_edits` bật, engine LƯU LẠI cặp này để tổng hợp `GET /v1/dictionary/suggestions` khi đủ ≥ 2 lần — xem mục "Gợi ý từ điển"). Tệp lưu `~/.vflow/dictionary.json` (0600), không nằm trong repo. Hạt giống `config/dictionary.seed.json` chỉ chứa thuật ngữ chung, không có tên riêng/khoá.

## Cấu hình (`~/.vflow/config.json`, tất cả có mặc định)
`default_model`, `rewrite.url` (mặc định `http://127.0.0.1:20128/v1` — cổng mặc định của 9Router, một máy chủ tương thích OpenAI chạy cục bộ và hoàn toàn tuỳ chọn; trỏ sang endpoint OpenAI-compatible khác bằng cách đổi giá trị này), `rewrite.model`, `rewrite.timeout_ms` (mặc định 8000), `rewrite.key_file` (đường dẫn tệp chứa khoá; **không** chứa khoá trực tiếp trong cấu hình), `auto.apps` (bảng ánh xạ `{ "<bundleId>": "normal|clean|email" }` cho chế độ `auto`; có mặc định, sửa được). `remote.phowhisper.url`.

## Chế độ
- `normal`: STT + từ điển + **dấu câu bằng giọng** (xem mục riêng dưới).
- `clean`: như `normal` + bỏ từ đệm (ừm, à, ờ, uh…) và sửa dấu cách/chấm câu cơ bản; thuần quy tắc, không gọi LLM.
- `email`: STT + từ điển + dấu câu bằng giọng + viết lại thành thư chuyên nghiệp qua endpoint OpenAI-compatible (`/chat/completions`, theo `tone`); chỉ gửi **văn bản** (không âm thanh).
- `auto`: tra `app_rules` (cài đặt, item 4) TRƯỚC, rồi `auto.apps` (cấu hình cứng) theo `app`. **Mặc định CHỈ chọn chế độ chạy trong máy, không bao giờ gọi LLM**: terminal/IDE (Terminal, iTerm2, Warp, VS Code, Cursor, Ghostty) → `dev`; ứng dụng thư và nhắn tin (Mail, Outlook, Slack, Telegram, Discord, Tin nhắn, WhatsApp…) → `clean`; còn lại → `normal`. `tidy` và `email` chỉ dùng khi người dùng CHỦ ĐỘNG chọn chúng (hoặc tự ánh xạ trong `app_rules`/`auto.apps`); khi đó văn bản của app đó sẽ được gửi qua LLM — TRỪ khi `cloud_llm` đang tắt, lúc đó `auto` rơi về `clean` NGAY (không thử gọi LLM) và báo `degraded_reason:"cloud_disabled"`.
- `tidy` ("Gọn"): STT + từ điển + snippets + quy tắc đọc kiểu lập trình + dấu câu bằng giọng + **LLM làm gọn** qua endpoint OpenAI-compatible (theo `tone`): tự thêm dấu câu và viết hoa, bỏ từ đệm, hiểu tự sửa giữa câu (backtrack: "…thứ Sáu, à nhầm, thứ Năm" chỉ giữ "thứ Năm"), định dạng danh sách khi người nói liệt kê. Chỉ gửi **văn bản**. KHÔNG được thêm ý, số, tên hay thuật ngữ không có trong lời nói — guard độc lập với `tone`. Lỗi/quá giờ/bị chặn bởi guard ⇒ `text` = văn bản đã qua từ điển, quy tắc lập trình và `clean` (không LLM), `rewrite = {used:false, error:"<mã>"}` (mã thêm: `guard_rejected`, `cloud_disabled`), `degraded:true`.
- `dev` ("Lập trình"): như `clean` + quy tắc đọc kiểu lập trình (thuần quy tắc, không LLM, không gửi gì ra ngoài, **KHÔNG** chạy dấu câu bằng giọng): "gạch dưới" → `_`, "gạch ngang" → `-`, "gạch chéo" → `/`, "hai chấm" → `:`, "chấm" giữa hai định danh (hoặc trước đuôi tệp đã biết) → `.`, "viết thường nối gạch dưới a b c" → `a_b_c` (snake_case), "camel case a b c" → `aBC` đúng quy ước, v.v. Chỉ áp dụng ở dạng cụm không nhập nhằng; không đổi từ tiếng Việt thường.
- Ký hiệu theo ngữ cảnh (`context_symbols`, mục riêng dưới) chạy ở MỌI chế độ KỂ CẢ `dev` và `tidy`, TRƯỚC quy tắc đọc kiểu lập trình của `dev`/`tidy` (vì terminal/IDE ở `auto` đều ra `dev`): "https hai chấm hai gạch chéo example" ở Terminal ⇒ `https://example` (nếu để quy tắc `dev` chạy trước thì thành `https:hai/example`).

## Lệnh dấu câu bằng giọng (`voice_punctuation`)
Chạy trong hậu xử lý cho MỌI chế độ TRỪ `dev`, trừ khi `voice_punctuation=false` (cài đặt, mặc định `true`). Từ khoá ≥ 2 từ (không nhầm lời nói thường — "chấm điểm", "câu hỏi" giữ nguyên): "xuống dòng"→`\n`, "đoạn mới"/"xuống hai dòng"→`\n\n`, "dấu chấm"→`.`, "dấu phẩy"→`,`, "dấu hỏi chấm"/"chấm hỏi"→`?`, "dấu chấm than"/"chấm than"→`!`, "dấu hai chấm"→`:`, "dấu chấm phẩy"→`;`, "ba chấm"/"dấu ba chấm"→`…`, "mở/đóng ngoặc"→`(`/`)`, "mở/đóng ngoặc kép"→`“`/`”`, "gạch ngang"/"dấu gạch ngang"→`–`. Dính vào từ trước đối với `, . ? ! : ; … ) ”` (không dư khoảng trắng trước); viết hoa chữ tiếp theo sau `. ? !` và sau xuống dòng, KHÔNG viết hoa sau `, : ;`. Thứ tự: từ điển/snippet trước, dấu câu bằng giọng sau, hành động "nhấn enter" (đã cắt khỏi câu từ bước đầu) không đổi. Hạn chế đã biết: ở `tidy`, "dấu hai chấm" có thể bị quy tắc lập trình "hai chấm" (không có "dấu") bắt trước một phần.

## Giọng điệu và nói nhỏ
`tone` (`neutral`|`formal`|`casual`, mặc định `neutral`): chỉ ảnh hưởng PHONG CÁCH của `tidy`/`email` (một dòng hướng dẫn thêm vào prompt) — không đổi guard, không đổi nghĩa/thêm thông tin. `whisper_mode` (mặc định `false`): trước STT, tự khuếch đại âm lượng hoàn toàn trong máy — chuẩn hoá đỉnh về khoảng −3 dBFS, tăng tối đa +24 dB, cổng nhiễu nhẹ (giảm mềm, không cắt hẳn) để im lặng/nhiễu nền không bị khuếch đại thành tiếng nghe được; không ảnh hưởng quyết định im lặng (`silence`).

## Hành động sau khi dán (`post.actions`)
Phản hồi `post` có thêm `actions: string[]` (mặc định rỗng). Hiện chỉ có `"enter"`: khi lời nói KẾT THÚC bằng cụm "nhấn enter" hoặc "bấm enter" (đúng ở cuối, bỏ dấu/viết hoa/dấu câu khi so khớp) và `actions_enabled` bật, engine cắt cụm đó khỏi `text` và trả `actions:["enter"]`; client dán rồi gửi phím Return. Không hành động nào khác được tạo từ lời nói.

## Snippets (đoạn văn mẫu gọi bằng lời)
`GET /v1/snippets` → `{ "entries": [ { "trigger": "link lịch hẹn", "text": "https://…", "uses": 3, "last_used": "…" } ] }`. `PUT /v1/snippets` thay toàn bộ (kiểm schema: `trigger` 1–60 ký tự, `text` 1–5.000 ký tự có thể nhiều dòng, trigger không trùng sau khi bỏ dấu/hoa thường, tối đa 500 mục). Lưu `~/.vflow/snippets.json` (0600), không nằm trong repo. Mở rộng: khi cả câu nói (bỏ dấu/hoa thường/dấu câu) bằng một trigger, HOẶC có dạng "chèn <trigger>" ở bất kỳ vị trí nào trong câu ⇒ thay bằng `text` nguyên văn (không qua từ điển, làm gọn hay viết lại); `post.applied` có `{type:"snippet", from:"<trigger>", to:"snippet"}` (không ghi nội dung snippet vào log). Không mở rộng ở nơi khác để tránh kích hoạt nhầm.

## Command Mode (sửa/soạn văn bản bằng lời)
Client ghi âm lệnh, gọi `POST /v1/transcribe` (`mode=normal`) để lấy chữ, rồi gọi `POST /v1/command` JSON `{ "instruction": "<lệnh>", "selection": "<đoạn đang chọn, có thể rỗng>", "context": "<văn bản xung quanh, tuỳ chọn>", "app": "<bundle id>" }` ⇒ 200 `{ "text": "<văn bản thay thế/soạn mới>", "kind": "edit|draft", "timings_ms": { "llm": 900 } }`. Có `selection` ⇒ `edit` (chỉ trả đoạn thay thế, không lời dẫn). Không có ⇒ `draft`. Giới hạn 20.000 ký tự mỗi trường. Lỗi (không đặt model, thiếu khoá, `cloud_disabled`, quá giờ, phản hồi rỗng/lạ) ⇒ HTTP 502/503 `{ "error": { "code": "rewrite_unavailable|cloud_disabled|timeout|bad_request", "message": "<tiếng Việt>" } }`, KHÔNG trả văn bản giả; client không dán gì.

## Cài đặt người dùng (`GET/PUT /v1/settings`)
`GET` →
```json
{ "cloud_llm": true, "llm_model": "ag/gemini-3.8-flash" | null, "llm_timeout_ms": 3500, "actions_enabled": true,
  "stats_enabled": true, "app_rules": { "com.apple.Terminal": "dev" }, "voice_punctuation": true, "context_symbols": true, "tone": "neutral",
  "whisper_mode": false, "learn_from_edits": true, "live_preview": true, "silence_stop_seconds": 0,
  "audio_history": false, "audio_history_mb": 200, "audio_history_days": 7 }
```
(không bao giờ trả khoá). `PUT` nhận tập con các trường (kiểm kiểu/giá trị), ghi vào `~/.vflow/config.json`, có hiệu lực ngay không cần khởi động lại:
- `llm_timeout_ms`: số nguyên 1.000–30.000, **mặc định mới 3.500** (item 7 — 8.000 cũ quá lâu để chờ; người dùng đã tự đặt giá trị khác thì giữ nguyên, mặc định chỉ áp khi khoá vắng mặt trong tệp).
- `llm_model`: chuỗi ≤ 200 ký tự hoặc null.
- `app_rules` (item 4): object `{ "<bundleId>": "normal"|"clean"|"dev"|"tidy"|"email" }`, tối đa 100 mục, bundle id dạng reverse-DNS (`^[A-Za-z][A-Za-z0-9]*(\.[A-Za-z0-9][A-Za-z0-9_-]*)+$`). `auto` tra bảng này TRƯỚC luật cứng `auto.apps` (cấu hình). Luật trỏ `tidy`/`email` chỉ có hiệu lực khi `cloud_llm` bật (xem mục Chế độ).
- `voice_punctuation`, `whisper_mode`, `learn_from_edits`, `live_preview`: boolean.
- `tone`: `"neutral"|"formal"|"casual"`.
- `silence_stop_seconds`: số nguyên 0–60 (0 = tắt); `live_preview`/`silence_stop_seconds` chỉ lưu cho client (engine không tự dùng). `live_preview` mặc định **`true`** (đổi từ `false`: đo thật p95 `/v1/partial` ở 10 s audio = 111 ms, dưới ngưỡng 500 ms).
- `stats_enabled`: boolean (xem mục Thống kê).
- `vocab_boost` ĐÃ GỠ (xem "Ghi chú đo: tăng cường từ khoá"): `PUT` khoá này ⇒ 400 `bad_request` (khoá lạ, như mọi khoá không có trong danh sách); `GET` không còn trả nó; gói `POST /v1/import` xuất từ bản cũ vẫn chứa nó thì khoá bị bỏ qua và báo `ignored:["vocab_boost"]` (không từ chối cả gói); giá trị còn sót trong `config.json` bị bỏ qua.
- `context_symbols` (boolean, mặc định **`true`**): bật ký hiệu theo ngữ cảnh ứng dụng (mục "Ký hiệu theo ngữ cảnh"); ngoài danh sách app cho phép thì bật hay tắt đều không đổi gì.
- `audio_history` (boolean, mặc định **`false`**): ghi lịch sử âm thanh (mục "Lịch sử âm thanh"). `POST /v1/import` KHÔNG bao giờ bật được khoá này (gói chứa `audio_history:true` bị loại và báo `ignored:["audio_history"]`; `false` thì áp dụng).
- `audio_history_mb`: số nguyên **50–2000**, mặc định **200** (ngân sách dung lượng kho âm thanh, MB = 1024²).
- `audio_history_days`: số nguyên **1–90**, mặc định **7** (hạn lưu, ngày).
- Giá trị sai kiểu/ngoài miền (vd `audio_history_mb:49`, `audio_history_days:1.5`, `audio_history:"true"`) ⇒ 400 `bad_request` và KHÔNG ghi gì. Ví dụ thật: `PUT {"audio_history_mb":10}` ⇒ `400 {"error":{"code":"bad_request","message":"audio_history_mb phải là số nguyên 50–2000"}}`.

`cloud_llm=false` ⇒ `tidy`, `email` và `/v1/command` không gọi LLM: `tidy`/`email` trả `rewrite.error="cloud_disabled"` và dùng văn bản đã qua từ điển (+ dấu câu bằng giọng); `/v1/command` trả `cloud_disabled`. Chế độ `normal`, `clean`, `dev` không bao giờ gọi LLM.

## Thống kê (`GET/DELETE /v1/stats`)
`GET /v1/stats?weeks=16` →
```json
{ "enabled": true, "since": "2026-09-01"|null, "weeks": 16, "week_start": "monday", "today": "2026-10-27",
  "total_words": 12345, "total_count": 321, "total_audio_ms": 9876543, "avg_wpm": 95|null,
  "current_streak": 4, "best_streak": 12,
  "days": [ { "date": "2026-09-08", "words": 0, "count": 0, "audio_ms": 0 }, … ],
  "top_apps": [ { "app": "com.apple.Terminal", "words": 5000, "count": 120 }, … ] }
```
`total_*`/`avg_wpm`/`current_streak`/`best_streak`/`top_apps` là TOÀN THỜI GIAN (từ `since`); `days[]` là cửa sổ `weeks` tuần kết thúc ở tuần chứa hôm nay (từ thứ Hai), đủ mọi ngày (ngày không có dữ liệu `words:0`), KHÔNG có ngày tương lai. `avg_wpm = total_words / (total_audio_ms/60000)` làm tròn 0 chữ số, `null` khi `total_audio_ms < 60000` (không đủ dữ liệu, không bịa số). `current_streak`: số ngày liên tiếp có `words>0` kết thúc hôm nay, HOẶC kết thúc hôm qua nếu hôm nay chưa có dữ liệu (chưa tính là mất chuỗi trong ngày). `weeks` phải là số nguyên 1–104, sai ⇒ `bad_request`.
Mỗi dictation THÀNH CÔNG (đã ra `text` cuối không rỗng, không phải Command Mode, không lỗi/im lặng) cộng `words` (token cách khoảng trắng có ≥ 1 chữ/số Unicode), `audio_ms`, `count+1`, theo `app` (thiếu ⇒ `"unknown"`) — KHÔNG cộng khi `stats_enabled=false` (không xoá dữ liệu cũ). Kho `$VFLOW_HOME/stats.json` (0600) CHỈ bộ đếm — không văn bản/âm thanh. Lần đầu chạy (chưa có `stats.json`) backfill từ `history.jsonl` hiện có (cùng cách đếm, bỏ Command Mode/dòng hỏng); chỉ backfill MỘT LẦN.
`DELETE /v1/stats` → `{"ok":true}`, xoá toàn bộ và đặt lại mốc để KHÔNG tự backfill lại từ history.

## Gợi ý từ điển (`GET /v1/dictionary/suggestions`, `POST /v1/dictionary/suggestions/dismiss`)
`GET` → `{ "suggestions": [ { "term": "Supabase", "variants": ["xu pa bết"], "count": 3, "last_seen": "2026-10-26T01:00:00.000Z" } ] }` — chỉ cặp (term, cách nói) xuất hiện ≥ 2 lần qua `POST /v1/corrections` (khi `learn_from_edits` bật), CHƯA có trong từ điển, chưa bị `dismiss`. `POST .../dismiss` nhận `{"term":"…"}` → `{"ok":true}`, không hiện lại gợi ý của `term` đó. Lưu `$VFLOW_HOME/corrections.json` (0600, tối đa 500 sự sửa gần nhất, chỉ cụm ngắn ≤ 5 từ, không lưu cả câu, KHÔNG gửi gì lên mạng).

## Xem chữ chạy trực tiếp (`POST /v1/partial`)
Nhận PCM như `/v1/transcribe` (cùng `Content-Type`/token), query `model` tuỳ chọn. Trả `{ "text": "…", "audio_ms": 1500, "stt_ms": 120 }` — CHỈ văn bản thô sau từ điển nhẹ (không tăng `uses`/không ghi tệp), KHÔNG post xử lý nặng (không clean/devspeech/dấu câu bằng giọng), KHÔNG LLM, KHÔNG ghi history/thống kê. Tối đa 1 yêu cầu đồng thời — bận ⇒ 429 `{"error":{"code":"busy", "message":"…"}}` (client tự bỏ qua). Giới hạn audio 30 giây; dài hơn ⇒ CHỈ xử lý 30 giây CUỐI.

## Dạy từ nghe thử (`POST /v1/teach`)
Để người dùng THẤY model nghe sai ra sao rồi thêm vào từ điển. Body/`Content-Type`/token y hệt `/v1/transcribe` (PCM `audio/L16; rate=16000; channels=1` hoặc `audio/wav`), query `model` tuỳ chọn (mặc định `default_model`; model lạ ⇒ 400 `bad_request`). 200 `{ "heard": "<chữ thô, chữ thường, khoảng trắng gọn>", "audio_ms": 3740, "stt_ms": 53 }` — đúng ba khoá. Ví dụ thật (model `zipformer-vi-30m`, câu thử `test_wavs/0.wav`):
```json
{ "heard": "rồi cũng hỗ trợ cho lâu lâu cũng cho gạo cho này kia", "audio_ms": 3740, "stt_ms": 53 }
```
Quy tắc: CHỈ chữ thô của STT (đổi về chữ thường) — KHÔNG qua từ điển/snippet/làm sạch/dấu câu/LLM (luôn giải mã `greedy_search`, mục đích là thấy đúng lỗi nhận dạng). KHÔNG ghi `history.jsonl`/`stats.json`/`uses` từ điển, KHÔNG ghi âm thanh (kể cả khi `audio_history=true`). Tối đa **15 giây** (đúng 15,0 s vẫn nhận; dài hơn ⇒ 413 `too_long`, KHÔNG cắt): `{"error":{"code":"too_long","message":"Âm thanh dài 18.7 s, vượt giới hạn 15 s (không tự cắt)."}}`. Tối đa 1 yêu cầu cùng lúc: đang bận ⇒ 429 `busy` (cờ bận được nhả cả khi yêu cầu lỗi). Im lặng ⇒ 200 `{ "heard": "", "audio_ms": …, "stt_ms": 0 }`. Lỗi khác: 400 `bad_audio` (không phải WAV/L16 hợp lệ), 401 `unauthorized`, 405 nếu không phải POST, 503 `model_unavailable`. Không xếp vào hàng đợi tuần tự của `/v1/transcribe` (như `/v1/partial`): có thể chạy chồng lên một dictation đang giải mã.

## Ký hiệu theo ngữ cảnh (`context_symbols`)
Lời đọc ký hiệu CHỈ được đổi thành ký tự khi tham số `app` (bundle id, so khớp CHÍNH XÁC, phân biệt hoa/thường) thuộc danh sách dưới; ngoài danh sách (Notes, Mail…, hoặc không gửi `app`) lời nói thường GIỮ NGUYÊN ("gạch dưới" vẫn là chữ). Cài đặt `context_symbols=false` tắt hẳn.
- Terminal: `com.apple.Terminal`, `com.googlecode.iterm2`, `dev.warp.Warp-Stable`, `com.mitchellh.ghostty`, `org.alacritty`, `io.alacritty`, `net.kovidgoyal.kitty`, `com.github.wez.wezterm`.
- IDE/trình soạn thảo: `com.microsoft.VSCode`, `com.microsoft.VSCodeInsiders`, `com.vscodium`, `com.todesktop.230313mzl4w4u92` (Cursor), `com.apple.dt.Xcode`, `dev.zed.Zed`, `com.sublimetext.3`, `com.sublimetext.4`, `com.panic.Nova`, và MỌI id bắt đầu bằng `com.jetbrains.`.
- Công cụ AI: `com.anthropic.claudefordesktop`, `com.openai.chat`. Chat nhóm: `com.tinyspeck.slackmacgap` (Slack), `com.hnc.Discord`, `com.microsoft.teams2`, `com.microsoft.teams`. Cố ý KHÔNG có (chưa xác nhận được bundle id, không đoán): Codex app, Orca, Windsurf.

Từ khoá (không phân biệt hoa/thường và dấu thanh sắc/huyền/hỏi/ngã/nặng; GIỮ phân biệt ă/â/ê/ô/ơ/ư/đ; giữa các từ của một cụm chỉ cho khoảng trắng hoặc gạch nối):
| Nói | Ra | Ghi chú |
|---|---|---|
| hai chấm hai gạch chéo | `://` | dính hai phía |
| gạch chéo ngược | `\` | dính hai phía |
| gạch chéo | `/` | dính hai phía |
| gạch nối gạch nối | `--` | cờ dòng lệnh: GIỮ khoảng trắng trước, dính vào từ sau ("git gạch nối gạch nối help" ⇒ `git --help`) |
| gạch nối | `-` | dính hai phía ("tên gạch nối lửa" ⇒ `tên-lửa`) |
| gạch dưới | `_` | dính hai phía |
| a còng + từ | `@từ` | nhắc tên/email; thêm 1 dấu cách phía sau CHỈ khi còn chữ/số tiếp theo (cuối câu hoặc trước dấu câu thì không: "gửi cho an a còng example" ⇒ `gửi cho an@example`, "an a còng example rồi chạy" ⇒ `an@example rồi chạy`); Slack/Discord/Teams GIỮ khoảng trắng trước `@` ("chào a còng nam" ⇒ `chào @nam`), terminal/IDE dính liền ("nam a còng gmail" ⇒ `nam@gmail`); "a còng" đứng cuối hoặc sau nó có dấu ngắt mệnh đề ⇒ `@` trần |
| dấu thăng / dấu đô la / dấu và / dấu sao / dấu bằng / dấu cộng | `#` / `$` / `&` / `*` / `=` / `+` | dính hai phía |
| gạch chéo + từ (CHỈ ở ĐẦU câu, CHỈ Slack/Discord) | `/từ` | lệnh slash ("gạch chéo deploy staging" ⇒ `/deploy staging`); 1 dấu cách sau `/từ` CHỈ khi còn chữ/số phía sau — "gạch chéo deploy" cuối câu ⇒ `/deploy` (không dư khoảng trắng) |

Ví dụ thật qua `POST /v1/transcribe?mode=normal&app=<id>` (âm thanh tổng hợp bằng giọng TTS `Linh`; chữ STT thô sai chính tả là của model, ký hiệu là của engine) — cùng âm thanh, `app=com.apple.Terminal` so với `app=com.apple.Notes`:
```json
{ "app": "com.apple.Terminal", "text_raw": "mở fi a gạch dưới bờ", "text": "mở fi a_bờ", "post.applied": [ { "type": "context_symbol", "from": "gạch dưới", "to": "_" } ] }
{ "app": "com.apple.Notes",    "text_raw": "mở fi a gạch dưới bờ", "text": "mở fi a gạch dưới bờ", "post.applied": [] }
{ "app": "com.apple.Terminal", "text_raw": "giúp gạch nối gạch nối hét", "text": "giúp --hét", "post.applied": [ { "type": "context_symbol", "from": "gạch nối gạch nối", "to": "--" } ] }
{ "app": "com.apple.Terminal", "text_raw": "truy cập tờ hai chấm hai gạch chéo ví dụ", "text": "truy cập tờ://ví dụ", "post.applied": [ { "type": "context_symbol", "from": "hai chấm hai gạch chéo", "to": "://" } ] }
```
Quan hệ với các bước khác: thứ tự trong hậu xử lý là snippet ⇒ hành động cuối câu ⇒ từ điển ⇒ **ký hiệu theo ngữ cảnh** ⇒ (quy tắc `dev`/`tidy`) ⇒ dấu câu bằng giọng (`voice_punctuation`, KHÔNG chạy ở `dev`) ⇒ làm sạch/LLM. Hai bộ từ khoá tách biệt (dấu câu: "dấu chấm", "xuống dòng", "gạch ngang"…; ký hiệu: bảng trên) nên không giành nhau; mỗi lần thay ghi `{type:"context_symbol", from, to}` vào `post.applied`. Hạn chế đã biết (cùng kiểu quy tắc `dev` có sẵn, KHÔNG phải lỗi ngẫu nhiên): ký hiệu dính hai phía nên "cd gạch chéo users" ⇒ `cd/users` (không có cách nhận biết đường dẫn tuyệt đối sau một lệnh), và "gạch nối" đơn không tách được "a-b" khỏi "ls -la".

## Ghi chú đo: tăng cường từ khoá (hotwords) — ĐÃ GỠ KHỎI ENGINE
Khoá cài đặt `vocab_boost` và toàn bộ đường hotwords/`modified_beam_search` đã bị gỡ (2026-10-27) sau khi đo thật; đừng làm lại từ đầu. Cấu hình đo (Mac M1 Pro, `sherpa-onnx-node` 2.0.0, model `zipformer-vi-30m`, 2 luồng; 13 clip = 35,1 s gồm 8 câu TTS tiếng Việt chứa 21 cụm thuật ngữ từ `config/dictionary.seed.json`, 2 câu TTS thường, 3 câu giọng thật `test_wavs/`; lặp 5 lần; TTS không thay thế giọng người): `greedy_search` 380 ms (RTF 0,011), trúng 1/21 cụm, WER câu thuật ngữ 36,7%; `modified_beam_search` không hotwords 507 ms (+33%), 1/21, 38,0%; thêm hotwords 20 mục 560 ms, 100 mục 679 ms, vẫn 1/21 và 38,0% — đầu ra GIỐNG HỆT câu nào cũng vậy (thử điểm 10, 30 cũng không đổi). Lý do không dùng: gói model không kèm `modelingUnit`/`bpeVocab` nên addon rơi về `cjkchar` và tách từng ký tự không-ASCII ("▁", "Đ", "Ô"…) thành token riêng ⇒ token hotword lệch token model phát ra (log addon `Cannot find ID for token …`); xấp xỉ `bpe` với `bpe.vocab` dựng từ `tokens.txt` cũng không cải thiện (điểm 5: WER 39,2%; điểm 10: 50,6%); chi phí chắc chắn là +28–35% thời gian giải mã và một recognizer thứ hai trong RAM. Hướng còn bỏ ngỏ (chưa làm): ghép từ điển ở hậu xử lý theo khoảng cách chỉnh sửa có kiểm soát giữa chữ STT và biến thể `spoken` (ước lượng thô chạm ~9/21 cụm nhưng cửa sổ 1 âm tiết có nhiều dương tính giả; cần đo lại bằng giọng người dùng).

## Lịch sử âm thanh (`audio_history`)
Tuỳ chọn riêng tư, mặc định TẮT. Bật bằng `PUT /v1/settings {"audio_history":true}`. Lịch sử dictation (`history.jsonl`) là của CLIENT; engine KHÔNG đọc/ghi nó và KHÔNG có `GET /v1/history`. Engine chỉ giữ MỘT kho WAV độc lập, khoá bằng chính `id` dictation (`audio_id`): client tự lưu `audio_id` vào mục lịch sử của nó và tự gọi `DELETE /v1/audio/<id>` khi xoá mục.
- Nơi lưu: `$VFLOW_HOME/audio/<id>.wav` + `index.json`; thư mục `0700`, tệp `0600` (ép lại mỗi lần ghi, kể cả khi thư mục có sẵn quyền rộng). WAV PCM 16-bit **mono 16 kHz** (header 44 byte chuẩn; đầu vào tần số/số kênh khác được đổi về 16 kHz mono). Là âm thanh GỐC người dùng nói: `whisper_mode` chỉ khuếch đại phía STT, không ghi bản khuếch đại. Ghi nguyên tử (tệp tạm + rename).
- Chỉ ghi khi dictation thành công (xem `audio_id`). `/v1/teach`, `/v1/partial`, Command Mode KHÔNG ghi.
- Ngân sách: tổng ≤ `audio_history_mb` — vượt thì đuổi tệp CŨ NHẤT trước cho tới khi vừa; hạn: tệp cũ hơn `audio_history_days` ngày bị xoá. Quét: lúc engine khởi động, sau mỗi lần ghi, mỗi lần `GET /v1/audio`, và mỗi 1 giờ (timer không giữ tiến trình sống). Tắt `audio_history` chỉ dừng ghi MỚI — tệp cũ vẫn bị hạn/ngân sách xoá dần, và người dùng xoá ngay bằng `DELETE /v1/audio`. Không đọc được cài đặt (config hỏng) ⇒ bỏ lần quét đó, KHÔNG xoá gì, ghi log mã lỗi.
- AN TOÀN DỮ LIỆU khi khởi động: `index.json` chỉ là bản ghi phụ trợ, nguồn sự thật là các WAV trên đĩa. Mục lục không đọc được (JSON hỏng, rỗng, `items` không phải mảng) ⇒ KHÔNG xoá WAV nào; dựng lại: `id` từ tên tệp, `bytes` từ kích thước, `audio_ms` từ header WAV (PCM 16-bit mono 16 kHz), `at` từ mtime, `app`/`mode` = `null`; ghi lại `index.json` nguyên tử (0600), log `audio_index_recovered` (chỉ mã lý do + số lượng, không nội dung). Mục lục đọc được nhưng thiếu mục cho WAV có thật, hoặc có mục sai kiểu/thiếu trường ⇒ WAV đó được nhận lại như trên; mục trỏ tới tệp đã mất bị bỏ. Tệp `.wav` không phân tích được header (rỗng, rác, cụt, sai định dạng) ⇒ chuyển vào `audio/quarantine/` (0700), KHÔNG xoá, không tính ngân sách, không liệt kê; không chuyển được thì để nguyên tại chỗ (log `audio_quarantine_failed`). Chỉ tệp tạm `*.tmp-*` (bản ghi dở do bị ngắt) bị xoá. SAU khi dựng lại, đuổi theo ngân sách/hạn ngày vẫn chạy bình thường (hạn tính theo `at`, tức mtime với tệp được nhận lại).
- `GET /v1/audio` → `{ "enabled": <audio_history>, "count": N, "bytes": tổng, "budget_bytes": …, "days": …, "index_rebuilt": false, "recovered": 0, "quarantined": 0, "items": [ { "id", "bytes", "audio_ms", "at" } ] }` — mới nhất trước, tối đa 500 mục (`count`/`bytes` là tổng của TOÀN kho). Ba trường cuối báo tình trạng phục hồi: `index_rebuilt` (boolean, từ lúc engine khởi động) = `true` khi `index.json` hỏng/rỗng/sai hình dạng/mất hẳn trong khi còn WAV nên mục lục đã được dựng lại; `recovered` = số WAV được nhận lại từ đĩa lúc khởi động (kể cả khi mục lục chỉ thiếu mục); `quarantined` = số tệp hiện nằm trong `quarantine/` (đếm trực tiếp). Ví dụ thật:
```json
{ "enabled": false, "count": 2, "bytes": 196568, "budget_bytes": 209715200, "days": 7,
  "index_rebuilt": true, "recovered": 2, "quarantined": 1,
  "items": [ { "id": "tr_demo_b", "bytes": 76844, "audio_ms": 2400, "at": "2026-10-27T00:58:14.581Z" },
             { "id": "tr_demo_a", "bytes": 119724, "audio_ms": 3740, "at": "2026-10-27T00:58:14.580Z" } ] }
```
(Ví dụ thật: `index.json` bị cắt hỏng `{"items": [ {"id": `, hai WAV hợp lệ + một tệp `tr_rac.wav` không phải WAV. Sau khi engine khởi động: hai WAV còn nguyên và tải lại được byte y hệt, `index.json` được ghi lại, `tr_rac.wav` nằm trong `audio/quarantine/`.)
- `GET /v1/audio/<id>` → 200 `audio/wav` (`cache-control: no-store`, stream từ đĩa, không hỗ trợ Range). `id` phải khớp `^[A-Za-z0-9_-]+$`; id sai định dạng (`..%2ftoken`, có `/`, `\`, `.`) hay không có ⇒ như nhau: 404 `{"error":{"code":"not_found","message":"Không có tệp âm thanh này."}}` (không phân biệt, không đọc/xoá được gì ngoài `audio/`). `export` là id dành riêng cho đường dẫn bên dưới.
- `DELETE /v1/audio/<id>` → `{ "ok": true, "deleted": 1 }` hoặc 404 `not_found` (đã xoá/không có). `DELETE /v1/audio` → `{ "ok": true, "deleted": N }` (N = số mục trong mục lục; 0 khi rỗng) và xoá luôn các tệp trong `quarantine/` (đây là yêu cầu chủ động của người dùng xoá hết giọng đã lưu).
- `GET /v1/audio/export` → 200 `application/zip` (kiểu "store", không nén; CRC32 đúng, đọc được bằng `unzip -t`). Gồm `index.json` — MẢNG các `{ "id", "at", "audio_ms", "app", "mode" }` (`app`/`mode` có thể `null`; KHÔNG có văn bản dictation vì engine không giữ) — và `<id>.wav` cho từng mục. Kho rỗng/đang tắt ⇒ ZIP hợp lệ chỉ có `index.json` = `[]`. Stream từng tệp có backpressure (máy khách tải chậm không làm RAM engine phình ra; bỏ tải giữa chừng ⇒ ngắt kết nối, ZIP dở KHÔNG hợp lệ). Ví dụ thật của `unzip -p audio.zip index.json`:
```json
[ { "id": "tr_mvpyanl1ae825c5bc1d2", "at": "2026-10-27T00:32:01.039Z", "audio_ms": 3740, "app": "com.apple.Terminal", "mode": "dev" },
  { "id": "tr_mvpyanoj4050b5eb1583", "at": "2026-10-27T00:32:01.149Z", "audio_ms": 2400, "app": null, "mode": "clean" } ]
```
- Mọi route trên cần token (401 nếu thiếu). `GET /v1/export` và `GET /v1/diagnostics` KHÔNG BAO GIỜ chứa âm thanh, `audio_id`, tên tệp hay đường dẫn kho; lỗi 404 của `/v1/audio/<id>` vào `recent_errors` được ghi là `/v1/audio/:id` (id không lưu lại).

## Ghi âm dài
`/v1/transcribe` nhận tối đa **1.200 giây (20 phút)** âm thanh (`payload_too_large` nếu vượt). STT cục bộ (model offline-transducer) xử lý audio dài hơn ~35 giây theo ĐOẠN (mặc định 25 giây/đoạn, chồng lấn 1,5 giây, ưu tiên cắt ở khoảng lặng) để RAM/thời gian không tăng vô hạn theo độ dài — ghép lại bằng so khớp từ chồng lấn ở biên, không lặp/mất chữ. Âm thanh ngắn hơn ngưỡng đi thẳng qua đường một lần như trước (không thêm độ trễ).

## Xuất/nhập (`GET /v1/export`, `POST /v1/import?mode=merge|replace`)
`GET /v1/export?include_history=0|1` (mặc định 0) →
```json
{ "format": "vflow-export", "version": 1, "exported_at": "2026-10-27T00:00:00.000Z",
  "dictionary": [...], "snippets": [...], "settings": {...không token/khoá...},
  "stats": { "backfilled": true, "days": {...} }, "history": [...] (chỉ khi include_history=1) }
```
`POST /v1/import?mode=merge|replace` (mặc định `merge`) nhận đúng cấu trúc đó: kiểm hợp lệ NGHIÊM toàn bộ TRƯỚC (kích thước ≤ 20 MB, `format`/`version`, kiểu từng trường, giới hạn độ dài/số lượng như từ điển/snippets hiện có) — sai BẤT KỲ PHẦN NÀO thì từ chối CẢ GÓI (không nhập nửa vời), lỗi chỉ rõ phần/chỉ mục (vd `"dictionary: entries[2].term …"`). `merge`: dictionary/snippets/history merge theo khoá duy nhất (term/trigger đã chuẩn hoá/id) KHÔNG tạo trùng (giữ bản hiện có khi đụng); `stats.days` merge CỘNG DỒN bộ đếm theo ngày; `settings` áp tập con đã cho (giống PUT). `replace`: dictionary/snippets/history bị THAY HOÀN TOÀN bởi phần có trong gói (phần KHÔNG có trong gói giữ nguyên); `stats.days` thay toàn bộ. Trả `{"ok":true, "applied":{"dictionary":n,"snippets":n,"settings":n,"stats_days":n,"history":n}, "ignored":["token",...] (chỉ khi có)}`. KHÔNG BAO GIỜ nhập token/khoá dù gói có (tự lọc, báo qua `ignored`).

## Chẩn đoán (`GET /v1/diagnostics`)
```json
{ "engine_version": "0.1.0", "node": "v22.x", "platform": "darwin-arm64", "uptime_s": 120,
  "model": { "default": "zipformer-vi-30m", "status": [...như /healthz...] },
  "stt": { "default": "zipformer-vi-30m" }, "settings": {...như GET /v1/settings...},
  "counts": { "dictionary": 12, "snippets": 3, "history": 40, "stats_days": 9 },
  "paths": { "home_basename": ".vflow" },
  "recent_errors": [ { "at": "2026-10-27T00:00:00.000Z", "route": "/v1/transcribe", "status": 503, "code": "model_unavailable" } ] }
```
Tối đa 50 dòng `recent_errors` gần nhất (chỉ `{at,route,status,code}` — KHÔNG văn bản dictation, KHÔNG token/khoá, `route` của `/v1/audio/<id>` luôn là `/v1/audio/:id`); đường dẫn dưới `$VFLOW_HOME`/thư mục home rút gọn thành `~`. Không có số đếm/dung lượng/tên tệp âm thanh (lấy qua `GET /v1/audio`).

## Ghi chú LLM (endpoint OpenAI-compatible, ví dụ 9Router)
Luôn gửi `"stream": false`. Máy chủ đã thấy trả luồng SSE (`data: {...}` từng dòng) dù không yêu cầu stream: client LLM của engine phải đọc được CẢ phản hồi JSON thường LẪN SSE (ghép `delta.content`), nếu không đọc được ⇒ `bad_response`. Khoá lấy từ `rewrite.key_file` (mặc định `~/.vflow/rewrite.key`), không bao giờ vào log/phản hồi/lỗi. `llm_model` trong `/v1/settings` ưu tiên hơn `rewrite.model` trong cấu hình.

## Bất biến cần test
1. Âm thanh chỉ được ghi xuống đĩa khi NGƯỜI DÙNG bật `audio_history` (mặc định tắt; không tệp/lệnh import nào bật được), nằm DUY NHẤT trong `$VFLOW_HOME/audio` (thư mục 0700, tệp 0600), có ngân sách MB và hạn ngày, và KHÔNG BAO GIỜ có trong `GET /v1/export` hay `GET /v1/diagnostics`. Mọi đường khác (`/v1/teach`, `/v1/partial`, dictation khi tắt) không ghi âm thanh. Log không chứa văn bản giọng nói hay đường dẫn kho.
2. Viết lại/làm gọn lỗi ⇒ `text` là văn bản đã qua từ điển và quy tắc (chưa qua LLM), `text_raw` giữ nguyên chữ STT gốc, và `rewrite.error` có giá trị.
3. Thiếu/sai token ⇒ 401 `unauthorized`; `Host` lạ ⇒ từ chối.
4. Model thiếu/hỏng ⇒ `model_unavailable` kèm lý do, không rơi về model khác một cách âm thầm.
5. Khoá viết lại không xuất hiện trong bất kỳ log/phản hồi/lỗi nào.
6. LLM làm gọn không được thêm nội dung: nếu đầu ra có từ/số/thuật ngữ không có trong đầu vào (ngoài dấu câu và dấu đánh số) quá ngưỡng thì bị `guard_rejected`.
7. `snippet` không bao giờ bị sửa bởi từ điển/làm gọn/viết lại; chỉ mở rộng đúng hai dạng đã nêu.
8. `actions:["enter"]` chỉ xuất hiện khi cụm đứng ĐÚNG ở cuối lời nói và `actions_enabled` bật.
9. `cloud_llm=false` ⇒ không có yêu cầu mạng nào tới endpoint LLM (kiểm bằng máy chủ giả đếm yêu cầu).
10. Với cấu hình mặc định, `mode=auto` KHÔNG BAO GIỜ gọi LLM (kiểm bằng máy chủ giả đếm 0 yêu cầu qua mọi `app` trong `auto.apps` mặc định). Chỉ chọn thủ công `tidy`/`email` hoặc tự sửa `app_rules`/`auto.apps` mới gửi chữ ra LLM; nếu `cloud_llm` đang tắt thì dù `app_rules`/`auto.apps` trỏ `tidy`/`email`, `auto` vẫn KHÔNG gọi LLM (rơi về `clean`).
11. Thống kê (`stats.json`) CHỈ là bộ đếm (words/audio_ms/count theo ngày/app) — không bao giờ chứa văn bản dictation hay âm thanh; tắt `stats_enabled` không xoá dữ liệu đã có; xoá/tắt `history_enabled` (client) không ảnh hưởng tới thống kê đã ghi.
12. `GET /v1/export` không bao giờ chứa token/khoá 9Router (`rewrite.key`); `POST /v1/import` cũng không bao giờ ÁP DỤNG token/khoá dù gói chứa chúng (tự lọc, báo `ignored`), và từ chối CẢ GÓI nếu bất kỳ phần nào sai (không nhập nửa vời — kiểm bằng cách cố ý làm hỏng một phần, phần còn lại hợp lệ, rồi xác nhận không có gì bị thay đổi).
13. `GET /v1/diagnostics` không bao giờ chứa token/khoá 9Router hay văn bản dictation, dù vừa có lỗi/dictation xảy ra ngay trước đó.
14. Dấu câu bằng giọng KHÔNG BAO GIỜ kích hoạt từ một từ đứng riêng ("chấm", "hỏi") — chỉ cụm ≥ 2 từ đã nêu; không chạy ở chế độ `dev`.
15. `voice_punctuation=false` ⇒ không cụm nào trong mục "Lệnh dấu câu bằng giọng" được thay, ở mọi chế độ.
16. `tone` (`formal`/`casual`) không được làm guard của `tidy` (bất biến 6) bỏ qua hay nới lỏng — đầu ra thêm nội dung vẫn bị `guard_rejected` dù `tone` nào.
17. `/v1/partial` không bao giờ ghi vào `history.jsonl`/`stats.json`, không tăng `uses` của mục từ điển nào, và chỉ xử lý tối đa 1 yêu cầu cùng lúc (yêu cầu thứ hai khi đang bận ⇒ `busy`).
18. STT cục bộ cho audio dài (> ngưỡng theo đoạn) không giữ RAM tăng vô hạn theo độ dài — đo bằng `/usr/bin/time -l` với audio tổng hợp 5 phút và 20 phút, RAM đỉnh phải không tăng tuyến tính so với không chia đoạn.
19. `audio_id` chỉ có trong phản hồi dictation khi `audio_history=true` và dictation thành công và tệp thật sự còn tồn tại; luôn vắng khi tắt/im lặng/văn bản rỗng/ghi lỗi. Tổng kho âm thanh ≤ `audio_history_mb` sau mỗi lần ghi và tệp bị đuổi theo thứ tự CŨ NHẤT trước; tệp quá `audio_history_days` bị xoá ở lần quét kế tiếp (kể cả lúc khởi động).
20. WAV trong kho luôn là PCM 16-bit mono 16 kHz hợp lệ (header khớp độ dài dữ liệu); `id` không khớp `^[A-Za-z0-9_-]+$` (path traversal) không bao giờ đọc/ghi/xoá được tệp ngoài `$VFLOW_HOME/audio`.
21. `/v1/teach` trả chữ thô CHƯA qua từ điển, không bao giờ ghi history/thống kê/âm thanh, chỉ 1 yêu cầu cùng lúc (`busy`), tối đa 15 s (`too_long`, không cắt).
22. Ký hiệu theo ngữ cảnh chỉ áp dụng khi `app` thuộc danh sách cho phép và `context_symbols` bật; ngoài danh sách lời nói thường giữ nguyên.
23. `POST /v1/import` không bao giờ bật `audio_history`.
24. Mục lục `audio/index.json` hỏng/rỗng/sai hình dạng/thiếu mục KHÔNG BAO GIỜ làm mất WAV hợp lệ: engine dựng lại mục lục từ các tệp trên đĩa; chỉ tệp `.wav` không phân tích được header mới bị chuyển vào `audio/quarantine/` (không xoá, không tính ngân sách); chỉ `DELETE /v1/audio` (người dùng) mới xoá quarantine.
25. `@tên` và `/lệnh` chỉ kèm 1 dấu cách phía sau khi CÒN chữ/số tiếp theo; câu kết thúc hoặc dấu câu theo sau thì KHÔNG dư khoảng trắng.
