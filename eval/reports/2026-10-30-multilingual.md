# M2 — đánh giá STT đa ngôn ngữ (30-10-2026, đo thật)

Tiếp nối báo cáo "dừng an toàn" cùng ngày (xem lịch sử git `84257de`): Mac vừa khởi động lại, RAM đủ, lần này đo được thật — không còn số `—`.

## Kết luận điều hành

1. **Model mặc định cho người nói Việt xen Anh:** **chưa có model nào đạt** cả hai tiêu chí "tiếng Việt tốt" và "code-switch tốt" cùng lúc. Trên bộ 36 câu tổng hợp (giọng `say` của macOS, KHÔNG đại diện giọng thật):
   - `zipformer-vi-30m` (hiện tại): WER sau post 40,75% toàn bộ, nhưng **không có khả năng tiếng Anh** — mọi câu tiếng Anh/Anh-xen-Việt bị phiên âm kiểu Việt vô nghĩa.
   - `whisper-tiny` multilingual (MIT): WER sau post 46,60% toàn bộ — **tệ hơn** zipformer ngay cả trên set trộn, vì ở cỡ tiny nó **tự nhận nhầm hẳn sang ngôn ngữ khác** (Thái, Bồ Đào Nha…) trên câu Việt ngắn/xen Anh, tạo ra văn bản bịa hoàn toàn (xem mục "Ví dụ thật").
   - `whisper-small` (MIT, 609,8 MB) khắc phục phần lớn lỗi nhận nhầm ngôn ngữ và đọc đúng nguyên văn nhiều thuật ngữ tiếng Anh xen trong câu Việt (ví dụ "anh review giúp em cái commit này." ra ĐÚNG 100%, điều zipformer không làm được), nhưng vẫn có câu thất bại hoàn toàn (lặp vô nghĩa, dịch nhầm) và RAM/độ trễ cao hơn hẳn (~1 GB RSS đỉnh, RTF trung vị 0,32 so với 0,01 của zipformer).
   - **Khuyến nghị:** CHƯA thay zipformer làm mặc định. Nếu muốn mở chế độ "Việt + English" ngay, dùng **whisper-small** làm lựa chọn song song (không mặc định), có cảnh báo rõ về độ trễ/RAM, và PHẢI đo lại bằng giọng thật của anh Nghĩa (bộ `eval/prompts/vi-en-40.txt`) trước khi cân nhắc đổi mặc định — số đo TTS ở đây có thể lệch xa so với giọng người thật, đặc biệt ở phần auto-detect ngôn ngữ (xem "Giới hạn").
2. **Giữ song song, không thay hẳn.** zipformer nhẹ (33 MB, RTF 0,01, RAM ~270 MB) và vẫn thắng về WER thô trên câu tiếng Việt thuần đơn giản ở cỡ nhỏ (xem bảng). Whisper cỡ đủ lớn (small) mới cạnh tranh được, với chi phí RAM/độ trễ/dung lượng tải gấp 3–30 lần.
3. **Tự nhận biết ngôn ngữ (auto) có đáng tin?** Phụ thuộc cỡ model:
   - `tiny`: **KHÔNG đáng tin** cho câu Việt ngắn/xen Anh — nhận lầm sang Thái/Bồ Đào Nha/Phần Lan (xem ví dụ thật). WER nhóm C (Việt-xen-Anh) ở auto là 105,2%, còn tệ hơn ép `vi` (103,4%).
   - `base`/`small`: auto khớp gần như y hệt ép `vi` trên câu Việt (vì tự nhận đúng), và đôi khi auto **tốt hơn** ép `vi`/`en` trên câu dài trộn ngôn ngữ (nhóm E, câu ~10 s): `small-auto` WER 25,2% so với `small-vi` 52,0% và `small-en` 70,7%. Ép sai ngôn ngữ trên âm thanh không khớp (vd ép `en` lên câu tiếng Việt) khiến Whisper **DỊCH NGHĨA** sang tiếng Anh thay vì phiên âm — một hiện tượng nguy hiểm hơn cả nhận nhầm, vì văn bản ra vẫn trôi chảy nhưng SAI HOÀN TOÀN NGHĨA (xem ví dụ thật, mục 2). ⇒ Nếu dùng Whisper ≥ base, **auto nên là mặc định**, không ép người dùng chọn trước.
   - **Phát hiện ở tầng engine hiện tại:** `engine/stt/local.js:92` LUÔN nạp Whisper với `language:''` (tự nhận biết) — tham số `lang=vi|en|auto` của API hiện chỉ kiểm năng lực model (`engine/stt/index.js:84-91`), **không hề** đổi hành vi giải mã. Vì vậy câu hỏi "ép vi/en có khác auto không" chỉ đo được bằng cách tạo recognizer riêng bên ngoài engine (như `run-whisper-eval.mjs` làm) — qua API thật hôm nay, mọi yêu cầu Whisper đều là auto-detect. Đây có thể là chủ ý (đơn giản hoá) hoặc thiếu sót; nêu rõ để coordinator xác nhận.
4. **Ảnh hưởng tới hậu xử lý hiện có:** đã kiểm thật bằng `bin/vflow.js compare` (engine thật, `mode=normal`, từ điển chỉ hạt giống) trên cùng 36 câu, so `zipformer-vi-30m` với `whisper-tiny-multilingual`:
   - Từ điển phiên-âm (fuzzy) sửa đúng 2/36 câu cho zipformer (`ri ác` → `React`, `cu bơ nét` → `Kubernetes`) nhưng **0/36** cho Whisper — lỗi của Whisper (nhận nhầm ngôn ngữ, lặp vô nghĩa) lệch quá xa dạng phiên âm mà từ điển được thiết kế để bắt (xem "Kiểm thực tế hậu xử lý").
   - Thử riêng câu có lệnh dấu câu bằng giọng ("...dấu phẩy...dấu hỏi chấm"): Whisper-tiny nghe sai cụm lệnh ("rấu, phy," thay vì "dấu phẩy") nên `punctuation.js` (so khớp từ đã gấp) KHÔNG nhận ra lệnh — tính năng "lệnh dấu câu bằng giọng" không chạy, không phải vì xung đột thiết kế mà vì ASR nghe sai từ. Cần đo lại với base/small và giọng thật trước khi kết luận.
   - Không phát sinh dấu câu kép hay viết hoa sai trong 36/36 câu (raw của Whisper vốn đã có dấu câu/viết hoa chuẩn, `normalizeText`/`capitalize` không đụng vào vì không có lỗi khoảng trắng để sửa) — nhưng bộ 36 câu KHÔNG có câu nào thử chế độ `dev`/devspeech, nên chưa kiểm được rủi ro đã nêu trong spec (biến có thể dính hoa/thường từ câu Whisper).
5. **Giấy phép cho thương mại:** **Whisper (OpenAI, MIT)** vẫn là lựa chọn rõ ràng nhất — xác nhận lại qua trang LICENSE của repo `openai/whisper`. **SenseVoice KHÔNG phải lựa chọn thương mại sạch như registry hiện ghi** — xem phát hiện quan trọng dưới đây.

## Phát hiện cần sửa ở `engine/stt/registry.js` (KHÔNG tự sửa, báo coordinator)

Khi tự kiểm giấy phép SenseVoice qua WebFetch (không tải model), phát hiện registry ghi sai:
- `engine/stt/registry.js:112` ghi `license: 'Apache-2.0 (FunASR SenseVoice)'`. Thực tế: mã nguồn repo `FunAudioLLM/SenseVoice` là **MIT** (xác nhận qua file `LICENSE` của repo và mục License trong README), nhưng **trọng số model** (SenseVoiceSmall) theo một giấy phép KHÁC: **"FunASR Model Open Source License Agreement" v1.1** (`modelscope/FunASR/MODEL_LICENSE`) — không phải Apache-2.0, không phải MIT.
- Nội dung giấy phép trọng số: cho phép dùng/sao chép/sửa/chia sẻ, buộc ghi nguồn và giữ tên model, nhưng có dòng miễn trách nhiệm "provided for reference and learning purposes only" và KHÔNG có điều khoản cấp phép thương mại rõ ràng (cũng không cấm rõ ràng) — mơ hồ, không nên gọi là "Apache-2.0" hay xem là sạch cho mục đích bán sau này.
- Ngôn ngữ hỗ trợ theo trang sherpa-onnx chính thức: `zh, yue, en, ja, ko` (+ `auto`) — **không có `vi`**, khớp với field `languages` hiện tại trong registry (đúng), nhưng field `license` cần sửa thành đại loại `"Mã nguồn MIT; TRỌNG SỐ theo FunASR Model Open Source License Agreement v1.1 (mơ hồ về thương mại, 'reference/learning only')"`.

## Lựa chọn khi mơ hồ

- **Không tải SenseVoice (1 GB) để tự băm checksum.** Lý do: (a) đã xác nhận KHÔNG hỗ trợ tiếng Việt qua tài liệu chính thức — không đổi được kết luận chính dù có checksum; (b) giấy phép trọng số mơ hồ về thương mại (xem trên) nên không phải "điểm cộng thương mại" như kỳ vọng ban đầu; (c) 1 GB tải + băm + nạp sẽ tốn đáng kể thời gian/RAM cho một model đã biết không phù hợp mục tiêu chính (Việt xen Anh). Nếu coordinator vẫn muốn checksum để mở khoá `models pull` cho mục đích khác (tiếng Trung/Nhật/Hàn/Quảng Đông), cần một lượt đo riêng.
- **Không đo `whisper-medium`/`large`.** Lý do: `small` (609,8 MB, RSS đỉnh ~1 GB) đã gần giới hạn hợp lý cho máy 16 GB chạy nền cả ngày; medium/large sẽ vượt xa ngân sách RAM cho một ứng dụng chạy thường trực, và pattern lỗi (nhận nhầm ngôn ngữ ở câu ngắn/xen) nhiều khả năng do bản chất kiến trúc Whisper trên audio ngắn chứ không chỉ do cỡ nhỏ — small đã đủ để thấy xu hướng.
- **Thêm 4 câu nhóm "e" (~10 s) vào `corpus.json`** (được phép theo phạm vi `eval/multilingual/**`) vì bộ gốc 32 câu không có câu nào ~10 s, mà nhiệm vụ yêu cầu đo cả hai mốc ~3 s và ~10 s. Giữ nguyên 32 câu gốc.
- **Sửa lỗi parse đối số trong `run-whisper-eval.mjs`** (`--language ''` bị hiểu là thiếu đối số vì `!''` là `true`): đã sửa để `''` (tự nhận biết) là giá trị hợp lệ, đồng thời chặn cứng giá trị `'auto'` với lỗi JS rõ ràng (xem "Kiểm chứng mã" — tạo lỗi thật, không còn im lặng kill tiến trình). Không lỗi này thì KHÔNG đo được chế độ auto qua script, vốn là một phần bắt buộc của nhiệm vụ.
- **Không dùng `node bin/vflow.js compare` để đo base/small**: CLI `compare` từ chối model lạ (`findModel(m)` phải có trong registry), mà `whisper-base`/`whisper-small` không có entry registry (ngoài phạm vi sửa của tôi). Nên base/small chỉ được đo trực tiếp qua `sherpa-onnx-node` (bỏ qua post-processing thật) — xem rõ trong bảng, các số base/small là "thô", không có dữ liệu "sau post"/từ điển cho hai cỡ này.

## An toàn RAM — trạng thái trước/sau mỗi model

Máy: MacBook Pro M1 Pro 16 GB, mới khởi động lại. `vm.swapusage` + `vm_stat (free/inactive)` đo NGAY TRƯỚC mỗi lần nạp model; không có lần nào vượt ngưỡng dừng (swap ≥ 8 GB hoặc free+inactive < 1 GB). Pane client (`swift test`) đang chạy lúc đầu — đã CHỜ đến khi hết `swift-frontend`/`swiftpm-testing-helper` trước khi nạp model đầu tiên.

| Trước khi nạp | swap used | free+inactive (ước tính) |
|---|---:|---:|
| Đầu phiên (sau reboot) | 0 MB | ~5,6 GB |
| Trước whisper-tiny × 3 chế độ | 0 MB | 3,1–5,7 GB |
| Trước whisper-base × 3 chế độ | 0–538,9 MB | 2,9–3,8 GB |
| Trước whisper-small × 3 chế độ | 538,9 MB (ổn định, không tăng) | 2,9–3,8 GB |
| Trước compare (zipformer+whisper-tiny cùng tiến trình) | 538,9 MB | ~2,9 GB |
| Cuối phiên | 514,9–538,9 MB | ~3,3 GB |

Swap tăng nhẹ lên ~539 MB khi bắt đầu base/small nhưng ỔN ĐỊNH (không tăng tiếp) suốt phần còn lại — không chạm ngưỡng dừng. Một tiến trình nhận dạng tại một thời điểm (mỗi lệnh `node eval/multilingual/run-whisper-eval.mjs` là một tiến trình riêng, thoát hẳn mới sang model kế; ngoại lệ duy nhất là lệnh `compare` nạp zipformer rồi whisper-tiny TRONG CÙNG một tiến trình Node theo đúng cách `bin/vflow.js compare` hoạt động — không có hai lượt giải mã chạy đồng thời).

## Bảng số đo đầy đủ — Whisper qua sherpa-onnx trực tiếp (KHÔNG qua post-processing/từ điển)

Nhóm câu: A = Việt thuần (8 câu, 3,3–4,2 s), B = Anh công việc (8 câu, 2,7–3,7 s), C = Việt xen Anh ngắn (8 câu, 2,1–3,2 s), D = thuật ngữ đọc kiểu Việt (8 câu, 1,9–2,9 s), E = câu dài trộn ngôn ngữ ~10–12,6 s (4 câu, MỚI thêm). WER/CER tính trên tham chiếu chữ thường bỏ dấu câu (nhạy dấu thanh), qua `eval/metrics.js`.

### whisper-tiny-multilingual (tải 116.204.861 byte = 110,8 MB; sha256 `c46116994e539aa165266d96b325252728429c12535eb9d8b6a2b10f129e66b1`, đã có trong registry)

| Chế độ | Nhóm | WER | CER | RTF trung vị/p95 | Độ trễ trung vị/p95 (ms) |
|---|---|---:|---:|---:|---:|
| `vi` (ép) | A | 31,7% | 20,2% | 0,056 / 0,061 | 203 / 246 |
| `vi` | B | 61,7% | 52,3% | 0,056 / 0,058 | 162 / 190 |
| `vi` | C | 103,4% | 66,1% | 0,058 / 0,064 | 153 / 193 |
| `vi` | D | 75,4% | 45,7% | 0,060 / 0,061 | 134 / 166 |
| `vi` | E (~10s) | 65,9% | 51,5% | 0,055 / 0,058 | 573 / 643 |
| `en` (ép) | A | 108,7% | 86,1% | 0,048 / 0,060 | 174 / 239 |
| `en` | B | 4,9% | 1,0% | 0,040 / 0,045 | 128 / 138 |
| `en` | C | 112,1% | 74,1% | 0,050 / 0,059 | 133 / 150 |
| `en` | D | 101,6% | 75,2% | 0,058 / 0,063 | 123 / 154 |
| `en` | E | 74,8% | 53,8% | 0,031 / 0,055 | 311 / 537 |
| tự nhận biết (`''`) | A | 31,7% | 20,2% | 0,058 / 0,061 | 209 / 247 |
| tự nhận biết | B | 4,9% | 1,0% | 0,041 / 0,048 | 134 / 146 |
| tự nhận biết | C | **105,2%** | 71,1% | 0,061 / 0,081 | 164 / 211 |
| tự nhận biết | D | 83,6% | 61,0% | 0,063 / 0,069 | 140 / 172 |
| tự nhận biết | E | 39,8% | 32,4% | 0,055 / 0,061 | 549 / 744 |

Tải model: 238–305 ms. RSS sau tải: 328–332 MB. RAM đỉnh thật (`/usr/bin/time -l`, `maximum resident set size`): **353,5 / 354,9 / 345,4 MB** (vi/en/auto).

### whisper-base (tải 207.557.382 byte = 197,9 MB; tải thủ công từ `k2-fsa/sherpa-onnx` — KHÔNG có trong registry, sha256 tự tính: `911b2083efd7c0dca2ac3b358b75222660dc09fb716d64fbfc417ba6c99ff3de`)

| Chế độ | Nhóm | WER | CER | RTF trung vị/p95 | Độ trễ trung vị/p95 (ms) |
|---|---|---:|---:|---:|---:|
| `vi` | A | 17,3% | 8,5% | 0,104 / 0,108 | 369 / 437 |
| `vi` | B | 103,7% | 76,5% | 0,103 / 0,109 | 314 / 346 |
| `vi` | C | 77,6% | 46,9% | 0,105 / 0,111 | 282 / 319 |
| `vi` | D | 60,7% | 41,0% | 0,115 / 0,132 | 251 / 319 |
| `vi` | E | 74,0% | 45,8% | 0,103 / 0,114 | 1056 / 1401 |
| `en` | A | 99,0% | 82,4% | 0,088 / 0,174 | 324 / 654 |
| `en` | B | 2,5% | 0,7% | 0,086 / 0,128 | 272 / 407 |
| `en` | C | 93,1% | 67,8% | 0,077 / 0,102 | 199 / 281 |
| `en` | D | 100,0% | 81,4% | 0,100 / 0,124 | 225 / 279 |
| `en` | E | 112,2% | 78,1% | 0,071 / 0,112 | 723 / 1380 |
| tự nhận biết | A | 17,3% | 8,5% | 0,107 / 0,108 | 384 / 434 |
| tự nhận biết | B | 2,5% | 0,7% | 0,079 / 0,091 | 258 / 277 |
| tự nhận biết | C | 75,9% | 47,7% | 0,115 / 0,120 | 303 / 363 |
| tự nhận biết | D | 65,6% | 48,1% | 0,117 / 0,122 | 260 / 317 |
| tự nhận biết | E | **35,8%** | 18,1% | 0,094 / 0,115 | 945 / 1411 |

Tải model: 353–639 ms. RSS sau tải: 492–532 MB. RAM đỉnh thật: **579,9 / 588,9 / 561,6 MB** (vi/en/auto).

### whisper-small (tải 639.387.718 byte = 609,8 MB; tải thủ công — sha256 tự tính: `486a46afbb7ba798507190ffe02fea2dd726049af212e774537efac6afb210a6`)

| Chế độ | Nhóm | WER | CER | RTF trung vị/p95 | Độ trễ trung vị/p95 (ms) |
|---|---|---:|---:|---:|---:|
| `vi` | A | **9,6%** | 5,4% | 0,326 / 0,333 | 1155 / 1355 |
| `vi` | B | 100,0% | 74,1% | 0,329 / 0,344 | 1047 / 1147 |
| `vi` | C | 53,4% | 29,3% | 0,322 / 0,380 | 839 / 991 |
| `vi` | D | 59,0% | 33,3% | 0,357 / 0,375 | 769 / 874 |
| `vi` | E | 52,0% | 40,8% | 0,319 / 0,345 | 3264 / 4226 |
| `en` | A | 101,9% | 96,3% | 0,234 / 0,275 | 848 / 1021 |
| `en` | B | 2,5% | 0,7% | 0,240 / 0,275 | 777 / 845 |
| `en` | C | 103,4% | 74,9% | 0,258 / 0,305 | 700 / 779 |
| `en` | D | 100,0% | 85,2% | 0,254 / 0,330 | 592 / 726 |
| `en` | E | 70,7% | 54,0% | 0,190 / 0,221 | 2108 / 2410 |
| tự nhận biết | A | 9,6% | 5,4% | 0,356 / 0,382 | 1268 / 1504 |
| tự nhận biết | B | 2,5% | 0,7% | 0,270 / 0,295 | 841 / 884 |
| tự nhận biết | C | **50,0%** | 28,9% | 0,316 / 0,398 | 868 / 1068 |
| tự nhận biết | D | 59,0% | 33,3% | 0,367 / 0,394 | 797 / 878 |
| tự nhận biết | E | **25,2%** | 13,7% | 0,307 / 0,344 | 3079 / 4228 |

Tải model: 862–904 ms. RSS sau tải: 448–852 MB. RAM đỉnh thật: **992,7 / 1011,4 / 1007,5 MB** (vi/en/auto).

### zipformer-vi-30m (mốc so sánh, đọc từ `~/.vflow/models/zipformer-vi-30m`, qua engine thật trong lệnh `compare` dưới)

| Model | WER thô/sau post (nhạy dấu) | CER thô/sau post | RTF trung vị/p95 | Độ trễ stt trung vị/p95 (ms) | Tải model (ms) |
|---|---:|---:|---:|---:|---:|
| `zipformer-vi-30m` | 39,81% / 40,75% | 24,80% / 25,20% | 0,010 / 0,014 | 32 / 80 | 784 |
| `whisper-tiny-multilingual` (qua engine, luôn auto) | 46,60% / 46,60% | 31,70% / 31,70% | 0,043 / 0,048 | 113 / 436 | 259 |

Nguồn: `node bin/vflow.js compare --set <36 câu> --models zipformer-vi-30m,whisper-tiny-multilingual --mode normal`, VFLOW_HOME tạm (zipformer COPY từ `~/.vflow/models/zipformer-vi-30m`, chỉ đọc nguồn). Thuật ngữ đúng (16 thuật ngữ IT trong `eval/prompts/terms.json`): zipformer 1/36 (2,78%) cả thô và sau post; whisper-tiny 6/36 (16,67%) cả thô và sau post — whisper bắt được nhiều thuật ngữ tiếng Anh hơn TRONG CÂU TIẾNG ANH THUẦN (nhóm B), nhưng KHÔNG cải thiện gì trên câu Việt-xen-Anh (nhóm C/D, nơi mục tiêu thực sự nằm) vì nó bị nhận nhầm ngôn ngữ ở đó. RAM đỉnh thật khi cả hai model cùng nằm trong một tiến trình (`compare` không giải phóng model trước khi nạp model sau): **688,4 MB** (maximum resident set size).

## Ví dụ văn bản THẬT (yêu cầu Acceptance #2)

Tất cả raw/hyp dưới đây là văn bản THÔ của model (chưa qua từ điển/post, trừ dòng ghi rõ "sau post"). Giọng tổng hợp `say` (Linh=vi_VN, Samantha=en_US).

**1 câu tiếng Anh thuần** — "Please send the final report before the meeting tomorrow morning." (b-01):
- zipformer: `clese and the final report perford the meding the more morning` (vô nghĩa — model chỉ học tiếng Việt)
- whisper-tiny (vi ép): `Hãy tên tên tên tên tên tên tên tên t` (lặp vô nghĩa khi ép SAI ngôn ngữ)
- whisper-tiny (en ép / auto): `Please send the final report before the meeting tomorrow morning.` (ĐÚNG 100%)
- whisper-base/small (mọi chế độ đúng ngôn ngữ): đúng 100%, có dấu câu/viết hoa chuẩn

**2 câu tiếng Việt xen Anh** —
- "mở cái pull request đó lên" (c-01):
  - zipformer: `mở cái tour ri quét đó lên` (giữ cấu trúc câu, phiên âm lệch "pull request")
  - whisper-tiny ép `vi`: `Mự kai to re-quad "Doll"` — whisper-tiny **tự nhận biết** (`''`): `มือ ขาย ทุกรี` (**tiếng Thái hoàn toàn**, không liên quan)
  - whisper-base/small (vi hoặc auto): `Mở cái 2Rquad đó lên` / `Mở cái "Tour Request" đó lên.` — giữ đúng cấu trúc Việt, nhận đúng ngôn ngữ, nhưng vẫn không ra đúng "pull request"
- "deploy lên staging sau khi test xong" (c-02):
  - zipformer: `a lên star sau khi tắt xong`
  - whisper-tiny auto: `que é que eu vou lembrei uns mais um salguito é` (**tiếng Bồ Đào Nha bịa**, nhận nhầm ngôn ngữ)
  - whisper-small ép `vi`: `Đó là một tên tên tên tên tên t` (lặp vô nghĩa — Whisper hallucinate trên câu ngắn mơ hồ, THẤT BẠI Ở MỌI CỠ)
  - whisper-small ép `en`/auto: `I think we will end this song.` (**dịch/bịa sang tiếng Anh, sai hoàn toàn nghĩa** — đây là câu khó nhất trong toàn bộ 36 câu, không model nào ra đúng)

**1 câu thuật ngữ IT (đọc kiểu Việt)** — "gít hấp đang báo lỗi xác thực" (= "GitHub đang báo lỗi xác thực", d-01):
- zipformer thô: `giúp hope đang báo lỗi xác thực` → **sau post: không đổi** (từ điển không khớp "giúp hope")
- whisper-tiny (vi/en ép): `gipe hợp đăng báo lỗi` / `Zephop Lang Bauloi Saku`; **tự nhận biết**: `ธอบรัง บ่า` (tiếng Thái)
- whisper-base (mọi chế độ): `R Hấp đăng vào lỗi sát`
- whisper-small (vi/auto): `dập hóp đang bảo lối xác` — **không có model nào** (kể cả zipformer có từ điển) phục hồi đúng "GitHub" cho câu này; so sánh với d-04/d-06 (dưới) nơi từ điển zipformer THÀNH CÔNG.

**Đối chứng thành công của từ điển (chỉ zipformer)** — "ri ác hiển thị trạng thái không đúng" (d-04, = "React…"): zipformer thô `ri ác hiển thị...` → **sau post: `React hiển thị...`** (từ điển khớp đúng). Cùng câu, whisper-tiny thô `Vy ác hiện thị trạng thái không đ` → **sau post: không đổi** (từ điển không khớp "Vy ác").

## Kiểm thực tế hậu xử lý (yêu cầu Khuyến nghị #4)

- **Dấu câu/viết hoa:** Whisper trả dấu câu + viết hoa chuẩn ngay từ raw; qua `mode=normal` (dictionary + `normalizeText`), KHÔNG có clip nào trong 36 câu bị dấu câu kép hoặc viết hoa sai — vì `normalizeText` (`engine/post/clean.js`) chỉ chỉnh khoảng trắng quanh dấu câu đã có, không tự thêm/xoá. Chưa kiểm được `mode=dev`/devspeech trên câu Whisper (bộ 36 câu không có câu ra lệnh code); đây là lỗ hổng cần đo thêm bằng giọng thật trước khi bật Whisper cho chế độ Lập trình.
- **Lệnh dấu câu bằng giọng:** thử rời (`xin chào dấu phẩy anh khỏe không dấu hỏi chấm`, whisper-tiny ép `vi`): model nghe sai cụm lệnh → `xin chào rấu, phy, anh khuay, không rấu` — không khớp bảng `RULES` trong `engine/post/punctuation.js` (so khớp từ đã gấp dấu, "rấu"/"phy" ≠ "dấu"/"phẩy") nên lệnh KHÔNG được thực thi. Đây là lỗi NGHE (ASR), không phải lỗi thiết kế xung khắc giữa Whisper và `punctuation.js`; nhưng hệ quả thực tế là tính năng im lặng không chạy. Cần thử lại với `base`/`small` và giọng thật — whisper cỡ lớn hơn nghe tiếng Việt tốt hơn nhiều (xem WER nhóm A giảm từ 31,7%→17,3%→9,6%) nên có thể đỡ hơn, nhưng CHƯA ĐO.
- **Từ điển phiên âm:** xem bảng "zipformer-vi-30m" trên — 2/36 câu được từ điển sửa đúng cho zipformer, 0/36 cho whisper-tiny. Nguyên nhân: từ điển `engine/post/dictionary.js` được tinh chỉnh từ lỗi phiên âm kiểu transducer (gần âm, như "ri ác"≈"react"); lỗi của Whisper ở các câu này là HALLUCINATION/nhận nhầm ngôn ngữ, không phải phiên âm gần — khác bản chất, từ điển hiện tại không bắt được. Nếu áp dụng Whisper rộng, từ điển có thể cần thêm biến thể "nghe-nhầm-điển-hình-của-Whisper" riêng, không chỉ tái dùng danh sách hiện có.

## Chưa đo được

- **Giọng người thật của anh Nghĩa.** Toàn bộ số đo trên là giọng TỔNG HỢP `say` (Linh/Samantha) — KHÔNG đại diện ngữ điệu, tốc độ nói, hay cách phát âm xen ngôn ngữ thật. Quyết định cuối BẮT BUỘC phải đọc `eval/prompts/vi-en-40.txt` (40 câu) thành bộ ghi âm thật rồi lặp lại đúng quy trình này.
- **Whisper base/small qua engine thật + từ điển/post-processing đầy đủ.** `registry.js` chỉ có entry cho `whisper-tiny-multilingual`; base/small không có trong danh mục nên `bin/vflow.js compare` từ chối — chỉ đo được "thô" qua gọi `sherpa-onnx-node` trực tiếp, không có số "sau post"/thuật ngữ cho hai cỡ này.
- **Lệnh dấu câu bằng giọng và chế độ Lập trình (`devspeech`) trên whisper-base/small và trên giọng thật** — chỉ thử nhanh 1 câu với tiny.
- **whisper-medium/large, SenseVoice (checksum + chạy thật), PhoWhisper remote (gpu-vps)** — ngoài phạm vi phiên này (xem "Lựa chọn khi mơ hồ").
- **Độ ổn định qua nhiều lượt lặp** (mỗi cấu hình chỉ chạy 1 lượt trên 36 câu, không lặp 5 lần như báo cáo `engine-api.md` từng làm cho hotwords) — số RTF/latency có thể dao động ±10-20% giữa các lượt chạy thật.

## Lệnh tái lập

```sh
TMPBASE=$(mktemp -d /tmp/vflow-multilingual.XXXXXX)
mkdir -p "$TMPBASE/home" "$TMPBASE/set" "$TMPBASE/models-dl"

# 1) Bộ WAV tổng hợp (36 câu, ngoài repo)
node eval/multilingual/make-synthetic-set.mjs --out "$TMPBASE/set"

# 2) whisper-tiny: qua vflow pull (có checksum trong registry)
VFLOW_HOME="$TMPBASE/home" node bin/vflow.js models pull whisper-tiny-multilingual
for L in vi en ''; do
  /usr/bin/time -l node eval/multilingual/run-whisper-eval.mjs \
    --set "$TMPBASE/set" --model-dir "$TMPBASE/home/models/whisper-tiny-multilingual" \
    --model tiny --language "$L" > "/tmp/tiny-${L:-auto}.json"
done

# 3) whisper-base/small: tải thủ công (KHÔNG có trong registry), tự băm
curl -L -o "$TMPBASE/models-dl/base.tar.bz2" \
  https://github.com/k2-fsa/sherpa-onnx/releases/download/asr-models/sherpa-onnx-whisper-base.tar.bz2
tar -xf "$TMPBASE/models-dl/base.tar.bz2" -C "$TMPBASE/models-dl"
for L in vi en ''; do
  /usr/bin/time -l node eval/multilingual/run-whisper-eval.mjs \
    --set "$TMPBASE/set" --model-dir "$TMPBASE/models-dl/sherpa-onnx-whisper-base" \
    --model base --language "$L" > "/tmp/base-${L:-auto}.json"
done
# (tương tự cho sherpa-onnx-whisper-small.tar.bz2, --model small)

# 4) zipformer vs whisper-tiny qua engine thật (copy zipformer CHỈ ĐỌC từ ~/.vflow)
cp -R ~/.vflow/models/zipformer-vi-30m "$TMPBASE/home/models/zipformer-vi-30m"
VFLOW_HOME="$TMPBASE/home" node bin/vflow.js compare \
  --set "$TMPBASE/set" --models zipformer-vi-30m,whisper-tiny-multilingual --mode normal

rm -rf "$TMPBASE"
```

## Kiểm chứng mã đã chạy

```
$ node --check eval/multilingual/run-whisper-eval.mjs
(không có lỗi)
$ node --check eval/multilingual/make-synthetic-set.mjs
(không có lỗi)
$ node --test eval/metrics.test.js
# tests 12
# pass 12
# fail 0

$ node eval/multilingual/run-whisper-eval.mjs --set /tmp --model-dir /tmp --model tiny --language auto
file:///<repo>/eval/multilingual/run-whisper-eval.mjs:20
  if (process.argv[i + 1] === 'auto') throw new Error(...)
Error: --language không được là "auto" (addon sherpa-onnx sẽ kill tiến trình Node); dùng chuỗi rỗng '' cho tự nhận biết.
Node.js v22.23.2
exit=1
```
(Trước khi sửa `arg()`, `--language ''` bị hiểu nhầm là "thiếu đối số" do `!''` === `true` trong JS — sửa xong mới đo được chế độ tự nhận biết, bắt buộc theo nhiệm vụ. Bằng chứng lỗi đã sửa thật: chạy `git diff` trên `eval/multilingual/run-whisper-eval.mjs` thấy hàm `arg()` nay có tham số `allowEmpty` và chặn cứng giá trị `'auto'` bằng lỗi JS rõ ràng thay vì để addon kill tiến trình.)

## Xác nhận dọn dẹp và an toàn dữ liệu (Acceptance #4)

- Hash nội dung `~/.vflow` (đường dẫn + kích thước + mtime mọi tệp, sắp xếp, SHA-256) TRƯỚC và SAU phiên làm việc: **`0a24cbf4ce5ed7004253adf067181635f30ad2054559de160c7168de3473db11`** — KHỚP HOÀN TOÀN, không file nào bị thêm/sửa/xoá.
- `~/.vflow/models/zipformer-vi-30m` chỉ được ĐỌC (dùng `cp -R` COPY NGUỒN sang thư mục tạm `VFLOW_HOME`, không ghi lại vào `~/.vflow`).
- Không `models pull` nào chạy với `VFLOW_HOME` trỏ vào `~/.vflow` thật; mọi model (whisper-tiny/base/small, 110,8 + 197,9 + 609,8 MB) nằm trong `/tmp/vflow-ml-eval/...` — đã `rm -rf` toàn bộ model, WAV tổng hợp, archive tải về sau khi đo xong (xác nhận `du -sh` còn lại chỉ 484 KB JSON kết quả, sau đó cũng xoá).
- Không cổng 7611 nào được dùng (các lệnh `compare`/`models pull`/`run-whisper-eval.mjs` không mở server HTTP).
- Không tiến trình mồ côi: `pgrep -fl "vflow.js serve"` sau phiên chỉ còn đúng 1 tiến trình — PID 873, là app `vflow.app` THẬT đang chạy sẵn của anh Nghĩa (không do tôi khởi động, không đụng tới).
- Không chụp màn hình, không dùng `osascript`/System Events, không mở `vflow.app` thật, không có cửa sổ GUI nào được tạo (toàn bộ việc đo là CLI/Node, không có client Swift nào bị chạy bởi tôi).
