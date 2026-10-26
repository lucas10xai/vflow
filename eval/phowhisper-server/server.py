"""Máy chủ STT PhoWhisper cho vflow, theo contract/remote-stt.md (v0.1).

Chỉ nghe 127.0.0.1. Âm thanh chỉ nằm trong bộ nhớ, không ghi xuống đĩa.
Log chỉ có id, thời lượng, thời gian xử lý, mã lỗi (không có văn bản).

Biến môi trường:
  VFLOW_REMOTE_TOKEN       token Bearer (bắt buộc, hoặc dùng VFLOW_REMOTE_TOKEN_FILE)
  VFLOW_REMOTE_TOKEN_FILE  đường dẫn tệp chứa token (quyền 0600)
  VFLOW_REMOTE_PORT        cổng (mặc định 7612)
  VFLOW_MODEL_DIR          thư mục model CTranslate2 (backend ct2) hoặc id/thư mục HF (backend hf)
  VFLOW_MODEL_ID           tên model trả về client (mặc định phowhisper-large)
  VFLOW_BACKEND            ct2 (faster-whisper, mặc định) | hf (transformers)
  VFLOW_BEAM               beam size (mặc định 1)
  VFLOW_QUEUE_WAIT_S       thời gian tối đa chờ tới lượt dùng GPU (mặc định 30)
"""

import hmac
import io
import json
import logging
import os
import secrets
import stat
import sys
import threading
import time
import wave
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import parse_qs, urlsplit

import numpy as np

HOST = "127.0.0.1"
SAMPLE_RATE = 16000
MAX_AUDIO_S = 120
# Giới hạn byte thô trước khi giải mã: đủ cho 120 s WAV 48 kHz stereo 16-bit.
MAX_BODY_BYTES = MAX_AUDIO_S * 48000 * 2 * 2 + 4096

log = logging.getLogger("vflow-phowhisper")


class ApiError(Exception):
    def __init__(self, status, code, message):
        super().__init__(message)
        self.status = status
        self.code = code
        self.message = message


def read_token():
    """Đọc token từ biến môi trường hoặc tệp 0600. Không bao giờ log token."""
    token = os.environ.get("VFLOW_REMOTE_TOKEN", "")
    path = os.environ.get("VFLOW_REMOTE_TOKEN_FILE", "")
    if not token and path:
        mode = stat.S_IMODE(os.stat(path).st_mode)
        if mode & 0o077:
            raise SystemExit(f"Tệp token phải có quyền 0600 (hiện {oct(mode)})")
        with open(path, encoding="utf-8") as f:
            token = f.read().strip()
    if len(token) < 16:
        raise SystemExit("Thiếu token: đặt VFLOW_REMOTE_TOKEN hoặc VFLOW_REMOTE_TOKEN_FILE (>= 16 ký tự)")
    return token


def to_mono_16k(samples, rate, channels):
    """int16 xen kẽ kênh -> float32 mono 16 kHz trong [-1, 1]."""
    audio = samples.astype(np.float32) / 32768.0
    if channels > 1:
        audio = audio.reshape(-1, channels).mean(axis=1)
    if rate != SAMPLE_RATE:
        n_out = int(round(len(audio) * SAMPLE_RATE / rate))
        x_old = np.arange(len(audio), dtype=np.float64) / rate
        x_new = np.arange(n_out, dtype=np.float64) / SAMPLE_RATE
        audio = np.interp(x_new, x_old, audio).astype(np.float32)
    return audio


def parse_content_type(value):
    parts = [p.strip() for p in (value or "").split(";")]
    params = {}
    for p in parts[1:]:
        if "=" in p:
            k, v = p.split("=", 1)
            params[k.strip().lower()] = v.strip()
    return parts[0].lower(), params


def decode_audio(body, content_type):
    """Trả (audio float32 mono 16 kHz, audio_ms). Lỗi -> ApiError bad_audio/payload_too_large."""
    mime, params = parse_content_type(content_type)
    if mime == "audio/l16":
        try:
            rate = int(params.get("rate", SAMPLE_RATE))
            channels = int(params.get("channels", 1))
        except ValueError:
            raise ApiError(400, "bad_audio", "Tham số rate/channels không hợp lệ")
        if rate < 8000 or rate > 48000 or channels < 1 or channels > 2:
            raise ApiError(400, "bad_audio", "Chỉ hỗ trợ 8–48 kHz, 1–2 kênh")
        if len(body) % (2 * channels):
            raise ApiError(400, "bad_audio", "Độ dài PCM không khớp int16 × số kênh")
        samples = np.frombuffer(body, dtype="<i2")
    elif mime in ("audio/wav", "audio/x-wav", "audio/wave"):
        try:
            with wave.open(io.BytesIO(body), "rb") as w:
                if w.getcomptype() != "NONE" or w.getsampwidth() != 2:
                    raise ApiError(400, "bad_audio", "WAV phải là PCM 16-bit")
                rate, channels = w.getframerate(), w.getnchannels()
                frames = w.readframes(w.getnframes())
        except ApiError:
            raise
        except (wave.Error, EOFError, ValueError) as e:
            raise ApiError(400, "bad_audio", f"WAV hỏng hoặc không phải PCM 16-bit ({type(e).__name__})")
        if rate < 8000 or rate > 48000 or channels < 1 or channels > 2:
            raise ApiError(400, "bad_audio", "Chỉ hỗ trợ 8–48 kHz, 1–2 kênh")
        if len(frames) % (2 * channels):
            raise ApiError(400, "bad_audio", "Dữ liệu WAV bị cắt cụt")
        samples = np.frombuffer(frames, dtype="<i2")
    else:
        raise ApiError(400, "bad_audio", "Content-Type phải là audio/L16 hoặc audio/wav")
    n_frames = len(samples) // channels
    if n_frames == 0:
        raise ApiError(400, "bad_audio", "Âm thanh rỗng")
    audio_ms = int(round(n_frames * 1000 / rate))
    if audio_ms > MAX_AUDIO_S * 1000:
        raise ApiError(413, "payload_too_large", f"Âm thanh dài hơn {MAX_AUDIO_S} giây")
    return to_mono_16k(samples, rate, channels), audio_ms


class Ct2Backend:
    """faster-whisper (CTranslate2) fp16 trên cuda:0."""

    def __init__(self, model_dir, beam):
        from faster_whisper import WhisperModel

        self.beam = beam
        self.model = WhisperModel(model_dir, device="cuda", device_index=0, compute_type="float16")

    def transcribe(self, audio):
        segments, _ = self.model.transcribe(
            audio,
            language="vi",
            task="transcribe",
            beam_size=self.beam,
            condition_on_previous_text=False,
            without_timestamps=True,
            vad_filter=False,
        )
        return " ".join(s.text.strip() for s in segments).strip()


class HfBackend:
    """transformers WhisperForConditionalGeneration fp16 trên cuda:0."""

    def __init__(self, model_dir, beam):
        import torch
        from transformers import pipeline

        self.beam = beam
        self.pipe = pipeline(
            "automatic-speech-recognition",
            model=model_dir,
            torch_dtype=torch.float16,
            device="cuda:0",
        )

    def transcribe(self, audio):
        out = self.pipe(
            {"raw": audio, "sampling_rate": SAMPLE_RATE},
            chunk_length_s=30,
            generate_kwargs={"language": "vi", "task": "transcribe", "num_beams": self.beam},
        )
        return out["text"].strip()


class State:
    def __init__(self, token, model_id):
        self.token = token
        self.model_id = model_id
        self.backend = None
        self.reason = "loading"
        self.load_ms = None
        self.gpu_lock = threading.Lock()
        self.queue_wait_s = float(os.environ.get("VFLOW_QUEUE_WAIT_S", "30"))

    def load(self, backend_name, model_dir, beam):
        t0 = time.monotonic()
        try:
            cls = {"ct2": Ct2Backend, "hf": HfBackend}[backend_name]
            backend = cls(model_dir, beam)
            # Khởi động nóng để yêu cầu đầu tiên không chịu chi phí cấp phát CUDA.
            backend.transcribe(np.zeros(SAMPLE_RATE, dtype=np.float32))
            self.backend = backend
            self.reason = None
            self.load_ms = int((time.monotonic() - t0) * 1000)
            log.info("model_loaded backend=%s load_ms=%d", backend_name, self.load_ms)
        except Exception as e:  # noqa: BLE001 - phải hiện lý do, không im lặng
            self.reason = f"load_failed:{type(e).__name__}"
            log.error("model_load_failed backend=%s err=%s", backend_name, type(e).__name__)


def make_handler(state):
    class Handler(BaseHTTPRequestHandler):
        server_version = "vflow-phowhisper/0.1"
        sys_version = ""

        def log_message(self, fmt, *args):  # tắt log mặc định (có thể chứa query)
            pass

        def send_json(self, status, obj):
            data = json.dumps(obj, ensure_ascii=False).encode("utf-8")
            self.send_response(status)
            self.send_header("Content-Type", "application/json; charset=utf-8")
            self.send_header("Content-Length", str(len(data)))
            self.send_header("Cache-Control", "no-store")
            self.end_headers()
            self.wfile.write(data)

        def send_error_json(self, err):
            self.send_json(err.status, {"error": {"code": err.code, "message": err.message}})

        def do_GET(self):
            path = urlsplit(self.path).path
            if path != "/healthz":
                return self.send_error_json(ApiError(404, "bad_request", "Không có đường dẫn này"))
            body = {
                "ok": state.backend is not None,
                "model": state.model_id,
                "device": "cuda:0",
                "dtype": "float16",
                "loaded": state.backend is not None,
            }
            if state.backend is None:
                body["reason"] = state.reason
            self.send_json(200, body)

        def do_POST(self):
            req_id = "tr_" + secrets.token_hex(6)
            t0 = time.monotonic()
            audio_ms = None
            try:
                url = urlsplit(self.path)
                if url.path != "/v1/transcribe":
                    raise ApiError(404, "bad_request", "Không có đường dẫn này")
                auth = self.headers.get("Authorization", "")
                given = auth[7:] if auth.startswith("Bearer ") else ""
                if not given or not hmac.compare_digest(given.encode(), state.token.encode()):
                    raise ApiError(401, "unauthorized", "Thiếu hoặc sai token")
                lang = parse_qs(url.query).get("lang", ["vi"])[0]
                if lang != "vi":
                    raise ApiError(400, "bad_request", "Chỉ hỗ trợ lang=vi")
                try:
                    length = int(self.headers.get("Content-Length", ""))
                except ValueError:
                    raise ApiError(411, "bad_request", "Thiếu Content-Length")
                if length < 0:
                    raise ApiError(400, "bad_request", "Content-Length không hợp lệ")
                if length > MAX_BODY_BYTES:
                    raise ApiError(413, "payload_too_large", f"Âm thanh dài hơn {MAX_AUDIO_S} giây")
                body = self.rfile.read(length)
                if len(body) != length:
                    raise ApiError(400, "bad_audio", "Thân yêu cầu bị cắt cụt")
                audio, audio_ms = decode_audio(body, self.headers.get("Content-Type"))
                del body
                if state.backend is None:
                    raise ApiError(503, "model_unavailable", f"Model chưa sẵn sàng: {state.reason}")
                if not state.gpu_lock.acquire(timeout=state.queue_wait_s):
                    raise ApiError(503, "timeout", "GPU đang bận, hết thời gian chờ")
                try:
                    t_stt = time.monotonic()
                    text = state.backend.transcribe(audio)
                    stt_ms = int((time.monotonic() - t_stt) * 1000)
                finally:
                    state.gpu_lock.release()
                self.send_json(200, {"text": text, "audio_ms": audio_ms, "stt_ms": stt_ms, "model": state.model_id})
                log.info("id=%s status=200 audio_ms=%d stt_ms=%d total_ms=%d", req_id, audio_ms, stt_ms,
                         int((time.monotonic() - t0) * 1000))
            except ApiError as e:
                self.send_error_json(e)
                log.info("id=%s status=%d code=%s audio_ms=%s total_ms=%d", req_id, e.status, e.code, audio_ms,
                         int((time.monotonic() - t0) * 1000))
            except Exception as e:  # noqa: BLE001
                self.send_error_json(ApiError(500, "internal", "Lỗi nội bộ máy chủ"))
                log.error("id=%s status=500 code=internal err=%s", req_id, type(e).__name__)

    return Handler


def main():
    logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s", stream=sys.stderr)
    logging.getLogger("faster_whisper").setLevel(logging.WARNING)
    token = read_token()
    port = int(os.environ.get("VFLOW_REMOTE_PORT", "7612"))
    model_dir = os.environ.get("VFLOW_MODEL_DIR", "")
    if not model_dir:
        raise SystemExit("Thiếu VFLOW_MODEL_DIR")
    state = State(token, os.environ.get("VFLOW_MODEL_ID", "phowhisper-large"))
    httpd = ThreadingHTTPServer((HOST, port), make_handler(state))
    httpd.daemon_threads = True
    log.info("listening %s:%d", HOST, port)
    loader = threading.Thread(
        target=state.load,
        args=(os.environ.get("VFLOW_BACKEND", "ct2"), model_dir, int(os.environ.get("VFLOW_BEAM", "1"))),
        daemon=True,
    )
    loader.start()
    try:
        httpd.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        httpd.server_close()


if __name__ == "__main__":
    main()
