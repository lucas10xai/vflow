# Hợp đồng engine vflow (v0.1)

Engine là tiến trình Node chạy cục bộ. Client (Swift, CLI, test) chỉ nói chuyện qua HTTP này. Mọi worker phải tuân theo; muốn đổi thì hỏi coordinator.

## Ràng buộc chung
- Chỉ nghe `127.0.0.1` (mặc định cổng `7611`, đổi bằng `VFLOW_PORT`). Không bao giờ `0.0.0.0`.
- Mọi yêu cầu (trừ `/healthz`) cần `Authorization: Bearer <token>`; token sinh ngẫu nhiên 32 byte, lưu `~/.vflow/token` (quyền 0600). Từ chối nếu `Host` không phải `127.0.0.1:<cổng>` hoặc `localhost:<cổng>` (chặn DNS rebinding), không gửi CORS header.
- Âm thanh: **không ghi ra đĩa**, không log nội dung âm thanh hay văn bản; log chỉ có id, thời lượng, thời gian xử lý, mã lỗi.
- Lỗi: HTTP 4xx/5xx kèm `{"error":{"code":"<snake_case>","message":"<tiếng Việt>"}}`. Mã: `unauthorized`, `bad_audio`, `bad_request`, `model_unavailable`, `timeout`, `payload_too_large` (giới hạn 1200 giây/20 phút âm thanh ở `/v1/transcribe`, 30 giây ở `/v1/partial`), `internal`, `rewrite_unavailable`, `cloud_disabled`, `busy` (429 — `/v1/partial` đang bận, client tự bỏ qua yêu cầu).

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
            "rewrite": { "used": false, "error": null },
            "degraded": false, "degraded_reason": null } }
```
Quy tắc: `text_raw` luôn là chữ gốc do STT trả về, không đổi. `text` luôn có giá trị dùng được. Nếu bước viết lại (`email`) lỗi hoặc quá thời gian thì `text` = văn bản đã qua từ điển nhưng CHƯA viết lại (không áp thêm `clean`), `rewrite = {used:false,error:"<mã>"}` (không báo thành công giả). Âm thanh rỗng/im lặng trả `text:""` kèm `"silence":true`, không phải lỗi.

`post.degraded`/`post.degraded_reason` (item 7): `true` kèm một trong `"llm_timeout"|"llm_error"|"guard"|"cloud_disabled"` khi kết quả là bản dự phòng cục bộ thay cho đám mây đã định — do LLM quá `llm_timeout_ms`/lỗi/bị guard chặn (`tidy`/`email`), hoặc do `auto` tra `app_rules`/`auto.apps` ra `tidy`/`email` nhưng `cloud_llm` đang tắt (mode trả về đã là `clean`, không phải `tidy`/`email`). `false`/`null` khi không có gì suy giảm (gồm cả khi người dùng CHỌN THẲNG `normal`/`clean`/`dev`, hoặc `tidy`/`email` thành công).

## Từ điển cá nhân
`GET /v1/dictionary` → `{ "entries": [ { "term": "deploy", "spoken": ["đi plôi","đì ploi"], "kind": "term", "uses": 12, "last_used": "2026-10-26T01:00:00Z" } ] }`
`PUT /v1/dictionary` thay toàn bộ (kiểm schema, tối đa 5.000 mục). `POST /v1/corrections` với `{ "before": "…", "after": "…" }` → `{ "suggestions": [ { "term": "…", "spoken": ["…"] } ] }` (phản hồi ngay chỉ là gợi ý, KHÔNG tự thêm vào từ điển — người dùng xác nhận mới ghi qua `PUT /v1/dictionary`; đồng thời, nếu `learn_from_edits` bật, engine LƯU LẠI cặp này để tổng hợp `GET /v1/dictionary/suggestions` khi đủ ≥ 2 lần — xem mục "Gợi ý từ điển"). Tệp lưu `~/.vflow/dictionary.json` (0600), không nằm trong repo. Hạt giống `config/dictionary.seed.json` chỉ chứa thuật ngữ chung, không có tên riêng/khoá.

## Cấu hình (`~/.vflow/config.json`, tất cả có mặc định)
`default_model`, `rewrite.url` (mặc định `http://127.0.0.1:20128/v1`), `rewrite.model`, `rewrite.timeout_ms` (mặc định 8000), `rewrite.key_file` (đường dẫn tệp chứa khoá; **không** chứa khoá trực tiếp trong cấu hình), `auto.apps` (bảng ánh xạ `{ "<bundleId>": "normal|clean|email" }` cho chế độ `auto`; có mặc định, sửa được). `remote.phowhisper.url`.

## Chế độ
- `normal`: STT + từ điển + **dấu câu bằng giọng** (xem mục riêng dưới).
- `clean`: như `normal` + bỏ từ đệm (ừm, à, ờ, uh…) và sửa dấu cách/chấm câu cơ bản; thuần quy tắc, không gọi LLM.
- `email`: STT + từ điển + dấu câu bằng giọng + viết lại thành thư chuyên nghiệp qua endpoint OpenAI-compatible (`/chat/completions`, theo `tone`); chỉ gửi **văn bản** (không âm thanh).
- `auto`: tra `app_rules` (cài đặt, item 4) TRƯỚC, rồi `auto.apps` (cấu hình cứng) theo `app`. **Mặc định CHỈ chọn chế độ chạy trong máy, không bao giờ gọi LLM**: terminal/IDE (Terminal, iTerm2, Warp, VS Code, Cursor, Ghostty) → `dev`; ứng dụng thư và nhắn tin (Mail, Outlook, Slack, Telegram, Discord, Tin nhắn, WhatsApp…) → `clean`; còn lại → `normal`. `tidy` và `email` chỉ dùng khi người dùng CHỦ ĐỘNG chọn chúng (hoặc tự ánh xạ trong `app_rules`/`auto.apps`); khi đó văn bản của app đó sẽ được gửi qua LLM — TRỪ khi `cloud_llm` đang tắt, lúc đó `auto` rơi về `clean` NGAY (không thử gọi LLM) và báo `degraded_reason:"cloud_disabled"`.
- `tidy` ("Gọn"): STT + từ điển + snippets + quy tắc đọc kiểu lập trình + dấu câu bằng giọng + **LLM làm gọn** qua endpoint OpenAI-compatible (theo `tone`): tự thêm dấu câu và viết hoa, bỏ từ đệm, hiểu tự sửa giữa câu (backtrack: "…thứ Sáu, à nhầm, thứ Năm" chỉ giữ "thứ Năm"), định dạng danh sách khi người nói liệt kê. Chỉ gửi **văn bản**. KHÔNG được thêm ý, số, tên hay thuật ngữ không có trong lời nói — guard độc lập với `tone`. Lỗi/quá giờ/bị chặn bởi guard ⇒ `text` = văn bản đã qua từ điển, quy tắc lập trình và `clean` (không LLM), `rewrite = {used:false, error:"<mã>"}` (mã thêm: `guard_rejected`, `cloud_disabled`), `degraded:true`.
- `dev` ("Lập trình"): như `clean` + quy tắc đọc kiểu lập trình (thuần quy tắc, không LLM, không gửi gì ra ngoài, **KHÔNG** chạy dấu câu bằng giọng): "gạch dưới" → `_`, "gạch ngang" → `-`, "gạch chéo" → `/`, "hai chấm" → `:`, "chấm" giữa hai định danh (hoặc trước đuôi tệp đã biết) → `.`, "viết thường nối gạch dưới a b c" → `a_b_c` (snake_case), "camel case a b c" → `aBC` đúng quy ước, v.v. Chỉ áp dụng ở dạng cụm không nhập nhằng; không đổi từ tiếng Việt thường.

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
  "stats_enabled": true, "app_rules": { "com.apple.Terminal": "dev" }, "voice_punctuation": true, "tone": "neutral",
  "whisper_mode": false, "learn_from_edits": true, "live_preview": false, "silence_stop_seconds": 0 }
```
(không bao giờ trả khoá). `PUT` nhận tập con các trường (kiểm kiểu/giá trị), ghi vào `~/.vflow/config.json`, có hiệu lực ngay không cần khởi động lại:
- `llm_timeout_ms`: số nguyên 1.000–30.000, **mặc định mới 3.500** (item 7 — 8.000 cũ quá lâu để chờ; người dùng đã tự đặt giá trị khác thì giữ nguyên, mặc định chỉ áp khi khoá vắng mặt trong tệp).
- `llm_model`: chuỗi ≤ 200 ký tự hoặc null.
- `app_rules` (item 4): object `{ "<bundleId>": "normal"|"clean"|"dev"|"tidy"|"email" }`, tối đa 100 mục, bundle id dạng reverse-DNS (`^[A-Za-z][A-Za-z0-9]*(\.[A-Za-z0-9][A-Za-z0-9_-]*)+$`). `auto` tra bảng này TRƯỚC luật cứng `auto.apps` (cấu hình). Luật trỏ `tidy`/`email` chỉ có hiệu lực khi `cloud_llm` bật (xem mục Chế độ).
- `voice_punctuation`, `whisper_mode`, `learn_from_edits`, `live_preview`: boolean.
- `tone`: `"neutral"|"formal"|"casual"`.
- `silence_stop_seconds`: số nguyên 0–60 (0 = tắt); `live_preview`/`silence_stop_seconds` chỉ lưu cho client (engine không tự dùng).
- `stats_enabled`: boolean (xem mục Thống kê).

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
Tối đa 50 dòng `recent_errors` gần nhất (chỉ `{at,route,status,code}` — KHÔNG văn bản dictation, KHÔNG token/khoá); đường dẫn dưới `$VFLOW_HOME`/thư mục home rút gọn thành `~`.

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
10. Với cấu hình mặc định, `mode=auto` KHÔNG BAO GIỜ gọi LLM (kiểm bằng máy chủ giả đếm 0 yêu cầu qua mọi `app` trong `auto.apps` mặc định). Chỉ chọn thủ công `tidy`/`email` hoặc tự sửa `app_rules`/`auto.apps` mới gửi chữ ra LLM; nếu `cloud_llm` đang tắt thì dù `app_rules`/`auto.apps` trỏ `tidy`/`email`, `auto` vẫn KHÔNG gọi LLM (rơi về `clean`).
11. Thống kê (`stats.json`) CHỈ là bộ đếm (words/audio_ms/count theo ngày/app) — không bao giờ chứa văn bản dictation hay âm thanh; tắt `stats_enabled` không xoá dữ liệu đã có; xoá/tắt `history_enabled` (client) không ảnh hưởng tới thống kê đã ghi.
12. `GET /v1/export` không bao giờ chứa token/khoá 9Router (`rewrite.key`); `POST /v1/import` cũng không bao giờ ÁP DỤNG token/khoá dù gói chứa chúng (tự lọc, báo `ignored`), và từ chối CẢ GÓI nếu bất kỳ phần nào sai (không nhập nửa vời — kiểm bằng cách cố ý làm hỏng một phần, phần còn lại hợp lệ, rồi xác nhận không có gì bị thay đổi).
13. `GET /v1/diagnostics` không bao giờ chứa token/khoá 9Router hay văn bản dictation, dù vừa có lỗi/dictation xảy ra ngay trước đó.
14. Dấu câu bằng giọng KHÔNG BAO GIỜ kích hoạt từ một từ đứng riêng ("chấm", "hỏi") — chỉ cụm ≥ 2 từ đã nêu; không chạy ở chế độ `dev`.
15. `voice_punctuation=false` ⇒ không cụm nào trong mục "Lệnh dấu câu bằng giọng" được thay, ở mọi chế độ.
16. `tone` (`formal`/`casual`) không được làm guard của `tidy` (bất biến 6) bỏ qua hay nới lỏng — đầu ra thêm nội dung vẫn bị `guard_rejected` dù `tone` nào.
17. `/v1/partial` không bao giờ ghi vào `history.jsonl`/`stats.json`, không tăng `uses` của mục từ điển nào, và chỉ xử lý tối đa 1 yêu cầu cùng lúc (yêu cầu thứ hai khi đang bận ⇒ `busy`).
18. STT cục bộ cho audio dài (> ngưỡng theo đoạn) không giữ RAM tăng vô hạn theo độ dài — đo bằng `/usr/bin/time -l` với audio tổng hợp 5 phút và 20 phút, RAM đỉnh phải không tăng tuyến tính so với không chia đoạn.
