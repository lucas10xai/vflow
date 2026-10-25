# vflow — đọc chính tả giọng nói tiếng Việt, chạy trong máy

Ngày: 2026-10-26 · Chủ sở hữu: Nguyễn Văn An · Điều phối: Chief of Staff (omp)

## Mục tiêu
Công cụ "giữ phím, nói, nhả phím, chữ hiện vào ô đang gõ" giống [Haynoi](https://github.com/sonpiaz/haynoi), khác ở chỗ:
- **Model tiếng Việt chạy trong máy của anh**, không gửi âm thanh lên dịch vụ ngoài, không đăng nhập, không hạn mức từ.
- Phù hợp cách anh làm việc: nói tiếng Việt xen thuật ngữ kỹ thuật (deploy, commit, worktree, Orca, AIOS…) khi ra lệnh cho agent trong terminal.
- Dùng 9Router có sẵn (OpenAI-compatible, `http://127.0.0.1:20128/v1`) cho bước viết lại, thay Kyma.

Nền tảng dùng thật: **macOS (Mac Core)**. HP Windows chỉ là máy dựng/kiểm thử (không GPU, ~4,9 GB RAM trống lúc khảo sát, đã có Node 22, chưa có Python/ffmpeg).

## Không làm (non-goals)
Tài khoản, thanh toán, telemetry/analytics, tự cập nhật, STT đám mây, client Windows, đồng bộ từ điển lên mạng.

## Giả định đã khảo sát (nguồn công khai, CHƯA đo trên máy anh)
- Zipformer-30M-RNNT-6000h (`hynt/Zipformer-30M-RNNT-6000h`, có bản streaming): 30 triệu tham số, ~6.000 giờ tiếng Việt; gói `sherpa-onnx-zipformer-vi-30M-int8-2026-02-09` chạy bằng `sherpa-onnx` trên CPU.
- PhoWhisper (VinAI, `vinai/PhoWhisper-{tiny,base,small,medium,large}`): Whisper tinh chỉnh trên 844 giờ tiếng Việt.
- Rủi ro đã biết: model thuần Việt kém ở từ tiếng Anh xen giữa câu; bù bằng từ điển + ánh xạ phiên âm + (tuỳ chọn) viết lại bằng LLM. Chất lượng thật chỉ biết sau khi đo bằng giọng của anh.

## Kiến trúc
```
client macOS (Swift, đợt sau)  --HTTP 127.0.0.1-->  engine (Node 22, ESM)
                                                    ├─ stt/    sherpa-onnx-node: zipformer-vi-30m (offline + streaming)
                                                    │          remote: PhoWhisper trên gpu-host qua SSH tunnel
                                                    ├─ post/   từ điển cá nhân, làm sạch, chế độ, viết lại qua 9Router
                                                    └─ server/ HTTP cục bộ theo contract/engine-api.md
eval/  bộ đo WER/CER/RTF/RAM, câu thoại mẫu, so sánh model
```
Engine viết bằng JavaScript ESM + JSDoc, test bằng `node --test`, **không bước build**, để chạy được y hệt trên HP (Windows) và Mac mà không cài Python.

## Quy ước làm việc
- Repo chuẩn: `/Users/example/Developer/vflow` (máy Mac). Worker sửa file ở đây.
- HP là máy dựng/kiểm thử: đồng bộ mã sang `C:\Users\example\dev\vflow` rồi chạy lệnh qua `ssh windows-host` (script `scripts/hp.sh`).
- Mọi giá trị bí mật (khoá 9Router…) chỉ đọc từ biến môi trường hoặc tệp ngoài repo (`~/.vflow/`), không bao giờ nằm trong repo, log, fixture hay báo cáo.
- Truth-first: lỗi/thiếu dữ liệu hiện đúng là lỗi; không biến thành chuỗi rỗng "thành công". Viết lại hỏng thì trả nguyên văn bản gốc kèm cờ lỗi.

## Các đợt (milestone)
| Đợt | Nội dung | Máy chạy | Phụ thuộc |
|---|---|---|---|
| M0 | Khung repo, `scripts/hp.sh` (đồng bộ + chạy trên HP), test chạy được trên cả Mac và HP | Mac + HP | — |
| M1a | `engine/stt` + `server` + CLI + `eval` (đo WER/RTF/RAM bằng gói test của model) | HP | M0 |
| M1b | `engine/post`: từ điển, làm sạch, chế độ, viết lại; bộ câu thoại mẫu | HP | M0 |
| M1c | PhoWhisper trên gpu-host (server cùng contract) + so sánh | gpu-host | contract |
| M2 | Ghi âm bộ đo bằng giọng anh, so sánh model, chọn mặc định | Mac | M1a–c |
| M3 | Client macOS menu bar: phím nóng, ghi âm 16 kHz, chèn chữ (Accessibility + clipboard), lớp phủ, âm báo | Mac | M2 |

Tiêu chí chọn model mặc định (quyết sau M2, không quyết trước): WER thấp nhất trên bộ câu của anh với điều kiện RTF < 0,3 trên Mac và độ trễ (nhả phím đến có chữ) với câu 5 giây dưới 1,5 giây. Nếu không model nào đạt, báo cáo đúng như vậy.
