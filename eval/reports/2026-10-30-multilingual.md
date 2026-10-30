# M1 — đánh giá STT đa ngôn ngữ (30-10-2026)

## Kết luận điều hành

Chưa có đủ số đo mới để chọn model mặc định một cách trung thực. Không thay zipformer-vi-30m: giữ nó cho tiếng Việt thuần, và chỉ bổ sung Whisper đa ngôn ngữ thành lựa chọn song song sau khi đo được bộ 40 câu bằng chính giọng anh Nghĩa. Ứng viên thương mại khả thi nhất về giấy phép là OpenAI Whisper (tiny/base/small đều MIT); tuy vậy chưa được phép suy diễn rằng nó tốt hơn Zipformer cho tiếng Việt xen Anh từ giọng TTS.

## Trạng thái và chốt an toàn

Máy đo: Mac M1 Pro 16 GB, darwin-arm64, Node đã cài sherpa-onnx-node 2.0.0. HP win-tailscale timeout SSH, nên không dùng làm nơi đo.

Coordinator cho phép chỉ thử Whisper tiny rồi base nếu an toàn: trước mỗi lần phải không có swift-frontend, swap trống tối thiểu 2 GB và tổng trang free + inactive tối thiểu 1 GB; swap dưới 1 GB thì dừng hẳn. Lúc kiểm cuối, lệnh dưới cho kết quả thật:

text
sysctl -n vm.swapusage
total = 17408.00M  used = 16432.12M  free = 975.88M  (encrypted)

vm_stat | awk '/Pages free|Pages inactive/ {print}'
Pages free: 5364.
Pages inactive: 186462.


Đồng thời pane khác đang chạy swift-frontend cho test client. Vì swap free dưới 1 GB, không tải/nạp/giải mã bất kỳ model nào, không tạo WAV tạm hay model tạm; đây là **dừng an toàn có chủ đích**, không phải kết quả hiệu năng.

## API thực tế của sherpa-onnx-node 2.0.0

Đã đọc node_modules/sherpa-onnx-node/types.js và non-streaming-asr.js tại checkout. Gói 2.0.0 có OfflineRecognizer.createAsync(config), với modelConfig.whisper { encoder, decoder, language, task, tailPaddings }, modelConfig.senseVoice { model, language, useInverseTextNormalization }, và modelConfig.moonshine; không có factory Node tên OfflineRecognizer.from_whisper trong mã cài đặt này. Vì vậy tích hợp tương lai phải dùng recognizer cấu hình tổng quát, không dựa vào tên API Python.

| Ứng viên | Sherpa 2.0.0 có config | Hỗ trợ tiếng Việt đã xác minh | Giấy phép/upstream | Kết luận |
|---|---|---|---|---|
| zipformer-vi-30m | transducer | Có, thuần Việt | CC-BY-NC-ND-4.0 theo manifest/model gốc | Mốc tiếng Việt; không thương mại |
| Whisper tiny/base/small/medium đa ngôn ngữ | whisper | Có: Whisper đa ngôn ngữ (99 ngôn ngữ trên model card) | MIT, gồm code và trọng số | Ứng viên thương mại chính |
| SenseVoice-small | senseVoice | **Không**: tài liệu sherpa chỉ liệt kê zh/en/ja/ko/yue | Trang sherpa ghi nguồn SenseVoice; giấy phép phải rà lại đúng artifact nếu cân nhắc | Loại khỏi bài toán Việt/Anh |
| Moonshine | moonshine | Không có bằng chứng model sherpa-onnx 2.0.0 hỗ trợ tiếng Việt | Chưa phù hợp để tải/đo | Loại |

Nguồn: [Whisper model card](https://huggingface.co/openai/whisper-tiny), [giấy phép Whisper MIT](https://github.com/openai/whisper/blob/main/LICENSE), [tài liệu Whisper của sherpa](https://k2-fsa.github.io/sherpa/onnx/pretrained_models/whisper/tiny.en.html), [SenseVoice của sherpa](https://k2-fsa.github.io/sherpa/onnx/sense-voice/index.html), [model SenseVoice dựng sẵn](https://k2-fsa.github.io/sherpa/onnx/sense-voice/pretrained.html).

## Bộ thử đã dựng (chưa sinh audio)

Đã thêm nguồn tái lập trong eval/multilingual/:

- corpus.json: 32 câu chuẩn, 4 nhóm, mỗi nhóm 8 câu: A tiếng Việt thuần, B tiếng Anh công việc, C Việt xen Anh (gồm năm câu yêu cầu), D tên riêng/thuật ngữ đọc kiểu Việt.
- make-synthetic-set.mjs: dùng say giọng Linh (vi_VN) cho A/C/D và Samantha (en_US) cho B, rồi afconvert thành WAV PCM 16-bit mono 16 kHz. Nó từ chối ghi audio vào repo.
- run-whisper-eval.mjs: dùng API Node thực tế, tính WER/CER qua eval/metrics.js, thời gian tải, RSS mẫu, latency và RTF theo từng nhóm.

Lệnh tái lập, chỉ chạy khi chốt RAM đã đạt:

sh
TEMP_DIR=$(mktemp -d /tmp/vflow-multilingual.XXXXXX)
node eval/multilingual/make-synthetic-set.mjs --out "$TEMP_DIR/set"
curl -L -o "$TEMP_DIR/tiny.tar.bz2" https://github.com/k2-fsa/sherpa-onnx/releases/download/asr-models/sherpa-onnx-whisper-tiny.tar.bz2
tar -xf "$TEMP_DIR/tiny.tar.bz2" -C "$TEMP_DIR"
/usr/bin/time -l node eval/multilingual/run-whisper-eval.mjs --set "$TEMP_DIR/set" --model-dir "$TEMP_DIR/sherpa-onnx-whisper-tiny" --model tiny --language auto
rm -rf "$TEMP_DIR"


Lưu ý: TTS chỉ kiểm đường ống/model trên phát âm tổng hợp, **không thay thế** giọng thật, ngữ điệu hay cách nói xen Anh của anh Nghĩa. Quyết định cuối cần anh đọc đầy đủ eval/prompts/vi-en-40.txt thành bộ ~/.vflow/eval/nghia-1, rồi chạy WER/CER và latency cùng quy trình.

## Bảng số đo

Ký hiệu — là chưa đo, không phải 0 hay thành công.

| Model × nhóm | WER | CER | RTF | latency trung vị / p95 | RAM đỉnh | tải về | nạp model | Trạng thái |
|---|---:|---:|---:|---:|---:|---:|---:|---|
| Zipformer × A | — | — | — | — | — | 26,4 MB (số cũ) | — | Model hiện có nhưng không chạy lại do chốt RAM |
| Zipformer × B/C/D | — | — | — | — | — | 26,4 MB (số cũ) | — | Không có năng lực Anh được kỳ vọng |
| Whisper tiny × A/B/C/D, language=auto | — | — | — | — | — | — | — | Chưa tải: dừng an toàn |
| Whisper tiny × A/B/C/D, vi | — | — | — | — | — | — | — | Chưa tải: dừng an toàn |
| Whisper tiny × A/B/C/D, en | — | — | — | — | — | — | — | Chưa tải: dừng an toàn |
| Whisper base × A/B/C/D, auto/vi/en | — | — | — | — | — | — | — | Không được sang base |
| Whisper small × A/B/C/D, auto/vi/en | — | — | — | — | — | — | — | Không được phép thử ở áp lực RAM này |
| Whisper medium × A/B/C/D | — | — | — | — | — | — | — | Không thử; rủi ro RAM cao |
| SenseVoice-small × A/B/C/D | — | — | — | — | — | — | — | Không tải vì không hỗ trợ tiếng Việt |

Mốc cũ duy nhất có thể kiểm chứng trong repo là eval/reports/2026-10-26-m1a.md: Zipformer trên M1 Pro, một WAV 3,74 s: tải 933 ms, nhận dạng 45 ms (RTF 0,012), maximum resident set size 269,5 MB. Đây không có transcript tham chiếu nên không có WER/CER và không được dùng để suy ra chất lượng đa ngôn ngữ.

## Phân tích và khuyến nghị

1. **Mặc định cho người Việt xen Anh:** chưa thể chọn dựa trên số đo. Ứng viên cần đo trước là **Whisper small multilingual**, vì là model duy nhất trong danh sách có tiếng Việt lẫn tiếng Anh và MIT; tiny/base là cỡ rẻ hơn để xác định đường cong RAM/latency. Không có số WER/CER thật thì không tuyên bố small thắng Zipformer.
2. **Kiến trúc:** giữ Zipformer cho người dùng chọn “Tiếng Việt nhanh”, thêm Whisper “Việt + English” song song; không thay hẳn. Zipformer là 30M/nhẹ và mốc cũ RTF 0,012; Whisper thay đổi đặc tính chữ đầu ra, model lớn hơn và có rủi ro latency/RAM cần số đo.
3. **Ngôn ngữ:** Whisper có thể để ngôn ngữ không ép (auto) hoặc ép token ngôn ngữ vi/en; model card mô tả hai chế độ forced/unforced. Chưa đo được auto so với ép vi/en, nên không chọn chính sách mặc định. Khi an toàn, chạy cùng audio ba lần --language auto, vi, en cho tiny rồi base/small và so WER/CER C/D.
4. **Hậu xử lý hiện hữu:** đây là thay đổi lớn. Zipformer hiện được chuẩn hoá chữ thường không dấu câu; Whisper thường trả viết hoa/dấu câu, nên các luật từ điển đọc-phiên-âm, lệnh dấu câu bằng giọng, ký hiệu theo ngữ cảnh và dev phải được đo lại trên text_raw, không chỉ đo WER. Nếu chạy nguyên luật hiện tại, có thể sinh dấu câu kép hoặc không khớp pattern vốn giả định chữ thường; cần thiết kế chuẩn hoá trung gian riêng theo provider, không được âm thầm lower-case phá tên riêng/English. Từ điển vẫn hữu ích cho “gít hấp”→GitHub và thuật ngữ do Whisper nghe sai; chế độ Lập trình phải bảo toàn token code/viết hoa có chủ ý.
5. **Thương mại:** Whisper là mở đường rõ nhất: upstream nói trọng số và code MIT, giấy phép cho phép dùng/sửa/phân phối/bán với điều kiện giữ notice. Zipformer là CC-BY-NC-ND-4.0 nên không là nền tảng thương mại. Không kết luận SenseVoice thương mại cho vflow vì trước hết nó không có tiếng Việt trong artifact sherpa được nêu.

## Kiểm chứng mã đã chạy

text
$ node --check eval/multilingual/run-whisper-eval.mjs
$ node --check eval/multilingual/make-synthetic-set.mjs
$ node --test eval/metrics.test.js
# tests 12
# pass 12
# fail 0
# cancelled 0


## Chưa đo được

- Tất cả metric yêu cầu M1 mới: WER, CER, RTF, median/p95 3 s/10 s, /usr/bin/time -l peak RAM, dung lượng tải và thời gian nạp của Whisper tiny/base/small/medium/SenseVoice.
- So sánh Whisper auto với ép vi và en.
- Zipformer trên bộ 32 câu mới và trên giọng thật; WAV test_wavs có sẵn của Zipformer không có transcript tham chiếu nên WER/CER không xác định.
- Chất lượng tiếng nói thật của anh Nghĩa và ảnh hưởng hậu xử lý từng mode.

Không còn model, archive, WAV tổng hợp hoặc tiến trình đo nào để dọn; các tệp bền vững duy nhất là nguồn đánh giá trong eval/multilingual/ và báo cáo này.
