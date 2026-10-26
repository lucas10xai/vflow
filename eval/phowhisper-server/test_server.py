"""Kiểm thử hành vi HTTP của server.py bằng backend giả (không cần GPU).

Chạy: python3 -m unittest test_server  (cần numpy)
"""

import io
import json
import logging
import os
import struct
import threading
import unittest
import urllib.error
import urllib.request
import wave
from http.server import ThreadingHTTPServer

import numpy as np

import server

TOKEN = "t" * 32


class FakeBackend:
    def __init__(self):
        self.calls = []
        self.active = 0
        self.max_active = 0
        self.lock = threading.Lock()
        self.delay = 0.0

    def transcribe(self, audio):
        with self.lock:
            self.active += 1
            self.max_active = max(self.max_active, self.active)
        try:
            if self.delay:
                threading.Event().wait(self.delay)
            self.calls.append(audio)
            return "xin chào"
        finally:
            with self.lock:
                self.active -= 1


def wav_bytes(seconds, rate=16000, channels=1, sampwidth=2):
    buf = io.BytesIO()
    with wave.open(buf, "wb") as w:
        w.setnchannels(channels)
        w.setsampwidth(sampwidth)
        w.setframerate(rate)
        w.writeframes(b"\x00" * int(seconds * rate) * channels * sampwidth)
    return buf.getvalue()


class ServerTest(unittest.TestCase):
    def setUp(self):
        self.state = server.State(TOKEN, "phowhisper-large")
        self.backend = FakeBackend()
        self.state.backend = self.backend
        self.state.reason = None
        self.httpd = ThreadingHTTPServer((server.HOST, 0), server.make_handler(self.state))
        self.port = self.httpd.server_address[1]
        threading.Thread(target=self.httpd.serve_forever, daemon=True).start()

    def tearDown(self):
        self.httpd.shutdown()
        self.httpd.server_close()

    def request(self, method, path, body=None, headers=None):
        req = urllib.request.Request(f"http://127.0.0.1:{self.port}{path}", data=body, method=method,
                                     headers=headers or {})
        try:
            with urllib.request.urlopen(req, timeout=10) as r:
                return r.status, json.loads(r.read())
        except urllib.error.HTTPError as e:
            with e:
                return e.code, json.loads(e.read())

    def post(self, body, ctype="audio/wav", token=TOKEN, path="/v1/transcribe"):
        headers = {"Content-Type": ctype}
        if token is not None:
            headers["Authorization"] = f"Bearer {token}"
        return self.request("POST", path, body, headers)

    def test_binds_loopback_only(self):
        self.assertEqual(server.HOST, "127.0.0.1")
        self.assertEqual(self.httpd.server_address[0], "127.0.0.1")

    def test_healthz_reports_reason_while_loading(self):
        self.state.backend = None
        self.state.reason = "loading"
        status, body = self.request("GET", "/healthz")
        self.assertEqual(status, 200)
        self.assertEqual((body["ok"], body["loaded"], body["reason"]), (False, False, "loading"))
        status, body = self.post(wav_bytes(1))
        self.assertEqual((status, body["error"]["code"]), (503, "model_unavailable"))
        self.assertIn("loading", body["error"]["message"])

    def test_healthz_loaded(self):
        status, body = self.request("GET", "/healthz")
        self.assertEqual(body, {"ok": True, "model": "phowhisper-large", "device": "cuda:0",
                                "dtype": "float16", "loaded": True})

    def test_missing_or_wrong_token_is_401_and_backend_not_called(self):
        for token in (None, "", "sai", TOKEN + "x", TOKEN[:-1]):
            status, body = self.post(wav_bytes(1), token=token)
            self.assertEqual((status, body["error"]["code"]), (401, "unauthorized"), token)
        status, body = self.request("POST", "/v1/transcribe", wav_bytes(1),
                                    {"Content-Type": "audio/wav", "Authorization": f"Basic {TOKEN}"})
        self.assertEqual(status, 401)
        self.assertEqual(self.backend.calls, [])

    def test_wav_ok_returns_contract_fields(self):
        status, body = self.post(wav_bytes(2.5))
        self.assertEqual(status, 200)
        self.assertEqual(body["text"], "xin chào")
        self.assertEqual(body["audio_ms"], 2500)
        self.assertEqual(body["model"], "phowhisper-large")
        self.assertIsInstance(body["stt_ms"], int)
        self.assertEqual(len(self.backend.calls[0]), 40000)

    def test_l16_raw_pcm(self):
        pcm = struct.pack("<4h", 0, 16384, -32768, 32767) * 4000
        status, body = self.post(pcm, ctype="audio/L16; rate=16000; channels=1")
        self.assertEqual((status, body["audio_ms"]), (200, 1000))
        audio = self.backend.calls[0]
        self.assertEqual(audio.dtype, np.float32)
        self.assertAlmostEqual(float(audio[1]), 0.5, places=4)
        self.assertAlmostEqual(float(audio[2]), -1.0, places=4)

    def test_wav_resampled_and_downmixed_to_16k_mono(self):
        status, body = self.post(wav_bytes(1, rate=44100, channels=2))
        self.assertEqual((status, body["audio_ms"]), (200, 1000))
        self.assertEqual(len(self.backend.calls[0]), 16000)

    def test_bad_audio(self):
        cases = [
            (b"RIFF\x00\x00garbage", "audio/wav"),
            (wav_bytes(1)[:-1], "audio/wav"),  # khung int16 bị cắt
            (wav_bytes(1, sampwidth=1), "audio/wav"),  # 8-bit
            (wav_bytes(0), "audio/wav"),  # rỗng
            (b"\x00\x00\x00", "audio/L16; rate=16000; channels=1"),  # lẻ byte
            (b"", "audio/L16; rate=16000; channels=1"),
            (b"\x00\x00", "audio/L16; rate=abc; channels=1"),
            (wav_bytes(1), "audio/mpeg"),
        ]
        for body, ctype in cases:
            status, resp = self.post(body, ctype=ctype)
            self.assertEqual((status, resp["error"]["code"]), (400, "bad_audio"), (ctype, body[:16]))
        self.assertEqual(self.backend.calls, [])

    def test_audio_over_120s_rejected(self):
        status, body = self.post(wav_bytes(120.5))
        self.assertEqual((status, body["error"]["code"]), (413, "payload_too_large"))
        status, body = self.post(wav_bytes(120))
        self.assertEqual(status, 200)

    def test_only_one_inference_at_a_time(self):
        self.backend.delay = 0.2
        results = []
        threads = [threading.Thread(target=lambda: results.append(self.post(wav_bytes(1))[0])) for _ in range(4)]
        for t in threads:
            t.start()
        for t in threads:
            t.join()
        self.assertEqual(results, [200] * 4)
        self.assertEqual(self.backend.max_active, 1)

    def test_queue_wait_exceeded_is_timeout_not_success(self):
        self.state.queue_wait_s = 0.05
        self.state.gpu_lock.acquire()
        try:
            status, body = self.post(wav_bytes(1))
        finally:
            self.state.gpu_lock.release()
        self.assertEqual((status, body["error"]["code"]), (503, "timeout"))

    def test_backend_exception_is_internal(self):
        def boom(audio):
            raise RuntimeError("CUDA out of memory")
        self.backend.transcribe = boom
        status, body = self.post(wav_bytes(1))
        self.assertEqual((status, body["error"]["code"]), (500, "internal"))
        self.assertNotIn("CUDA", body["error"]["message"])

    def test_log_has_no_text_or_token(self):
        records = []

        class H(logging.Handler):
            def emit(self, record):
                records.append(record.getMessage())

        h = H()
        server.log.addHandler(h)
        server.log.setLevel(logging.INFO)
        try:
            self.post(wav_bytes(1))
            self.post(wav_bytes(1), token="sai-token-abc")
        finally:
            server.log.removeHandler(h)
        joined = "\n".join(records)
        self.assertIn("status=200", joined)
        self.assertIn("code=unauthorized", joined)
        for secret in ("xin chào", TOKEN, "sai-token-abc"):
            self.assertNotIn(secret, joined)


class TokenTest(unittest.TestCase):
    def setUp(self):
        self.env = {k: os.environ.pop(k) for k in ("VFLOW_REMOTE_TOKEN", "VFLOW_REMOTE_TOKEN_FILE") if k in os.environ}

    def tearDown(self):
        os.environ.update(self.env)

    def test_missing_or_short_token_refuses_to_start(self):
        with self.assertRaises(SystemExit):
            server.read_token()
        os.environ["VFLOW_REMOTE_TOKEN"] = "short"
        try:
            with self.assertRaises(SystemExit):
                server.read_token()
        finally:
            del os.environ["VFLOW_REMOTE_TOKEN"]

    def test_token_file_must_be_0600(self):
        import tempfile
        with tempfile.TemporaryDirectory() as d:
            p = os.path.join(d, "token")
            with open(p, "w") as f:
                f.write(TOKEN + "\n")
            os.environ["VFLOW_REMOTE_TOKEN_FILE"] = p
            try:
                os.chmod(p, 0o644)
                with self.assertRaises(SystemExit):
                    server.read_token()
                os.chmod(p, 0o600)
                self.assertEqual(server.read_token(), TOKEN)
            finally:
                del os.environ["VFLOW_REMOTE_TOKEN_FILE"]


if __name__ == "__main__":
    unittest.main()
