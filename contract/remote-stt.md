# Hợp đồng STT từ xa (v0.1)

Máy chủ STT từ xa (ví dụ PhoWhisper trên `gpu-host`) chỉ làm một việc: nhận âm thanh, trả chữ thô. Từ điển, chế độ, viết lại do engine vflow trên Mac làm.

- Chỉ nghe `127.0.0.1` trên máy chủ từ xa. Mac gọi qua **SSH tunnel** (`ssh -N -L 7612:127.0.0.1:7612 gpu-host`), không mở cổng ra Internet, không dùng Tailscale/Cloudflare tunnel.
- Xác thực: header `Authorization: Bearer <token>`; token do người dùng đặt khi chạy server (biến môi trường `VFLOW_REMOTE_TOKEN` hoặc tệp quyền 0600), không nằm trong repo/log.

## GET /healthz
`{ "ok": true, "model": "phowhisper-large", "device": "cuda:0", "dtype": "float16", "loaded": true }`
Chưa tải xong model: `ok:false` kèm `reason`.

## POST /v1/transcribe
Body y hệt engine: PCM thô `audio/L16; rate=16000; channels=1` hoặc `audio/wav`. Query `lang=vi` (mặc định).
200: `{ "text": "…", "audio_ms": 5230, "stt_ms": 380, "model": "phowhisper-large" }`
Lỗi: `{ "error": { "code": "bad_audio|unauthorized|model_unavailable|timeout|internal", "message": "…" } }`.
Không ghi âm thanh xuống đĩa; log không chứa văn bản.
