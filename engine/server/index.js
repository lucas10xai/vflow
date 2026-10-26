/**
 * HTTP cục bộ của engine theo contract/engine-api.md (node:http, không framework).
 * - Chỉ nghe 127.0.0.1; kiểm Host (chặn DNS rebinding); không CORS; Bearer token.
 * - Âm thanh chỉ nằm trong RAM; log chỉ có id, thời lượng, thời gian, mã lỗi.
 */
import http from 'node:http';
import { randomBytes } from 'node:crypto';
import { performance } from 'node:perf_hooks';
import { decodeAudio, durationMs, isSilence } from '../stt/audio.js';
import { tokenMatches } from './token.js';

export const VERSION = '0.1.0';
export const DEFAULT_PORT = 7611;
export const MAX_AUDIO_SECONDS = 120;
/** Trần byte thân âm thanh (đọc trong RAM); thời lượng thật kiểm sau khi giải mã. */
export const MAX_AUDIO_BYTES = 48 * 1024 * 1024;
const MAX_JSON_BYTES = 4 * 1024 * 1024;
const MAX_DICTIONARY_ENTRIES = 5000;
const MODES = new Set(['normal', 'clean', 'email', 'auto']);
const LANGS = new Set(['vi', 'auto']);

const STATUS = {
  unauthorized: 401, bad_audio: 400, bad_request: 400, model_unavailable: 503,
  timeout: 504, payload_too_large: 413, internal: 500,
};

class HttpError extends Error {
  /** @param {keyof typeof STATUS} code @param {string} message @param {number} [status] */
  constructor(code, message, status) {
    super(message);
    this.code = code;
    this.status = status ?? STATUS[code];
  }
}

/** Lỗi từ engine/stt hoặc engine/post ⇒ mã contract. */
function toHttpError(err, fallbackCode = 'internal') {
  if (err instanceof HttpError) return err;
  const code = /** @type {any} */ (err)?.code;
  if (typeof code === 'string' && code in STATUS) {
    const reason = /** @type {any} */ (err).reason;
    const msg = String(/** @type {any} */ (err).message || code);
    return new HttpError(/** @type {any} */ (code), reason && !msg.includes(reason) ? `${msg} (lý do: ${reason})` : msg);
  }
  if (fallbackCode === 'bad_request' && ['ValidationError', 'TypeError', 'RangeError', 'SyntaxError'].includes(err?.name)) {
    return new HttpError('bad_request', String(err.message || 'Dữ liệu không hợp lệ.'));
  }
  return new HttpError('internal', 'Lỗi nội bộ của engine.');
}

/** @param {http.ServerResponse} res @param {number} status @param {unknown} body */
function sendJson(res, status, body) {
  const data = Buffer.from(JSON.stringify(body));
  res.writeHead(status, {
    'content-type': 'application/json; charset=utf-8',
    'content-length': data.length,
    'cache-control': 'no-store',
    'x-content-type-options': 'nosniff',
  });
  res.end(data);
}

/**
 * Đọc thân yêu cầu vào RAM với trần byte.
 * @param {http.IncomingMessage} req @param {number} limit
 * @returns {Promise<Uint8Array>}
 */
function readBody(req, limit) {
  return new Promise((resolve, reject) => {
    const declared = Number(req.headers['content-length']);
    if (Number.isFinite(declared) && declared > limit) {
      reject(new HttpError('payload_too_large', `Thân yêu cầu quá lớn (tối đa ${limit} byte).`));
      req.resume();
      return;
    }
    /** @type {Buffer[]} */
    const chunks = [];
    let size = 0;
    let failed = false;
    req.on('data', (c) => {
      if (failed) return;
      size += c.length;
      if (size > limit) {
        failed = true;
        chunks.length = 0;
        reject(new HttpError('payload_too_large', `Thân yêu cầu quá lớn (tối đa ${limit} byte).`));
        return;
      }
      chunks.push(c);
    });
    req.on('end', () => { if (!failed) resolve(new Uint8Array(Buffer.concat(chunks))); });
    req.on('error', (e) => { if (!failed) { failed = true; reject(e); } });
  });
}

/** @param {http.IncomingMessage} req */
async function readJson(req) {
  const bytes = await readBody(req, MAX_JSON_BYTES);
  try {
    return JSON.parse(Buffer.from(bytes).toString('utf8'));
  } catch {
    throw new HttpError('bad_request', 'Thân yêu cầu không phải JSON hợp lệ.');
  }
}

const newId = () => `tr_${Date.now().toString(36)}${randomBytes(6).toString('hex')}`;

/**
 * Hàng đợi tuần tự: mỗi lúc chỉ một lần nhận dạng (giữ RAM/CPU ổn định).
 * @returns {<T>(fn: () => Promise<T>) => Promise<T>}
 */
function serialQueue() {
  let tail = Promise.resolve();
  return (fn) => {
    const run = tail.then(fn, fn);
    tail = run.then(() => {}, () => {});
    return run;
  };
}

/**
 * @typedef {{
 *   process: (input: { textRaw: string, mode: string, app?: string }) => Promise<{ text: string, applied: any[], rewrite: { used: boolean, error: string|null } }>,
 *   dictionary: { list: () => any, replaceAll: (entries: any[]) => any, learnCorrection: (x: { before: string, after: string }) => any },
 * }} PostProcessor
 */

/**
 * @param {{
 *   stt: ReturnType<typeof import('../stt/index.js').createStt>,
 *   post: PostProcessor,
 *   token: string,
 *   log?: (entry: Record<string, unknown>) => void,
 *   maxAudioSeconds?: number,
 *   requestTimeoutMs?: number,
 * }} opts
 */
export function createServer({ stt, post, token, log = () => {}, maxAudioSeconds = MAX_AUDIO_SECONDS, requestTimeoutMs = 60000 }) {
  if (!token) throw new Error('createServer cần token');
  const enqueue = serialQueue();
  /** @type {http.Server} */
  const server = http.createServer(handle);
  server.requestTimeout = requestTimeoutMs + 5000;
  server.headersTimeout = 10000;

  /** @param {http.IncomingMessage} req @param {http.ServerResponse} res */
  async function handle(req, res) {
    const started = performance.now();
    /** @type {Record<string, unknown>} */
    const entry = { method: req.method, route: '' };
    try {
      const port = /** @type {import('node:net').AddressInfo} */ (server.address())?.port;
      const host = String(req.headers.host ?? '').toLowerCase();
      if (host !== `127.0.0.1:${port}` && host !== `localhost:${port}`) {
        throw new HttpError('unauthorized', 'Host không hợp lệ (chỉ nhận 127.0.0.1 hoặc localhost).', 403);
      }
      // Engine không phục vụ trình duyệt: có Origin ⇒ từ chối, và không bao giờ gửi header CORS.
      if (req.headers.origin !== undefined) {
        throw new HttpError('unauthorized', 'Không nhận yêu cầu từ trình duyệt (có header Origin).', 403);
      }
      const url = new URL(req.url ?? '/', `http://127.0.0.1:${port}`);
      entry.route = url.pathname;

      if (url.pathname === '/healthz') {
        if (req.method !== 'GET') throw new HttpError('bad_request', 'Chỉ hỗ trợ GET.', 405);
        sendJson(res, 200, { ok: true, version: VERSION, models: await stt.status() });
        entry.status = 200;
        return;
      }

      const auth = String(req.headers.authorization ?? '');
      const m = /^Bearer\s+(\S+)\s*$/i.exec(auth);
      if (!m || !tokenMatches(m[1], token)) throw new HttpError('unauthorized', 'Thiếu hoặc sai token.');

      if (url.pathname === '/v1/transcribe') {
        if (req.method !== 'POST') throw new HttpError('bad_request', 'Chỉ hỗ trợ POST.', 405);
        await transcribe(req, res, url, entry);
        return;
      }
      if (url.pathname === '/v1/dictionary') {
        if (req.method === 'GET') {
          sendJson(res, 200, await callPost(() => post.dictionary.list()));
        } else if (req.method === 'PUT') {
          const body = await readJson(req);
          if (!body || typeof body !== 'object' || !Array.isArray(body.entries)) {
            throw new HttpError('bad_request', 'Cần JSON dạng {"entries": [...]}.');
          }
          if (body.entries.length > MAX_DICTIONARY_ENTRIES) {
            throw new HttpError('bad_request', `Tối đa ${MAX_DICTIONARY_ENTRIES} mục từ điển.`);
          }
          await callPost(() => post.dictionary.replaceAll(body.entries));
          sendJson(res, 200, await callPost(() => post.dictionary.list()));
        } else {
          throw new HttpError('bad_request', 'Chỉ hỗ trợ GET hoặc PUT.', 405);
        }
        entry.status = 200;
        return;
      }
      if (url.pathname === '/v1/corrections') {
        if (req.method !== 'POST') throw new HttpError('bad_request', 'Chỉ hỗ trợ POST.', 405);
        const body = await readJson(req);
        if (!body || typeof body.before !== 'string' || typeof body.after !== 'string') {
          throw new HttpError('bad_request', 'Cần JSON dạng {"before": "…", "after": "…"}.');
        }
        sendJson(res, 200, await callPost(() => post.dictionary.learnCorrection({ before: body.before, after: body.after })));
        entry.status = 200;
        return;
      }
      throw new HttpError('bad_request', 'Không có đường dẫn này.', 404);
    } catch (err) {
      const e = toHttpError(err);
      entry.status = e.status;
      entry.code = e.code;
      // Thân yêu cầu chưa đọc hết (vd. quá lớn) ⇒ đóng kết nối sau khi trả lỗi.
      if (!req.complete) res.setHeader('connection', 'close');
      if (!res.headersSent) sendJson(res, e.status, { error: { code: e.code, message: e.message } });
      else res.destroy();
    } finally {
      entry.total_ms = Math.round(performance.now() - started);
      log(entry);
    }
  }

  /** Gọi engine/post; lỗi kiểm dữ liệu ⇒ bad_request, còn lại ⇒ internal. */
  async function callPost(fn) {
    try {
      return await fn();
    } catch (err) {
      throw toHttpError(err, 'bad_request');
    }
  }

  /**
   * @param {http.IncomingMessage} req @param {http.ServerResponse} res @param {URL} url
   * @param {Record<string, unknown>} entry
   */
  async function transcribe(req, res, url, entry) {
    const id = newId();
    entry.id = id;
    const q = url.searchParams;
    const model = q.get('model') || stt.defaultModel;
    const mode = q.get('mode') || 'normal';
    const lang = q.get('lang') || 'vi';
    const app = q.get('app') || undefined;
    if (!MODES.has(mode)) throw new HttpError('bad_request', `mode không hợp lệ: ${mode}`);
    if (!LANGS.has(lang)) throw new HttpError('bad_request', `lang không hợp lệ: ${lang}`);
    if (!stt.isKnown(model)) throw new HttpError('bad_request', `Không có model "${model}".`);
    entry.model = model;

    let bytes = await readBody(req, MAX_AUDIO_BYTES);
    const tBody = performance.now();
    let wave = decodeAudio(bytes, req.headers['content-type']);
    bytes = new Uint8Array(0); // bỏ tham chiếu tới thân yêu cầu sớm
    const audioMs = durationMs(wave.samples.length, wave.sampleRate);
    entry.audio_ms = audioMs;
    if (audioMs > maxAudioSeconds * 1000) {
      throw new HttpError('payload_too_large', `Âm thanh dài ${(audioMs / 1000).toFixed(1)} s, vượt giới hạn ${maxAudioSeconds} s.`);
    }

    const work = enqueue(async () => {
      // Kiểm model trước cả khi im lặng: model hỏng phải báo lỗi, không trả "im lặng" giả.
      await stt.ensure(model);
      if (isSilence(wave.samples, wave.sampleRate)) return { silent: true, sttMs: 0, textRaw: '' };
      const r = await stt.transcribe(model, { pcm: wave.samples, sampleRate: wave.sampleRate });
      return { silent: r.text === '', sttMs: r.stt_ms, textRaw: r.text };
    });
    const r = await withTimeout(work, requestTimeoutMs, 'Nhận dạng quá thời gian.');
    wave = { samples: new Float32Array(0), sampleRate: wave.sampleRate };
    entry.stt_ms = r.sttMs;

    /** @type {any} */
    let postOut = { text: '', applied: [], rewrite: { used: false, error: null } };
    let postMs = 0;
    if (!r.silent) {
      const t0 = performance.now();
      postOut = await withTimeout(
        Promise.resolve().then(() => post.process({ textRaw: r.textRaw, mode, ...(app ? { app } : {}) })),
        requestTimeoutMs, 'Hậu xử lý quá thời gian.',
      );
      postMs = Math.round(performance.now() - t0);
      if (!postOut || typeof postOut.text !== 'string') throw new HttpError('internal', 'Hậu xử lý trả kết quả không hợp lệ.');
    }
    const total = Math.round(performance.now() - tBody);
    /** @type {Record<string, unknown>} */
    const body = {
      // Chế độ thực sự đã áp (auto đã phân giải) nếu hậu xử lý báo; không thì chế độ yêu cầu.
      id, model, mode: typeof postOut.mode === 'string' && MODES.has(postOut.mode) ? postOut.mode : mode, language: 'vi',
      text_raw: r.textRaw,
      text: postOut.text,
      audio_ms: audioMs,
      timings_ms: { stt: r.sttMs, post: postMs, total },
      rtf: audioMs > 0 ? Math.round((r.sttMs / audioMs) * 1000) / 1000 : 0,
      post: {
        applied: Array.isArray(postOut.applied) ? postOut.applied : [],
        rewrite: postOut.rewrite ?? { used: false, error: null },
      },
    };
    if (r.silent) body.silence = true;
    sendJson(res, 200, body);
    entry.status = 200;
  }

  return server;
}

/**
 * @template T
 * @param {Promise<T>} p @param {number} ms @param {string} message
 * @returns {Promise<T>}
 */
function withTimeout(p, ms, message) {
  /** @type {NodeJS.Timeout|undefined} */
  let timer;
  const t = new Promise((_, reject) => { timer = setTimeout(() => reject(new HttpError('timeout', message)), ms); });
  return Promise.race([p, t]).finally(() => clearTimeout(timer));
}

/**
 * Nghe trên 127.0.0.1 (không bao giờ 0.0.0.0).
 * @param {http.Server} server @param {number} port
 * @returns {Promise<number>} cổng thật
 */
export function listen(server, port) {
  return new Promise((resolve, reject) => {
    server.once('error', reject);
    server.listen(port, '127.0.0.1', () => {
      server.off('error', reject);
      resolve(/** @type {import('node:net').AddressInfo} */ (server.address()).port);
    });
  });
}
