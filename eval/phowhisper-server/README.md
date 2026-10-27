# Máy chủ STT PhoWhisper (M1c)

Máy chủ STT từ xa theo `contract/remote-stt.md`, chạy `vinai/PhoWhisper-large` trên một máy GPU (`gpu-host`;
RTX A4000, dùng chung). Mac gọi qua SSH tunnel; máy chủ chỉ nghe `127.0.0.1:7612`.

| Tệp | Vai trò |
|---|---|
| `server.py` | HTTP (thư viện chuẩn `http.server`), `GET /healthz`, `POST /v1/transcribe` |
| `convert.py` | Chuyển PhoWhisper (`pytorch_model.bin` fp32) sang CTranslate2 float16, RAM đỉnh thấp |
| `run.sh` / `stop.sh` | Chạy/dừng nền trên máy GPU bằng `nohup` + `server.pid` (không sudo) |
| `tunnel.sh` | Trên Mac: `ssh -N -L 127.0.0.1:7612:127.0.0.1:7612 gpu-host`, báo lỗi nếu cổng đã bận (đặt `VFLOW_REMOTE_HOST` nếu alias SSH khác) |
| `bench.py` | Đo độ trễ/RTF và WER/CER (thư viện chuẩn, chạy được trên Mac và máy GPU) |
| `test_server.py` | Kiểm thử hành vi HTTP bằng backend giả (không cần GPU): `python3 -m unittest test_server` |

## Chọn phương án
Backend mặc định `ct2` = faster-whisper 1.2.1 / CTranslate2 4.8.4, `float16` trên `cuda:0`, `beam_size=1`.
Đã đo cả hai trên cùng bộ mẫu (2026-10-26, máy GPU, đo tại chỗ không qua tunnel):

| Backend | Tải model | VRAM tiến trình | stt 5 s (trung vị / p95) | stt 15 s | WER 12 clip |
|---|---|---|---|---|---|
| ct2 beam 1 (mặc định) | 4,2–9,9 s | 3.922–4.178 MiB | 368 / 452 ms | 694 / 856 ms | 0,1358 (5 s) · 0,0514 (15 s) |
| ct2 beam 5 | 4,6 s | 4.178 MiB | 413 / 511 ms | 754 / 984 ms | như beam 1 |
| transformers 4.57.6 fp16 beam 1 | 14,2 s | 3.730 MiB | 1.014 / 1.295 ms | 1.853 / 2.455 ms | như nhau (CER 5 s 0,1241) |

ct2 nhanh hơn ~2,7 lần, WER như nhau, xử lý âm thanh dài > 30 s sẵn (transformers cần `chunk_length_s`,
có cảnh báo "very experimental"). Beam 5 chậm hơn ~12 % mà WER trên FLEURS dev không tốt hơn
(0,0826 so với 0,0813), nên giữ beam 1. Backend `hf` vẫn giữ trong mã để đối chiếu (`VFLOW_BACKEND=hf`).

## Cài đặt trên máy GPU (gpu-host; mọi thứ trong `~/vflow-phowhisper/`)
```sh
cd ~/vflow-phowhisper
python3 -m venv venv
venv/bin/pip install torch==2.5.1 --index-url https://download.pytorch.org/whl/cu124
venv/bin/pip install -r app/requirements.txt
# Tải model (revision cố định) vào models/hf/PhoWhisper-large, kiểm sha256 pytorch_model.bin:
#   revision b9136a44b5f2ca664bd0b8f74baecf1715f6eeeb
#   sha256   9e0077352544f497673395b313a9ef6d7cd2967598197c4d691d8042333060b2 (khớp LFS oid trên HF)
venv/bin/python -B app/convert.py models/hf/PhoWhisper-large models/hf/PhoWhisper-large-fp16 \
  models/ct2/PhoWhisper-large-fp16
#   model.bin CT2 sha256 9e1ed3829506693cf7d9451f104336c63f854aa43b3de061c8ce96a9b677880b (3.086.913.037 byte)
umask 077; python3 -c "import secrets;print(secrets.token_urlsafe(32))" > token   # quyền 0600
```
Mã nằm ở `~/vflow-phowhisper/app/` (sao chép từ thư mục này). Giấy phép model: BSD-3-Clause.

## Chạy
```sh
# máy GPU (gpu-host)
bash ~/vflow-phowhisper/app/run.sh      # đọc token từ VFLOW_REMOTE_TOKEN hoặc ~/vflow-phowhisper/token
curl -s 127.0.0.1:7612/healthz          # chờ "loaded": true
bash ~/vflow-phowhisper/app/stop.sh
# Mac
./tunnel.sh                             # tiền cảnh; Ctrl-C để đóng
curl -s -H "Authorization: Bearer $(cat <tệp token>)" -H 'Content-Type: audio/wav' \
  --data-binary @mau.wav 'http://127.0.0.1:7612/v1/transcribe?lang=vi'
```
Biến môi trường: `VFLOW_REMOTE_TOKEN` / `VFLOW_REMOTE_TOKEN_FILE`, `VFLOW_REMOTE_PORT` (7612), `VFLOW_MODEL_DIR`,
`VFLOW_MODEL_ID` (`phowhisper-large`), `VFLOW_BACKEND` (`ct2`|`hf`), `VFLOW_BEAM` (1), `VFLOW_QUEUE_WAIT_S` (30).

## Hành vi
- Chỉ nghe `127.0.0.1`; không có tuỳ chọn đổi địa chỉ nghe.
- Token so sánh hằng thời gian; thiếu/sai ⇒ 401 `unauthorized`. Không có token (hoặc < 16 ký tự, hoặc tệp token
  không phải 0600) ⇒ từ chối khởi động.
- Model tải một lần ở luồng nền khi khởi động; trong lúc tải `/healthz` trả `ok:false, reason:"loading"` và
  `/v1/transcribe` trả 503 `model_unavailable`. Tải lỗi ⇒ `reason:"load_failed:<loại lỗi>"`.
- Body: `audio/L16; rate=…; channels=…` (int16 LE) hoặc `audio/wav` PCM 16-bit (8–48 kHz, 1–2 kênh; tự trộn mono
  và nội suy tuyến tính về 16 kHz). WAV float32/8-bit, dữ liệu cắt cụt, rỗng, Content-Type khác ⇒ 400 `bad_audio`.
- Dài hơn 120 s ⇒ 413 `payload_too_large` (mã lấy từ `contract/engine-api.md`; `remote-stt.md` không liệt kê mã này).
- `lang` khác `vi` ⇒ 400 `bad_request`.
- Một suy luận GPU tại một thời điểm (khoá); chờ quá `VFLOW_QUEUE_WAIT_S` ⇒ 503 `timeout`. Lỗi backend ⇒ 500
  `internal` (thông điệp chung, không lộ chi tiết).
- Âm thanh chỉ ở bộ nhớ. Log chỉ có id, status, mã lỗi, `audio_ms`, `stt_ms`, `total_ms`; log truy cập mặc định
  của `http.server` bị tắt; log INFO của faster-whisper bị hạ xuống WARNING.
- Không kiểm `Host` (khác engine): cổng phía Mac của tunnel có thể khác 7612; token là lớp bảo vệ.

## Đo (2026-10-26)
Điều kiện: máy GPU RTX A4000 16 GB dùng chung với các dịch vụ khác (đang có hai tiến trình khác chiếm ~2.430 MiB VRAM, GPU nhàn rỗi 0 %),
8 CPU (cgroup), ct2 fp16 beam 1. `stt_ms` do máy chủ đo (chỉ phần suy luận); RTF = `stt_ms / audio_ms`.
p95 theo nearest-rank. Dữ liệu:
- `3s`: `test_wavs/0.wav` (3,74 s), `1.wav` (2,40 s) trong gói `sherpa-onnx-zipformer-vi-30M-int8-2026-02-09`
  (sha256 tar.bz2 `da8b6379…6b9b`; nguồn gốc `nguyenvulebinh/wav2vec2-base-vietnamese-250h`, CC-BY-NC-4.0).
  Gói **không có văn bản tham chiếu** ⇒ WER/CER không xác định.
- `5s`, `15s`, `fleurs_dev`: Google FLEURS `vi_vn` dev (CC-BY-4.0, sha256 `dev.tar.gz` `8821a394…f673`), WAV float32
  gốc đã đổi sang PCM 16-bit bằng ffmpeg. `5s` = mọi clip 4,5–5,5 s (7 clip, trong đó 3 bản ghi cùng một câu);
  `15s` = 5 clip 14–16 s đầu tiên theo tên tệp, khác câu.
- Chuẩn hoá WER/CER (`bench.py`): NFC, chữ thường, bỏ dấu câu/ký hiệu Unicode (P*, S*), gộp khoảng trắng; CER bỏ
  khoảng trắng. **Không** chuẩn hoá số ("100 feet" và "một trăm phít" tính là 3 lỗi từ).

| Nhóm | Clip × lần | audio TB | stt trung vị / p95 | RTF trung vị / p95 | e2e tại máy GPU | e2e từ Mac qua tunnel | WER / CER |
|---|---|---|---|---|---|---|---|
| 3s | 2 × 10 | 3,07 s | 345 / 377 ms | 0,113 / 0,134 | 348 / 380 ms | 484 / 526 ms | không xác định (không có tham chiếu) |
| 5s | 7 × 10 | 4,98 s | 368 / 452 ms | 0,077 / 0,089 | 371 / 455 ms | 523 / 584 ms | 0,136 / 0,117 (7 clip, 81 từ) |
| 15s | 5 × 10 | 14,83 s | 694 / 856 ms | 0,048 / 0,055 | 696 / 859 ms | 856 / 1.049 ms | 0,051 / 0,025 (5 clip) |
| FLEURS dev đủ | 361 × 1 | 11,91 s | 632 / 967 ms | 0,057 / 0,075 | — | — | **0,081 / 0,059** |
| 102 s (10 clip nối) | 1 × 3 | 102,5 s | 3.638 / 3.742 ms | 0,036 | — | — | — |

- Tải model (đọc CT2 fp16 + chạy nóng 1 s im lặng): 9,9 s lần đầu (đĩa nguội), 4,2–5,4 s các lần sau.
- VRAM tiến trình (nvidia-smi, lấy mẫu 250 ms): 3.922 MiB sau khi tải, đỉnh 4.210 MiB; VRAM toàn GPU đỉnh 6.658 / 16.376 MiB.
- RAM tiến trình đỉnh (VmHWM): 3,19 GB. Chuyển đổi model: RSS đỉnh 4,3 GB, RAM trống thấp nhất 8,6 GB.
- e2e từ Mac = client Python trên Mac → tunnel → trả JSON (tạo kết nối TCP mới mỗi yêu cầu); phần thêm so với
  tại chỗ ≈ 140–160 ms.
- **Tunnel phải có `-o IPQoS=cs0`**: với mặc định của `ssh -N`, tải lên 478 KB (15 s WAV) mất 31–40 s; với cs0
  là 0,76–0,88 s. `tunnel.sh` đã đặt sẵn.

Giới hạn: bộ mẫu nhỏ, giọng đọc FLEURS/đọc văn bản, **không đại diện giọng của người dùng cuối** hay câu lệnh xen thuật ngữ
tiếng Anh; số đo GPU phụ thuộc tải của dịch vụ khác lúc đo. Lỗi điển hình quan sát được: số đọc thành chữ
("100 feet" → "một trăm phít"), tên riêng nước ngoài ("Moldova" → "modova", "Bishkek" → "bi két"), từ mượn
("ra đa" → "radar").
