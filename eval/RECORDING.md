# Thu bộ câu đo và so sánh model (M2)

Âm thanh thu là **dữ liệu cá nhân**: chỉ lưu ở `~/.vflow/eval/<tên-bộ>/` (ngoài repo; `record-set` từ chối ghi vào trong repo), không commit, không gửi đi đâu ngoài STT mà anh chọn khi chạy `compare`. Cách đọc câu, số, URL: xem `eval/prompts/README.md`.

## 1. Cấp quyền micro (macOS, làm một lần)

ffmpeg chạy dưới quyền của ứng dụng terminal (Terminal, iTerm2, Ghostty, Warp…), nên quyền micro cấp cho **ứng dụng terminal**, không cấp riêng cho ffmpeg.

1. Chạy `node bin/vflow.js record-set --list-devices`: phải thấy `[0] Micrô MacBook Pro` (hoặc mic tai nghe).
2. Lần thu đầu tiên macOS hỏi "… muốn truy cập micrô" → **Cho phép**.
3. Nếu đã lỡ từ chối, hoặc thu ra toàn im lặng (mean rất thấp, cảnh báo `too_quiet`): **Cài đặt hệ thống → Quyền riêng tư & Bảo mật → Micrô** → bật cho ứng dụng terminal đang dùng, rồi **thoát hẳn (⌘Q) và mở lại** terminal đó (quyền chỉ áp dụng cho tiến trình mới).
4. Nếu terminal không có trong danh sách: chạy lại một lần thu để macOS hỏi; hoặc đặt lại bằng `tccutil reset Microphone <bundle id>` (ví dụ `com.apple.Terminal`) rồi thu lại.

## 2. Thu âm

```sh
node bin/vflow.js record-set --prompts eval/prompts/vi-en-40.txt --out ~/.vflow/eval/vi-en-40 [--device 0]
```

- Mỗi câu hiện `NN/40` chữ to (dòng cao gấp đôi trên Terminal/iTerm2). **Enter** bắt đầu thu, **Enter** lần nữa để dừng. Chương trình không bao giờ tự thu nền: chỉ thu giữa hai lần bấm Enter.
- Sau mỗi bản thu: thời lượng, mức âm (ffmpeg `volumedetect`: mean/max dB) và cảnh báo nếu quá nhỏ (mean < -45 dB hoặc max < -20 dB), có thể vỡ tiếng (max ≥ -0,5 dB) hoặc quá ngắn (< 1 s).
- Rồi chọn: **Enter** lưu và sang câu tiếp · **r** thu lại · **p** nghe lại (afplay) · **s** bỏ qua · **q** thoát (bản vừa thu chưa lưu sẽ bị bỏ).
- Mỗi câu lưu thành `NN.wav` (PCM 16-bit, 16 kHz, mono) + `NN.txt` (đúng nội dung câu). Lỡ nói khác câu: sửa `NN.txt` theo lời đã nói.
- Chạy lại cùng lệnh thì **tiếp tục** từ câu chưa có (câu đã có đủ `wav` + `txt` không bị ghi đè). Thu lại câu đã có: `--redo 07,12` (hỏi xác nhận trước khi ghi đè).
- `set.json` trong thư mục bộ ghi nguồn thu (`avfoundation:N` hoặc giả) và cờ `synthetic`. Thử không cần micro: `--input-fake` (sóng sin của ffmpeg; `--fake-gain=-40` để thử cảnh báo nhỏ tiếng); bộ đó bị đánh dấu `synthetic: true` vĩnh viễn.

## 3. So sánh model

```sh
# Chỉ model cục bộ
node bin/vflow.js compare --set ~/.vflow/eval/vi-en-40 --models zipformer-vi-30m

# Có PhoWhisper trên gpu-host (GPU dùng chung: bật trước khi đo, TẮT ngay sau khi đo)
scripts/phowhisper.sh up        # kiểm VRAM (> 10 GB của dịch vụ khác ⇒ từ chối, mã 3), chạy máy chủ, mở tunnel
scripts/phowhisper.sh exec -- node bin/vflow.js compare --set ~/.vflow/eval/vi-en-40 \
  --models zipformer-vi-30m,phowhisper-large
scripts/phowhisper.sh down      # đóng tunnel + dừng máy chủ
scripts/phowhisper.sh status
```

`exec` lấy token bằng `ssh gpu-host 'cat ~/vflow-phowhisper/token'` thẳng vào biến môi trường `VFLOW_REMOTE_TOKEN` của tiến trình con: không in, không ghi đĩa trên Mac.

Báo cáo ghi vào `<bộ>/reports/compare-<thời điểm>.md` + `.json` (đổi bằng `--out`). Nội dung:
- văn bản thô và sau `engine/post` (mặc định `--mode normal`; từ điển = **chỉ hạt giống** `config/dictionary.seed.json`, chạy trên bản sao tạm nên không đụng `~/.vflow/dictionary.json`; `--dictionary <tệp>` để dùng từ điển khác, cũng qua bản sao);
- WER/CER nhạy và không nhạy dấu thanh cho cả hai dạng (chênh lệch = phần từ điển giúp được);
- tỉ lệ bắt thuật ngữ tiếng Anh (`eval/prompts/terms.json`) và bảng **thuật ngữ bị sót → model đã nghe ra gì** (văn bản thô ở vị trí tương ứng, kèm số clip) để bổ sung `spoken` vào từ điển;
- độ trễ stt trung vị/p95, độ trễ câu 4–6 s, RTF; tải model;
- **KẾT LUẬN** theo tiêu chí trong `docs/specs/2026-10-26-vflow-design.md`: WER thấp nhất (sau post, nhạy dấu thanh) trong các model có RTF trung vị < 0,3 và p95 độ trễ câu ~5 s (clip 4–6 s) < 1,5 s, không có clip lỗi. Không model nào đạt ⇒ ghi đúng như vậy.

Lỗi một clip không làm dừng lần chạy: clip đó ghi `LỖI <mã>`, số liệu tổng hợp chỉ tính clip thành công và ghi rõ số clip lỗi. Bộ < 30 câu, giọng tổng hợp, hoặc thiếu `set.json` ⇒ cảnh báo **KHÔNG ĐẠI DIỆN** ở đầu báo cáo và kết luận không chọn model.

Giới hạn đã biết: tham chiếu viết số/URL dạng chữ mong muốn (`5678`, `localhost:3000`) còn model nghe ra chữ đọc ("năm sáu bảy tám"), nên WER bị cộng lỗi ở các câu này và cột "nghe ra" của thuật ngữ cạnh số có thể dính cả phần số. Độ trễ của model từ xa gồm mạng + tunnel.
