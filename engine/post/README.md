# engine/post — hậu xử lý văn bản STT

```js
import { createPostProcessor, loadConfig, CommandError } from './engine/post/index.js';
const post = createPostProcessor({
  dictionaryPath: '~/.vflow/dictionary.json', config: loadConfig(path),
  snippets, // tuỳ chọn, từ settings/snippets module: { expand(text) -> {text, applied, matched} }
  settings, // tuỳ chọn: { get() -> {cloud_llm, llm_model, llm_timeout_ms, actions_enabled} }, gọi lại mỗi yêu cầu
});
await post.process({ textRaw, mode: 'normal'|'clean'|'email'|'tidy'|'dev'|'auto', app: 'com.apple.mail' });
// -> { text, mode (chế độ đã áp, auto đã phân giải), applied: [{type, from, to}], rewrite: {used, error}, actions: string[] }
await post.command({ instruction, selection, context, app }); // -> { text, kind: 'edit'|'draft', timings_ms: { llm } }
// lỗi: ném CommandError (.code ∈ 'rewrite_unavailable'|'cloud_disabled'|'timeout'|'bad_request', .message tiếng Việt)
post.dictionary.list(); post.dictionary.replaceAll(entries); post.dictionary.learnCorrection({ before, after });
```

Tuỳ chọn thêm (ngoài chữ ký hợp đồng): `seedPath` (mặc định `config/dictionary.seed.json`), `log(event)` (mặc định: một dòng JSON lên stderr, chỉ có tên sự kiện và mã lỗi — không văn bản, không khoá). `snippets`/`settings` vắng mặt ⇒ dùng mặc định (`cloud_llm:true`, `llm_model` từ `config.rewrite.model`, `actions_enabled:true`, không snippet).

## Thứ tự xử lý trong `process`
1. **Snippets** (nếu có `snippets.expand` và khớp) ⇒ trả nguyên văn `text` của snippet, bỏ qua mọi bước sau, `applied` chỉ có `{type:'snippet',...}`.
2. **Hành động cuối câu** (`actions.js`): cụm "nhấn/bấm enter" đúng ở cuối ⇒ cắt khỏi text, `actions:["enter"]` (tắt bằng `settings.actions_enabled=false`).
3. **Từ điển** (`dictionary.js`).
4. Theo chế độ (xem dưới).

## Chế độ
- `normal`: chỉ từ điển.
- `clean`: từ điển → bỏ từ đệm (theo `fillers.json`, `clean.js`) → gộp khoảng trắng, bỏ khoảng trắng trước dấu câu, gộp dấu phẩy lặp; viết hoa đầu câu **chỉ khi** STT đã có dấu kết câu. Không bao giờ thêm dấu câu, không chèn khoảng trắng sau dấu chấm (để không phá `next.js`, `3,5`, tên miền).
- `dev`: `clean` rồi áp `devspeech.js` (quy tắc đọc kiểu lập trình: "gạch dưới"→`_`, "camel case a b c"→`aBC`, "src gạch chéo app chấm ts"→`src/app.ts`...). Thuần quy tắc, không gọi mạng. **Không** hiểu backtrack (đó là việc của LLM ở `tidy`).
- `tidy` ("Gọn"): `devspeech.js` rồi `clean.js` (văn bản dự phòng), sau đó `tidy.js` gọi LLM làm gọn (dấu câu, viết hoa, bỏ từ đệm, backtrack, danh sách) qua `llm.js`, có GUARD (`checkGuard`) chặn thêm nội dung lạ. Lỗi LLM/guard ⇒ dùng văn bản dự phòng, `rewrite={used:false,error:<mã>}` (thêm mã `guard_rejected`, `cloud_disabled` so với `email`).
- `email`: từ điển → `llm.js` (`rewrite.js`) viết lại thành thư. Lỗi ⇒ `text` = văn bản đã qua từ điển (chưa clean), `rewrite = {used:false, error}` với mã `timeout`, `http_<status>`, `empty`, `bad_response`, `network`, `no_key`, `no_model`, `cloud_disabled`. Phản hồi dài hơn max(4000, 8 × đầu vào) ký tự bị coi là `bad_response`; khối `<think>…</think>` bị bỏ.
- `auto`: tra `auto.apps[app]` trong cấu hình (bảng mặc định ở `config.js`: ứng dụng thư→`email`, Terminal/iTerm2/Warp/VS Code/Cursor/Ghostty→`dev`, ứng dụng nhắn tin→`tidy`; ghi đè được); không có ⇒ `normal`.

## LLM dùng chung (`llm.js`)
Client cho `email`/`tidy`/`command`: `POST {rewrite.url}/chat/completions`, luôn `stream:false`, đọc được CẢ JSON thường LẪN SSE (`data: {...}` ghép `delta.content`, bỏ `[DONE]`). `settings.cloud_llm=false` ⇒ `cloud_disabled`, không gọi mạng. Model = `settings.llm_model` ?? `config.rewrite.model` (`null` ⇒ `no_model`). Khoá từ `rewrite.key_file` (thiếu/rỗng/nhiều dòng ⇒ `no_key`), không bao giờ vào log/lỗi/kết quả.

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
