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
import { transcribeChunked, DEFAULT_CHUNK_SECONDS, DEFAULT_OVERLAP_SECONDS } from './chunked.js';

/** Audio dài hơn ngần này mới xử lý theo đoạn (contract/engine-api.md mục "Ghi âm dài") — dictation
 * ngắn bình thường (đa số < 30s) đi thẳng qua đường một lần như trước, không thêm chi phí/độ trễ. */
const CHUNK_THRESHOLD_SECONDS = 35;

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
 * Model transducer (zipformer) xuất token chữ HOA (bảng token không phân biệt hoa/thường) ⇒ đổi về
 * chữ thường để dùng được khi đọc chính tả. Whisper/SenseVoice đã tự trả hoa/thường và dấu câu
 * đúng (như bản gốc Whisper) cho MỌI ngôn ngữ kể cả tiếng Việt — không được đụng vào, kể cả khi
 * `language` yêu cầu là "vi" (bug đã gặp: khoá theo `language` thay vì theo loại engine làm mất
 * hoa/dấu câu Whisper trả cho câu tiếng Việt).
 * @param {string} text
 * @param {boolean} rawTransducer `true` khi văn bản đến từ engine transducer thô (zipformer).
 */
export function normalizeModelText(text, rawTransducer = true) {
  const t = String(text ?? '').replace(/\s+/g, ' ').trim();
  return rawTransducer ? t.toLocaleLowerCase('vi') : t;
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
      /** @type {any} */
      const modelConfig = { tokens: files.tokens, numThreads, provider: 'cpu', debug: 0 };
      if (s.engine === 'offline-transducer' || s.engine === 'online-transducer') {
        modelConfig.transducer = { encoder: files.encoder, decoder: files.decoder, joiner: files.joiner };
      } else if (s.engine === 'whisper') {
        // sherpa-onnx (OfflineWhisperGreedySearchDecoder) coi "auto" là MỘT MÃ NGÔN NGỮ không hợp
        // lệ (chỉ nhận chuỗi rỗng để tự nhận ngôn ngữ, hoặc một mã ISO có trong lang2id của model)
        // ⇒ nếu truyền "auto" addon gọi SHERPA_ONNX_EXIT và TẮT LUÔN tiến trình Node, không ném lỗi
        // JS bắt được. Chuỗi rỗng để Whisper tự nhận ngôn ngữ MỖI LẦN giải mã theo chính audio đó
        // (không phải một cấu hình cố định lúc tải model) — đúng cho mọi yêu cầu vi/en/auto.
        modelConfig.whisper = { encoder: files.encoder, decoder: files.decoder, language: '', task: 'transcribe' };
      } else if (s.engine === 'sense-voice') {
        modelConfig.senseVoice = { model: files.model, language: 'auto', useInverseTextNormalization: 1 };
      }
      const featConfig = { sampleRate: TARGET_RATE, featureDim: 80 };
      try {
        recognizer = s.engine === 'online-transducer'
          ? new lib.OnlineRecognizer({ featConfig, modelConfig, decodingMethod: 'greedy_search', enableEndpoint: 0 })
          : await lib.OfflineRecognizer.createAsync({ featConfig, modelConfig, decodingMethod: 'greedy_search' });
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
     * @param {{ pcm: Int16Array|Float32Array, sampleRate: number, language?: string }} input
     * @returns {Promise<{ text: string, audio_ms: number, stt_ms: number }>}
     */
    async transcribe({ pcm, sampleRate, language = 'vi' }) {
      if (!recognizer || !spec) throw modelUnavailable('not_loaded', 'Chưa tải model (gọi loadModel trước).');
      // Chốt chặn thứ hai (createStt() đã kiểm năng lực ngôn ngữ trước khi gọi tới đây); giữ ở đây
      // để provider vẫn an toàn nếu được gọi trực tiếp, không qua stt.transcribe().
      if (language === 'auto') {
        if (spec.autoDetect !== true) throw new SttError('bad_request', `Model "${spec.id}" không hỗ trợ tự nhận ngôn ngữ (auto). Hãy chọn ngôn ngữ cụ thể hoặc đổi model.`);
      } else if (!(spec.languages ?? ['vi']).includes(language)) {
        throw new SttError('bad_request', `Model "${spec.id}" không hỗ trợ ngôn ngữ "${language}". Hãy đổi model.`);
      }
      if (spec.engine === 'online-transducer') {
        const s = provider.createSession();
        s.accept(pcm, sampleRate);
        return s.finish();
      }
      const t0 = performance.now();
      const samples = prepare(pcm, sampleRate);
      const decodeOnce = async (chunk) => {
        const stream = recognizer.createStream();
        stream.acceptWaveform({ samples: chunk, sampleRate: TARGET_RATE });
        const result = await recognizer.decodeAsync(stream);
        return normalizeModelText(result?.text, spec.engine === 'offline-transducer');
      };
      const text = samples.length > CHUNK_THRESHOLD_SECONDS * TARGET_RATE
        ? await transcribeChunked(samples, TARGET_RATE, decodeOnce, { chunkSeconds: DEFAULT_CHUNK_SECONDS, overlapSeconds: DEFAULT_OVERLAP_SECONDS })
        : await decodeOnce(samples);
      return {
        text,
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
