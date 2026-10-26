/**
 * Provider STT cục bộ dùng `sherpa-onnx-node` (CPU).
 *   const p = createLocalProvider({ home });
 *   await p.loadModel('zipformer-vi-30m');
 *   const { text, audio_ms, stt_ms } = await p.transcribe({ pcm, sampleRate });
 * Bản streaming (`zipformer-vi-30m-streaming`) có thêm `createSession({ onPartial })`.
 */
import os from 'node:os';
import { createRequire } from 'node:module';
import { performance } from 'node:perf_hooks';
import { LOCAL_MODELS } from './registry.js';
import { resolveModelFiles } from './models.js';
import { SttError, modelUnavailable } from './errors.js';
import { TARGET_RATE, durationMs, resample, toFloat32 } from './audio.js';

const require = createRequire(import.meta.url);

/** Nạp addon gốc; lỗi (thiếu gói/thiếu bản cho nền tảng) ⇒ `model_unavailable`. */
export function loadSherpa() {
  try {
    return require('sherpa-onnx-node');
  } catch (err) {
    throw modelUnavailable(
      'runtime_missing',
      `Không nạp được sherpa-onnx-node trên ${process.platform}-${process.arch}: ${String(/** @type {Error} */ (err).message).split('\n')[0]}`,
      err,
    );
  }
}

/**
 * Model zipformer-vi xuất token chữ HOA (bảng token không phân biệt hoa/thường).
 * Đổi về chữ thường để dùng được khi đọc chính tả; không đổi gì khác.
 * @param {string} text
 */
export function normalizeModelText(text) {
  const t = String(text ?? '').replace(/\s+/g, ' ').trim();
  return t.toLocaleLowerCase('vi');
}

const defaultThreads = () => Math.max(1, Math.min(4, Math.floor(os.availableParallelism() / 2)));

/** @param {Float32Array|Int16Array} pcm @param {number} sampleRate */
function prepare(pcm, sampleRate) {
  if (!Number.isInteger(sampleRate) || sampleRate <= 0) {
    throw new SttError('bad_audio', `sampleRate không hợp lệ: ${sampleRate}`);
  }
  const f = toFloat32(pcm);
  return sampleRate === TARGET_RATE ? f : resample(f, sampleRate, TARGET_RATE);
}

/**
 * @param {{ home: string, numThreads?: number, sherpa?: () => any }} opts
 */
export function createLocalProvider({ home, numThreads = defaultThreads(), sherpa = loadSherpa }) {
  /** @type {any} */ let recognizer = null;
  /** @type {import('./registry.js').LocalModelSpec|null} */ let spec = null;
  /** @type {number|null} */ let loadMs = null;

  const provider = {
    kind: 'local',
    get id() { return spec?.id ?? null; },
    get loaded() { return recognizer !== null; },
    get loadMs() { return loadMs; },

    /** @param {string} id */
    async loadModel(id) {
      const s = LOCAL_MODELS.find((m) => m.id === id);
      if (!s) throw modelUnavailable('unknown_model', `Không có model cục bộ "${id}".`);
      const { files } = await resolveModelFiles(home, id);
      const lib = sherpa();
      const t0 = performance.now();
      const modelConfig = {
        transducer: { encoder: files.encoder, decoder: files.decoder, joiner: files.joiner },
        tokens: files.tokens, numThreads, provider: 'cpu', debug: 0,
      };
      const featConfig = { sampleRate: TARGET_RATE, featureDim: 80 };
      try {
        recognizer = s.engine === 'offline-transducer'
          ? await lib.OfflineRecognizer.createAsync({ featConfig, modelConfig, decodingMethod: 'greedy_search' })
          : new lib.OnlineRecognizer({ featConfig, modelConfig, decodingMethod: 'greedy_search', enableEndpoint: 0 });
      } catch (err) {
        recognizer = null;
        throw modelUnavailable('load_failed', `Không tải được model "${id}": ${/** @type {Error} */ (err).message}`, err);
      }
      if (!recognizer) throw modelUnavailable('load_failed', `Không tải được model "${id}".`);
      spec = s;
      loadMs = Math.round(performance.now() - t0);
      return { id, load_ms: loadMs };
    },

    /**
     * @param {{ pcm: Int16Array|Float32Array, sampleRate: number }} input
     * @returns {Promise<{ text: string, audio_ms: number, stt_ms: number }>}
     */
    async transcribe({ pcm, sampleRate }) {
      if (!recognizer || !spec) throw modelUnavailable('not_loaded', 'Chưa tải model (gọi loadModel trước).');
      if (spec.engine === 'online-transducer') {
        const s = provider.createSession();
        s.accept(pcm, sampleRate);
        return s.finish();
      }
      const t0 = performance.now();
      const samples = prepare(pcm, sampleRate);
      const stream = recognizer.createStream();
      stream.acceptWaveform({ samples, sampleRate: TARGET_RATE });
      const result = await recognizer.decodeAsync(stream);
      return {
        text: normalizeModelText(result?.text),
        audio_ms: durationMs(samples.length, TARGET_RATE),
        stt_ms: Math.round(performance.now() - t0),
      };
    },

    /**
     * Phiên streaming: đẩy âm thanh từng đoạn, nhận chữ tạm qua `onPartial`.
     * @param {{ onPartial?: (ev: { text: string, audio_ms: number }) => void }} [opts]
     */
    createSession({ onPartial } = {}) {
      if (!recognizer || !spec) throw modelUnavailable('not_loaded', 'Chưa tải model (gọi loadModel trước).');
      if (spec.engine !== 'online-transducer') {
        throw new SttError('bad_request', `Model "${spec.id}" không hỗ trợ streaming.`);
      }
      const rec = recognizer;
      const stream = rec.createStream();
      let total = 0;
      let busyMs = 0;
      let last = '';
      let done = false;
      const pump = () => {
        while (rec.isReady(stream)) rec.decode(stream);
        const text = normalizeModelText(rec.getResult(stream).text);
        if (text !== last) {
          last = text;
          onPartial?.({ text, audio_ms: durationMs(total, TARGET_RATE) });
        }
      };
      return {
        /** @param {Int16Array|Float32Array} pcm @param {number} sampleRate */
        accept(pcm, sampleRate) {
          if (done) throw new SttError('bad_request', 'Phiên streaming đã kết thúc.');
          const t0 = performance.now();
          const samples = prepare(pcm, sampleRate);
          total += samples.length;
          stream.acceptWaveform({ samples, sampleRate: TARGET_RATE });
          pump();
          busyMs += performance.now() - t0;
        },
        /** @returns {{ text: string, audio_ms: number, stt_ms: number }} */
        finish() {
          if (done) throw new SttError('bad_request', 'Phiên streaming đã kết thúc.');
          done = true;
          const t0 = performance.now();
          // Đệm 0,5 s im lặng để encoder xả nốt khung cuối (như ví dụ của sherpa-onnx).
          stream.acceptWaveform({ samples: new Float32Array(TARGET_RATE / 2), sampleRate: TARGET_RATE });
          stream.inputFinished();
          pump();
          busyMs += performance.now() - t0;
          return { text: last, audio_ms: durationMs(total, TARGET_RATE), stt_ms: Math.round(busyMs) };
        },
      };
    },
  };
  return provider;
}
