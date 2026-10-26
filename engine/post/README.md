# engine/post — hậu xử lý văn bản STT

```js
import { createPostProcessor, loadConfig, CommandError } from './engine/post/index.js';
const post = createPostProcessor({
  dictionaryPath: '~/.vflow/dictionary.json', config: loadConfig(path),
  snippets, // tuỳ chọn, từ settings/snippets module: { expand(text) -> {text, applied, matched} }
  settings, // tuỳ chọn: { get() -> {cloud_llm, llm_model, llm_timeout_ms, actions_enabled, app_rules,
            //   voice_punctuation, tone, whisper_mode, learn_from_edits, …} }, gọi lại mỗi yêu cầu
  corrections, // tuỳ chọn, từ learn.js: createCorrectionsStore(...) — xem mục "Gợi ý từ điển" dưới
});
await post.process({ textRaw, mode: 'normal'|'clean'|'email'|'tidy'|'dev'|'auto', app: 'com.apple.mail' });
// -> { text, mode (chế độ đã áp, auto đã phân giải), applied: [{type, from, to}], rewrite: {used, error},
//      actions: string[], degraded: boolean, degraded_reason: 'cloud_disabled'|'llm_timeout'|'llm_error'|'guard'|null }
await post.command({ instruction, selection, context, app }); // -> { text, kind: 'edit'|'draft', timings_ms: { llm } }
// lỗi: ném CommandError (.code ∈ 'rewrite_unavailable'|'cloud_disabled'|'timeout'|'bad_request', .message tiếng Việt)
post.dictionary.list(); post.dictionary.replaceAll(entries); post.dictionary.learnCorrection({ before, after });
post.dictionary.suggestions(); post.dictionary.dismissSuggestion(term); post.dictionary.applyPreview(text); // item 8/9
```

Tuỳ chọn thêm (ngoài chữ ký hợp đồng): `seedPath` (mặc định `config/dictionary.seed.json`), `log(event)` (mặc định: một dòng JSON lên stderr, chỉ có tên sự kiện và mã lỗi — không văn bản, không khoá). `snippets`/`settings`/`corrections` vắng mặt ⇒ dùng mặc định (`cloud_llm:true`, `llm_model` từ `config.rewrite.model`, `actions_enabled:true`, không snippet, `suggestions()` luôn rỗng).

## Thứ tự xử lý trong `process`
1. **Snippets** (nếu có `snippets.expand` và khớp) ⇒ trả nguyên văn `text` của snippet, bỏ qua mọi bước sau, `applied` chỉ có `{type:'snippet',...}`.
2. **Hành động cuối câu** (`actions.js`): cụm "nhấn/bấm enter" đúng ở cuối ⇒ cắt khỏi text, `actions:["enter"]` (tắt bằng `settings.actions_enabled=false`).
3. **Từ điển** (`dictionary.js`).
4. **Dấu câu bằng giọng** (`punctuation.js`, item 5): mọi chế độ TRỪ `dev`, trừ khi `settings.voice_punctuation=false`. "dấu chấm"→`.`, "dấu phẩy"→`,`, "xuống dòng"→`\n`, "đoạn mới"→`\n\n`, "mở/đóng ngoặc (kép)"→`(`/`)`/`“`/`”`, "chấm/dấu hỏi chấm"→`?`, "chấm/dấu chấm than"→`!`, "dấu hai chấm"→`:`, "dấu chấm phẩy"→`;`, "ba chấm"→`…`, "gạch ngang"→`–`. Từ khoá luôn ≥ 2 từ để không nhầm lời nói thường ("chấm điểm", "câu hỏi" giữ nguyên). Ở `tidy`, chạy SAU `devspeech.js` (xem mục Chế độ) — biết hạn chế: "dấu hai chấm" trong `tidy` có thể bị quy tắc `devspeech` "hai chấm" bắt mất phần "hai chấm", để lại "dấu" lẻ.
5. Theo chế độ (xem dưới).

## Chế độ
- `normal`: từ điển → dấu câu bằng giọng.
- `clean`: từ điển → dấu câu bằng giọng → bỏ từ đệm (theo `fillers.json`, `clean.js`) → gộp khoảng trắng, bỏ khoảng trắng trước dấu câu, gộp dấu phẩy lặp; viết hoa đầu câu khi có dấu kết câu (STT hoặc dấu câu bằng giọng vừa chèn). Không tự thêm dấu câu ngoài các lệnh giọng đã nói.
- `dev`: `clean` rồi áp `devspeech.js` (quy tắc đọc kiểu lập trình: "gạch dưới"→`_`, "camel case a b c"→`aBC`, "src gạch chéo app chấm ts"→`src/app.ts`...). Thuần quy tắc, không gọi mạng, **KHÔNG** chạy dấu câu bằng giọng (loại trừ rõ trong contract). **Không** hiểu backtrack (đó là việc của LLM ở `tidy`).
- `tidy` ("Gọn"): `devspeech.js` → dấu câu bằng giọng → `clean.js` (văn bản dự phòng), sau đó `tidy.js` gọi LLM làm gọn (dấu câu, viết hoa, bỏ từ đệm, backtrack, danh sách, theo `settings.tone`) qua `llm.js`, có GUARD (`checkGuard`) chặn thêm nội dung lạ (độc lập với tone). Lỗi LLM/guard ⇒ dùng văn bản dự phòng, `rewrite={used:false,error:<mã>}`, `degraded:true` (`degraded_reason`: `llm_timeout`|`guard`|`llm_error`).
- `email`: từ điển → dấu câu bằng giọng → `llm.js` (`rewrite.js`, theo `settings.tone`) viết lại thành thư. Lỗi ⇒ `text` = văn bản đã qua từ điển + dấu câu bằng giọng (chưa qua LLM), `rewrite={used:false,error}`, `degraded:true` với mã tương tự `tidy`. Phản hồi dài hơn max(4000, 8 × đầu vào) ký tự bị coi là `bad_response`; khối `<think>…</think>` bị bỏ.
- `auto`: tra `settings.app_rules[app]` (item 4) TRƯỚC, rồi `auto.apps[app]` trong cấu hình cứng (bảng mặc định ở `config.js` CHỈ chọn chế độ trong máy — bất biến 10); không có ⇒ `normal`. Luật trỏ sang `tidy`/`email` mà `settings.cloud_llm=false` ⇒ rơi về `clean` NGAY (không thử gọi LLM), `degraded:true, degraded_reason:"cloud_disabled"`.

## Giọng điệu & nói nhỏ (item 6)
`settings.tone` (`neutral`|`formal`|`casual`, mặc định `neutral`) chỉ thêm MỘT dòng hướng dẫn phong cách vào system prompt của `tidy`/`email` (`llm.js#toneInstruction`) — không đổi guard, không đổi nghĩa. `settings.whisper_mode` (mặc định `false`) khuếch đại PCM TRƯỚC STT (`engine/stt/gain.js#applyAutoGain`, chuẩn hoá đỉnh về −3 dBFS, trần +24 dB, cổng nhiễu mềm) — áp ở `engine/server/index.js`, không phải ở đây.

## Gợi ý từ điển (item 8, `learn.js`)
`suggestCorrections(before, after, entries)`: so diff mức từ (LCS), chỉ gợi ý ngay (không ghi gì) — dùng cho `POST /v1/corrections`. `createCorrectionsStore({path, now, log})`: lưu bền các cặp ngắn (≤ 5 từ) vào `corrections.json` (0600, tối đa 500 mục gần nhất) mỗi khi `learnCorrection` được gọi và `settings.learn_from_edits!==false`; `.suggestions(dictionaryEntries)` gộp theo (term, spoken), chỉ trả cặp xuất hiện ≥ 2 lần và chưa có trong từ điển/chưa bị `.dismiss(term)`.

## Command Mode (`command.js`, `post.command`)
Có `selection` ⇒ `kind:'edit'` (chỉ trả đoạn thay thế). Không có ⇒ `kind:'draft'`. Giới hạn 20.000 ký tự mỗi trường (`instruction`/`selection`/`context`). Lỗi ném `CommandError`, KHÔNG BAO GIỜ trả văn bản giả.

## LLM dùng chung (`llm.js`)
Client cho `email`/`tidy`/`command`: `POST {rewrite.url}/chat/completions`, luôn `stream:false`, đọc được CẢ JSON thường LẪN SSE (`data: {...}` ghép `delta.content`, bỏ `[DONE]`). `settings.cloud_llm=false` ⇒ `cloud_disabled`, không gọi mạng. Model = `settings.llm_model` ?? `config.rewrite.model` (`null` ⇒ `no_model`). Khoá từ `rewrite.key_file` (thiếu/rỗng/nhiều dòng ⇒ `no_key`), không bao giờ vào log/lỗi/kết quả. `llm_timeout_ms` mặc định **3500 ms** (item 7 — trước là 8000, quá lâu để chờ); quá giờ/lỗi/guard từ chối không bao giờ làm dictation thất bại, luôn có bản dự phòng cục bộ (xem `degraded`/`degraded_reason` ở trên).

## Thống kê (`stats.js`, item 1)
`createStatsStore({path, historyPath, now, log})`: `$VFLOW_HOME/stats.json` (0600) CHỈ bộ đếm theo ngày (`words,audio_ms,count,apps`) — không văn bản/âm thanh. Lần đầu chạy backfill từ `history.jsonl` của client (định dạng `client/Sources/VFlowCore/History.swift`: bỏ `mode` bắt đầu bằng `command`, bỏ dòng hỏng — đếm, không crash). `.record()` gọi ở engine/server mỗi dictation thành công (không rỗng, không Command Mode) khi `settings.stats_enabled!==false`. `.summary({weeks})` tính `since/avg_wpm/current_streak/best_streak/days[]/top_apps` — `total_*`/`avg_wpm`/`streak`/`top_apps` là TOÀN THỜI GIAN, `days[]` là cửa sổ biểu đồ `weeks` tuần (xem contract). `.clear()` xoá hết, đặt `backfilled:true` để không tự backfill lại.

## Xuất/nhập (`exportimport.js`, item 2) & Chẩn đoán (`diagnostics.js`, item 3)
`validateImportPackage(pkg)` kiểm NGHIÊM toàn bộ (format/version, dictionary/snippets qua validator sẵn có, settings lọc khoá bí mật, `stats.days`, `history`) — ném `ImportError` ngay khi gặp lỗi đầu tiên, KHÔNG áp dụng gì nếu có lỗi. `mergeDictionary`/`mergeSnippets`/`mergeHistory` merge theo khoá duy nhất, KHÔNG tạo trùng (giữ bản hiện có khi đụng). `buildDiagnostics(...)` chỉ nhận dữ liệu ĐÃ an toàn (settings.get() không có khoá theo schema cố định, `recent_errors` chỉ `{at,route,status,code}`); `redactPaths` rút gọn đường dẫn dưới home thành `~`.

## Command Mode (`command.js`, `post.command`)
Có `selection` ⇒ `kind:'edit'` (chỉ trả đoạn thay thế). Không có ⇒ `kind:'draft'`. Giới hạn 20.000 ký tự mỗi trường (`instruction`/`selection`/`context`). Lỗi ném `CommandError`, KHÔNG BAO GIỜ trả văn bản giả.

## Từ điển
- Mục: `{ term, spoken: [..], kind: 'term'|'replace', case?: 'exact', uses, last_used }`. `case: 'exact'` giữ nguyên hoa/thường (npm, n8n, macOS) kể cả đầu câu.
- Khớp theo từ, không phân biệt hoa/thường và **dấu thanh** (huyền/sắc/hỏi/ngã/nặng); **giữ** dấu mũ/trăng/móc và đ (`plôi` ≠ `plơi`). Các từ của một biến thể chỉ được cách nhau bởi khoảng trắng/gạch nối; không thay khi cụm dính vào định danh/URL (`x_pút`, `api.pút`, `pút.js`). Cụm dài nhất thắng; cùng độ dài thì mục đứng trước thắng.
- Mỗi lần thay tăng `uses`, đặt `last_used` và ghi tệp nguyên tử (tệp tạm + rename), quyền 0600. **Windows**: Node không áp quyền POSIX, nên bỏ qua chmod; `replaceAll` trả `permissions: "not_applied_windows"` thay vì `"0600"`.
- Chưa có tệp ⇒ dùng hạt giống (không ghi gì cho tới lần thay đổi đầu). Tệp hỏng ⇒ ném lỗi, không âm thầm quay về hạt giống.
- `replaceAll` kiểm schema (khoá lạ, trùng `term`, quá 5000 mục, `spoken` 1–20 chuỗi ≤ 100 ký tự…) và không đổi gì nếu sai.
- `learnCorrection` so diff mức từ (LCS) và chỉ gợi ý; lọc: giống nhau, chỉ đổi dấu câu/hoa thường/dấu thanh, chỉ thêm/xoá, sửa số, cụm > 4 từ (trước) hoặc > 3 từ (sau), > 3 chỗ sửa hoặc sửa quá nửa câu, biến thể đã có.

## Hạt giống `config/dictionary.seed.json`
149 thuật ngữ phát triển phần mềm/AI/hạ tầng. **Các biến thể phát âm (`spoken`) là GIẢ ĐỊNH** viết theo cách người Việt hay đọc, **chưa kiểm bằng giọng thật hay đầu ra STT thật** (zipformer/PhoWhisper có thể viết khác, ví dụ dính liền, khác dấu, hoặc ra chữ Latin). Cần đối chiếu với kết quả đo M2 rồi sửa. Rủi ro đã biết: vì khớp bỏ dấu thanh, biến thể một âm tiết có thể trùng từ tiếng Việt (ví dụ `búc` ↔ "bục"); test chặn các âm tiết thông dụng, nhưng danh sách chặn không đầy đủ.

## Từ đệm `fillers.json`
`always` (ừm, hmm, uh, um… và mẫu kéo dài) bỏ ở mọi vị trí. `contextual` (à, ừ, ờ, ơ, ê) chỉ bỏ ở vị trí cho phép (đầu/giữa câu), không bao giờ ở cuối câu hay đứng một mình, và giữ khi gặp ngữ cảnh có nghĩa (`à ra thế`, `à quên`, `rồi à`, `ừ thì`, `ơ kìa`, `ê này`, `chữ ê`…). Khi STT không có dấu câu, cả đoạn được coi là một câu nên tiểu từ giữa đoạn (ví dụ "đi rồi à em…") chỉ được giữ nhờ danh sách ngữ cảnh — có thể sót.

## Demo
`node engine/post/demo.js` — một đoạn thô đi qua 4 chế độ; chế độ email dùng **máy chủ giả** dựng trong demo (không gọi 9Router thật), từ điển ở thư mục tạm và bị xoá sau khi chạy.
