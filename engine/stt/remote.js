/**
 * Provider STT từ xa theo contract/remote-stt.md (ví dụ PhoWhisper trên gpu-host qua SSH tunnel).
 * Token đọc từ VFLOW_REMOTE_TOKEN; không bao giờ đưa token vào lỗi/log.
 */
import { performance } from 'node:perf_hooks';
import { SttError, modelUnavailable } from './errors.js';
import { TARGET_RATE, durationMs, resample, toFloat32, toInt16 } from './audio.js';

const PASS_THROUGH = new Set(['bad_audio', 'timeout', 'model_unavailable']);

/**
 * @param {{ id: string, url: string, token?: string|null, fetchImpl?: typeof fetch,
 *           timeoutMs?: number, healthTimeoutMs?: number }} opts
 */
export function createRemoteProvider({ id, url, token, fetchImpl = fetch, timeoutMs = 30000, healthTimeoutMs = 1500 }) {
  const base = String(url).replace(/\/+$/, '');
  let loaded = false;

  /** @param {string} path @param {RequestInit} init @param {number} ms */
  async function call(path, init, ms) {
    try {
      return await fetchImpl(base + path, { ...init, signal: AbortSignal.timeout(ms) });
    } catch (err) {
      const e = /** @type {any} */ (err);
      if (e?.name === 'TimeoutError') throw new SttError('timeout', `STT từ xa "${id}" quá ${ms} ms.`);
      throw modelUnavailable('tunnel_down', `Không kết nối được STT từ xa "${id}" tại ${base} (SSH tunnel chưa mở?).`);
    }
  }

  const provider = {
    kind: 'remote',
    id,
    get loaded() { return loaded; },

    /** Kiểm /healthz; không sẵn sàng ⇒ `model_unavailable` kèm lý do. */
    async loadModel(requested = id) {
      if (requested !== id) throw modelUnavailable('unknown_model', `Provider từ xa này phục vụ "${id}", không phải "${requested}".`);
      loaded = false;
      if (!token) throw modelUnavailable('missing_token', `Chưa đặt VFLOW_REMOTE_TOKEN cho STT từ xa "${id}".`);
      const res = await call('/healthz', { headers: { authorization: `Bearer ${token}` } }, healthTimeoutMs);
      let body = null;
      try { body = await res.json(); } catch { /* xử lý ở dưới */ }
      if (!res.ok || !body || body.ok !== true || body.loaded === false) {
        const reason = typeof body?.reason === 'string' ? body.reason : `http_${res.status}`;
        throw modelUnavailable(reason, `STT từ xa "${id}" chưa sẵn sàng (${reason}).`);
      }
      loaded = true;
      return { id };
    },

    /**
     * @param {{ pcm: Int16Array|Float32Array, sampleRate: number }} input
     * @returns {Promise<{ text: string, audio_ms: number, stt_ms: number }>}
     */
    async transcribe({ pcm, sampleRate }) {
      if (!token) throw modelUnavailable('missing_token', `Chưa đặt VFLOW_REMOTE_TOKEN cho STT từ xa "${id}".`);
      const t0 = performance.now();
      const f = toFloat32(pcm);
      const pcm16 = toInt16(sampleRate === TARGET_RATE ? f : resample(f, sampleRate, TARGET_RATE));
      const body = new Uint8Array(pcm16.buffer, pcm16.byteOffset, pcm16.byteLength);
      const res = await call('/v1/transcribe?lang=vi', {
        method: 'POST',
        headers: {
          authorization: `Bearer ${token}`,
          'content-type': `audio/L16; rate=${TARGET_RATE}; channels=1`,
        },
        body,
      }, timeoutMs);
      /** @type {any} */
      let json = null;
      try { json = await res.json(); } catch { /* xử lý ở dưới */ }
      if (!res.ok) {
        const code = json?.error?.code;
        if (code === 'unauthorized') {
          // Lỗi token phía máy chủ từ xa, không phải lỗi của client gọi engine.
          throw modelUnavailable('remote_unauthorized', `STT từ xa "${id}" từ chối token (kiểm VFLOW_REMOTE_TOKEN).`);
        }
        if (PASS_THROUGH.has(code)) {
          const e = new SttError(code, `STT từ xa "${id}": ${json?.error?.message ?? code}`,
            code === 'model_unavailable' ? { reason: 'remote_model_unavailable' } : {});
          throw e;
        }
        throw new SttError('internal', `STT từ xa "${id}" lỗi HTTP ${res.status}${code ? ` (${code})` : ''}.`);
      }
      if (!json || typeof json.text !== 'string') {
        throw new SttError('internal', `STT từ xa "${id}" trả phản hồi không hợp lệ (thiếu "text").`);
      }
      loaded = true;
      return {
        text: json.text.replace(/\s+/g, ' ').trim(),
        audio_ms: durationMs(pcm16.length, TARGET_RATE),
        stt_ms: Math.round(performance.now() - t0),
      };
    },
  };
  return provider;
}
