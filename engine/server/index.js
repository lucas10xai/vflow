/**
 * HTTP cục bộ của engine theo contract/engine-api.md (node:http, không framework).
 * - Chỉ nghe 127.0.0.1; kiểm Host (chặn DNS rebinding); không CORS; Bearer token.
 * - Âm thanh chỉ nằm trong RAM; log chỉ có id, thời lượng, thời gian, mã lỗi.
 */
import http from 'node:http';
import { readFileSync, writeFileSync, existsSync } from 'node:fs';
import { basename, join } from 'node:path';
import { randomBytes } from 'node:crypto';
import { performance } from 'node:perf_hooks';
import { decodeAudio, durationMs, isSilence } from '../stt/audio.js';
import { applyAutoGain } from '../stt/gain.js';
import { tokenMatches } from './token.js';
import {
  buildExport, validateImportPackage, mergeDictionary, mergeSnippets, mergeHistory,
  MAX_IMPORT_BYTES,
} from '../post/exportimport.js';
import { buildDiagnostics } from '../post/diagnostics.js';

export const VERSION = '0.1.0';
export const DEFAULT_PORT = 7611;
/** Ghi âm dài (item 10, contract/engine-api.md mục "Ghi âm dài"): tối đa 20 phút. */
export const MAX_AUDIO_SECONDS = 1200;
/** Trần byte thân âm thanh (đọc trong RAM); thời lượng thật kiểm sau khi giải mã.
 * 16 kHz mono 16-bit × 1200s ≈ 38,4 MB — 48 MB đã đủ dư; định dạng nặng hơn (vd WAV 48kHz stereo)
 * ở cùng độ dài sẽ tự bị chặn ở đây (payload_too_large) trước khi chạm MAX_AUDIO_SECONDS. */
export const MAX_AUDIO_BYTES = 48 * 1024 * 1024;
const MAX_RECENT_ERRORS = 50;
const MAX_PARTIAL_AUDIO_SECONDS = 30;
const MAX_JSON_BYTES = 4 * 1024 * 1024;
/** Trần JSON cho các route cài đặt/snippets/command (nhỏ hơn: không mang âm thanh hay danh sách lớn). */
const MAX_SETTINGS_JSON_BYTES = 1 * 1024 * 1024;
const MAX_DICTIONARY_ENTRIES = 5000;
const MAX_SNIPPET_ENTRIES = 500;
/** Trần ký tự mỗi trường của POST /v1/command (contract/engine-api.md, mục Command Mode). */
const COMMAND_FIELD_MAX = 20000;
/** Giá trị query `mode` client được gửi (contract/engine-api.md, mục Chế độ: gồm cả tidy/dev,
 * không chỉ qua auto+app). */
const MODES = new Set(['normal', 'clean', 'email', 'tidy', 'dev', 'auto']);
/** Chế độ thật có thể xuất hiện trong post.mode của phản hồi: `auto` đã được post/index.js (E1a)
 * phân giải thành một trong các chế độ cụ thể này (không bao giờ còn là "auto"). */
const RESOLVED_MODES = new Set(['normal', 'clean', 'email', 'tidy', 'dev']);
const LANGS = new Set(['vi', 'auto']);

const STATUS = {
  unauthorized: 401, bad_audio: 400, bad_request: 400, model_unavailable: 503,
  timeout: 504, payload_too_large: 413, internal: 500,
  rewrite_unavailable: 503, cloud_disabled: 503,
  busy: 429,
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
 *
 * Khi `Content-Length` tự khai đã vượt trần, client coi như đã tự thừa nhận vi phạm nên trả lỗi
 * ngay (không cần đợi — client có thể không gửi đủ số byte đã khai, chờ sẽ treo tới hết
 * `requestTimeout`). Khi KHÔNG biết trước độ dài (chunked) và việc vượt trần chỉ phát hiện được
 * lúc đang đọc, phải rút hết phần thân còn lại (có giới hạn trên) RỒI MỚI báo lỗi: trả 413 và đóng
 * kết nối khi client còn đang gửi dở (ví dụ do backpressure trên loopback) khiến client nhận
 * ECONNRESET/EPIPE ngẫu nhiên — không phải lỗi logic, mà do đóng socket trước khi đọc hết dữ liệu
 * đang bay trên dây. Rút cho hết rồi đóng tránh hẳn race này.
 * @param {http.IncomingMessage} req @param {number} limit
 * @returns {Promise<Uint8Array>}
 */
function readBody(req, limit) {
  return new Promise((resolve, reject) => {
    const tooLarge = () => new HttpError('payload_too_large', `Thân yêu cầu quá lớn (tối đa ${limit} byte).`);
    const declared = Number(req.headers['content-length']);
    if (Number.isFinite(declared) && declared > limit) {
      reject(tooLarge());
      req.resume();
      return;
    }
    /** @type {Buffer[]} */
    const chunks = [];
    let size = 0;
    let overflowed = false;
    let settled = false;
    const finish = (fn) => { if (!settled) { settled = true; fn(); } };
    // Rút phần vượt trần có giới hạn trên: không buffer vô hạn nếu client chunked gửi mãi.
    const DRAIN_LIMIT = Math.max(limit * 4, 8 * 1024 * 1024);
    let drained = 0;
    req.on('data', (c) => {
      if (overflowed) {
        drained += c.length;
        if (drained > DRAIN_LIMIT) { finish(() => reject(tooLarge())); req.destroy(); }
        return;
      }
      size += c.length;
      if (size > limit) { overflowed = true; chunks.length = 0; drained = size; return; }
      chunks.push(c);
    });
    req.on('end', () => finish(() => (overflowed ? reject(tooLarge()) : resolve(new Uint8Array(Buffer.concat(chunks))))));
    req.on('error', (e) => finish(() => (overflowed ? reject(tooLarge()) : reject(e))));
    req.on('close', () => finish(() => reject(overflowed ? tooLarge() : new HttpError('bad_request', 'Kết nối đóng giữa chừng khi đang đọc thân yêu cầu.'))));
  });
}

/** @param {http.IncomingMessage} req @param {number} [limit] */
async function readJson(req, limit = MAX_JSON_BYTES) {
  const bytes = await readBody(req, limit);
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
 *   process: (input: { textRaw: string, mode: string, app?: string }) => Promise<{ text: string, mode?: string, applied: any[], rewrite: { used: boolean, error: string|null }, actions?: string[] }>,
 *   command?: (input: { instruction: string, selection: string, context: string, app?: string }) => Promise<{ text: string, kind: 'edit'|'draft', timings_ms?: Record<string, number> }>,
 *   dictionary: { list: () => any, replaceAll: (entries: any[]) => any, learnCorrection: (x: { before: string, after: string }) => any },
 * }} PostProcessor
 * @typedef {{ list: () => any, replaceAll: (entries: any[]) => any, expand?: (text: string) => any }} SnippetStore
 * @typedef {{ get: () => any, update: (patch: any) => any }} SettingsStore
 */

/** Dùng khi chưa truyền snippets/settings (ví dụ test cũ chưa cần hai route này). */
const NOOP_SNIPPETS = {
  list: () => ({ entries: [] }),
  replaceAll: () => { throw new HttpError('internal', 'Chưa cấu hình snippets cho engine này.'); },
  expand: (text) => ({ text, applied: [], matched: false }),
};
const NOOP_SETTINGS = {
  get: () => ({
    cloud_llm: true, llm_model: null, llm_timeout_ms: 3500, actions_enabled: true,
    stats_enabled: true, app_rules: {}, voice_punctuation: true, tone: 'neutral',
    whisper_mode: false, learn_from_edits: true, live_preview: true, silence_stop_seconds: 0,
  }),
  update: () => { throw new HttpError('internal', 'Chưa cấu hình settings cho engine này.'); },
};
/** Dùng khi chưa truyền stats (ví dụ test cũ chưa cần route /v1/stats). */
const NOOP_STATS = {
  record: () => {},
  summary: () => { throw new HttpError('internal', 'Chưa cấu hình thống kê cho engine này.'); },
  clear: () => { throw new HttpError('internal', 'Chưa cấu hình thống kê cho engine này.'); },
  daysCount: () => 0,
  exportDays: () => ({ backfilled: true, days: {} }),
  importDays: () => 0,
};

/**
 * @typedef {{ record: (args: {text:string, audioMs?:number, app?:string|null}) => void,
 *             summary: (args?: {weeks?:number}) => any, clear: () => {ok:boolean},
 *             daysCount: () => number, exportDays: () => {backfilled:boolean, days:object},
 *             importDays: (days: object, mode: 'merge'|'replace') => number }} StatsStore
 */

/**
 * @param {{
 *   stt: ReturnType<typeof import('../stt/index.js').createStt>,
 *   post: PostProcessor,
 *   token: string,
 *   snippets?: SnippetStore,
 *   settings?: SettingsStore,
 *   stats?: StatsStore,
 *   home?: string,
 *   log?: (entry: Record<string, unknown>) => void,
 *   maxAudioSeconds?: number,
 *   requestTimeoutMs?: number,
 * }} opts
 *   home: thư mục $VFLOW_HOME — dùng cho GET /v1/diagnostics (đếm history.jsonl, rút gọn đường
 *   dẫn) và GET /v1/export (đọc history.jsonl khi include_history=1) / POST /v1/import (ghi lại).
 *   Vắng mặt ⇒ các phần liên quan tới history trong export/import/diagnostics coi như rỗng.
 */
export function createServer({
  stt, post, token, snippets = NOOP_SNIPPETS, settings = NOOP_SETTINGS, stats = NOOP_STATS, home,
  log = () => {}, maxAudioSeconds = MAX_AUDIO_SECONDS, requestTimeoutMs = 60000,
}) {
  if (!token) throw new Error('createServer cần token');
  const enqueue = serialQueue();
  const startedAt = Date.now();
  /** @type {{ at: string, route: string, status: number, code: string }[]} */
  const recentErrors = [];
  /** @param {Record<string, unknown>} entry */
  function recordRecentError(entry) {
    if (!entry.code) return;
    recentErrors.push({ at: new Date().toISOString(), route: String(entry.route ?? ''), status: Number(entry.status), code: String(entry.code) });
    if (recentErrors.length > MAX_RECENT_ERRORS) recentErrors.shift();
  }
  let partialBusy = false;
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
        sendJson(res, 200, { ok: true, version: VERSION, models: await stt.status(), max_audio_seconds: maxAudioSeconds });
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
      if (url.pathname === '/v1/snippets') {
        if (req.method === 'GET') {
          sendJson(res, 200, await callPost(() => snippets.list()));
        } else if (req.method === 'PUT') {
          const body = await readJson(req, MAX_SETTINGS_JSON_BYTES);
          if (!body || typeof body !== 'object' || !Array.isArray(body.entries)) {
            throw new HttpError('bad_request', 'Cần JSON dạng {"entries": [...]}.');
          }
          if (body.entries.length > MAX_SNIPPET_ENTRIES) {
            throw new HttpError('bad_request', `Tối đa ${MAX_SNIPPET_ENTRIES} mục snippets.`);
          }
          await callPost(() => snippets.replaceAll(body.entries));
          sendJson(res, 200, await callPost(() => snippets.list()));
        } else {
          throw new HttpError('bad_request', 'Chỉ hỗ trợ GET hoặc PUT.', 405);
        }
        entry.status = 200;
        return;
      }
      if (url.pathname === '/v1/settings') {
        if (req.method === 'GET') {
          sendJson(res, 200, await callPost(() => settings.get()));
        } else if (req.method === 'PUT') {
          const body = await readJson(req, MAX_SETTINGS_JSON_BYTES);
          if (!body || typeof body !== 'object' || Array.isArray(body)) {
            throw new HttpError('bad_request', 'Cần JSON object.');
          }
          sendJson(res, 200, await callPost(() => settings.update(body)));
        } else {
          throw new HttpError('bad_request', 'Chỉ hỗ trợ GET hoặc PUT.', 405);
        }
        entry.status = 200;
        return;
      }
      if (url.pathname === '/v1/command') {
        if (req.method !== 'POST') throw new HttpError('bad_request', 'Chỉ hỗ trợ POST.', 405);
        await command(req, res, entry);
        return;
      }
      if (url.pathname === '/v1/stats') {
        if (req.method === 'GET') {
          const weeksParam = url.searchParams.get('weeks');
          const weeks = weeksParam === null ? 16 : Number(weeksParam);
          if (!Number.isInteger(weeks) || weeks < 1 || weeks > 104) {
            throw new HttpError('bad_request', 'weeks phải là số nguyên 1–104.');
          }
          const s = await callPost(() => stats.summary({ weeks }));
          sendJson(res, 200, { enabled: settings.get().stats_enabled !== false, ...s });
        } else if (req.method === 'DELETE') {
          sendJson(res, 200, await callPost(() => stats.clear()));
        } else {
          throw new HttpError('bad_request', 'Chỉ hỗ trợ GET hoặc DELETE.', 405);
        }
        entry.status = 200;
        return;
      }
      if (url.pathname === '/v1/dictionary/suggestions') {
        if (req.method !== 'GET') throw new HttpError('bad_request', 'Chỉ hỗ trợ GET.', 405);
        if (typeof post.dictionary.suggestions !== 'function') throw new HttpError('internal', 'Chưa cấu hình gợi ý từ điển cho engine này.');
        sendJson(res, 200, await callPost(() => post.dictionary.suggestions()));
        entry.status = 200;
        return;
      }
      if (url.pathname === '/v1/dictionary/suggestions/dismiss') {
        if (req.method !== 'POST') throw new HttpError('bad_request', 'Chỉ hỗ trợ POST.', 405);
        if (typeof post.dictionary.dismissSuggestion !== 'function') throw new HttpError('internal', 'Chưa cấu hình gợi ý từ điển cho engine này.');
        const body = await readJson(req, MAX_SETTINGS_JSON_BYTES);
        if (!body || typeof body.term !== 'string' || body.term.trim() === '') {
          throw new HttpError('bad_request', 'Cần JSON dạng {"term": "…"}.');
        }
        sendJson(res, 200, await callPost(() => post.dictionary.dismissSuggestion(body.term)));
        entry.status = 200;
        return;
      }
      if (url.pathname === '/v1/export') {
        if (req.method !== 'GET') throw new HttpError('bad_request', 'Chỉ hỗ trợ GET.', 405);
        await exportHandler(res, url, entry);
        return;
      }
      if (url.pathname === '/v1/import') {
        if (req.method !== 'POST') throw new HttpError('bad_request', 'Chỉ hỗ trợ POST.', 405);
        await importHandler(req, res, url, entry);
        return;
      }
      if (url.pathname === '/v1/diagnostics') {
        if (req.method !== 'GET') throw new HttpError('bad_request', 'Chỉ hỗ trợ GET.', 405);
        sendJson(res, 200, await buildDiagnosticsNow());
        entry.status = 200;
        return;
      }
      if (url.pathname === '/v1/partial') {
        if (req.method !== 'POST') throw new HttpError('bad_request', 'Chỉ hỗ trợ POST.', 405);
        await partial(req, res, url, entry);
        return;
      }
      throw new HttpError('bad_request', 'Không có đường dẫn này.', 404);
    } catch (err) {
      const e = toHttpError(err);
      entry.status = e.status;
      entry.code = e.code;
      recordRecentError(entry);
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
   * POST /v1/command: sửa/soạn văn bản bằng lời (contract/engine-api.md, mục Command Mode).
   * Không log instruction/selection/context/app (có thể chứa nội dung của người dùng).
   * @param {http.IncomingMessage} req @param {http.ServerResponse} res @param {Record<string, unknown>} entry
   */
  async function command(req, res, entry) {
    const body = await readJson(req, MAX_SETTINGS_JSON_BYTES);
    if (!body || typeof body !== 'object' || Array.isArray(body)) {
      throw new HttpError('bad_request', 'Cần JSON object.');
    }
    const { instruction, selection = '', context = '', app } = /** @type {any} */ (body);
    if (typeof instruction !== 'string' || instruction.trim() === '' || instruction.length > COMMAND_FIELD_MAX) {
      throw new HttpError('bad_request', `instruction phải là chuỗi khác rỗng, tối đa ${COMMAND_FIELD_MAX} ký tự.`);
    }
    if (typeof selection !== 'string' || selection.length > COMMAND_FIELD_MAX) {
      throw new HttpError('bad_request', `selection phải là chuỗi, tối đa ${COMMAND_FIELD_MAX} ký tự.`);
    }
    if (typeof context !== 'string' || context.length > COMMAND_FIELD_MAX) {
      throw new HttpError('bad_request', `context phải là chuỗi, tối đa ${COMMAND_FIELD_MAX} ký tự.`);
    }
    if (app !== undefined && typeof app !== 'string') {
      throw new HttpError('bad_request', 'app phải là chuỗi.');
    }
    if (typeof post.command !== 'function') {
      throw new HttpError('internal', 'Chưa cấu hình Command Mode cho engine này.');
    }
    let result;
    try {
      result = await withTimeout(
        Promise.resolve().then(() => post.command({ instruction, selection, context, ...(app !== undefined ? { app } : {}) })),
        requestTimeoutMs, 'Lệnh quá thời gian.',
      );
    } catch (err) {
      // CommandError.code (rewrite_unavailable|cloud_disabled|timeout|bad_request) đi qua STATUS;
      // mã lạ/lỗi khác ⇒ internal, không lộ chi tiết.
      throw toHttpError(err);
    }
    if (!result || typeof result.text !== 'string' || (result.kind !== 'edit' && result.kind !== 'draft')) {
      throw new HttpError('internal', 'Lệnh trả kết quả không hợp lệ.');
    }
    sendJson(res, 200, { text: result.text, kind: result.kind, timings_ms: result.timings_ms ?? {} });
    entry.status = 200;
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
      // "Nói nhỏ" (item 6, contract/engine-api.md mục "Giọng điệu và nói nhỏ"): khuếch đại TRƯỚC
      // STT, hoàn toàn trong máy. Dò im lặng ở TRÊN dùng audio gốc (gain không ảnh hưởng quyết định
      // im lặng vì gain không khuếch đại được im lặng tuyệt đối — xem engine/stt/gain.js).
      const pcm = settings.get().whisper_mode ? applyAutoGain(wave.samples, wave.sampleRate) : wave.samples;
      const r = await stt.transcribe(model, { pcm, sampleRate: wave.sampleRate });
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
      id, model, mode: typeof postOut.mode === 'string' && RESOLVED_MODES.has(postOut.mode) ? postOut.mode : mode, language: 'vi',
      text_raw: r.textRaw,
      text: postOut.text,
      audio_ms: audioMs,
      timings_ms: { stt: r.sttMs, post: postMs, total },
      rtf: audioMs > 0 ? Math.round((r.sttMs / audioMs) * 1000) / 1000 : 0,
      post: {
        applied: Array.isArray(postOut.applied) ? postOut.applied : [],
        actions: Array.isArray(postOut.actions) ? postOut.actions : [],
        rewrite: postOut.rewrite ?? { used: false, error: null },
        degraded: postOut.degraded === true,
        degraded_reason: typeof postOut.degraded_reason === 'string' ? postOut.degraded_reason : null,
      },
    };
    if (r.silent) body.silence = true;
    // Thống kê (item 1): mỗi dictation THÀNH CÔNG (không rỗng, không Command Mode — route này
    // không phải Command Mode) cộng bộ đếm, nếu stats_enabled (mặc định true).
    if (!r.silent && typeof body.text === 'string' && body.text.trim() !== '' && settings.get().stats_enabled !== false) {
      stats.record({ text: /** @type {string} */ (body.text), audioMs, app: app ?? null });
    }
    sendJson(res, 200, body);
    entry.status = 200;
  }

  /** @returns {string|null} */
  function historyPath() {
    return home ? join(home, 'history.jsonl') : null;
  }

  /** Đọc history.jsonl (bỏ qua dòng hỏng, không ném lỗi — export/diagnostics chỉ cần đọc được gì có). */
  function readHistoryEntries() {
    const p = historyPath();
    if (!p || !existsSync(p)) return [];
    let raw;
    try {
      raw = readFileSync(p, 'utf8');
    } catch {
      return [];
    }
    const out = [];
    for (const line of raw.split('\n')) {
      const t = line.trim();
      if (t === '') continue;
      try {
        out.push(JSON.parse(t));
      } catch {
        // dòng hỏng: bỏ qua (export/diagnostics không phải chỗ báo lỗi dữ liệu client).
      }
    }
    return out;
  }

  /**
   * GET /v1/export (item 2, contract/engine-api.md mục "Xuất/nhập").
   * @param {http.ServerResponse} res @param {URL} url @param {Record<string, unknown>} entry
   */
  async function exportHandler(res, url, entry) {
    const includeHistory = url.searchParams.get('include_history') === '1';
    const dictionary = await callPost(() => post.dictionary.list());
    const snippetsOut = await callPost(() => snippets.list());
    const out = buildExport({
      dictionary, snippets: snippetsOut, settings: settings.get(), stats: await callPost(() => stats.exportDays()),
      history: includeHistory ? readHistoryEntries() : undefined,
    });
    sendJson(res, 200, out);
    entry.status = 200;
  }

  /**
   * POST /v1/import?mode=merge|replace (mặc định merge, item 2). Kiểm NGHIÊM TOÀN BỘ gói trước
   * (validateImportPackage) rồi mới áp dụng — không nhập nửa vời. Áp `settings` TRƯỚC các phần
   * khác: đó là bước duy nhất còn có thể ném lỗi sau khi đã kiểm (khoá lạ với bản settings hiện
   * tại) — áp trước để không để lại thay đổi dở dang ở dictionary/snippets/stats/history nếu lỗi.
   * @param {http.IncomingMessage} req @param {http.ServerResponse} res @param {URL} url @param {Record<string, unknown>} entry
   */
  async function importHandler(req, res, url, entry) {
    const mode = url.searchParams.get('mode') === 'replace' ? 'replace' : 'merge';
    const body = await readJson(req, MAX_IMPORT_BYTES);
    const validated = await callPost(() => validateImportPackage(body));

    const applied = { dictionary: 0, snippets: 0, settings: 0, stats_days: 0, history: 0 };
    if (validated.settings !== null) {
      await callPost(() => settings.update(validated.settings));
      applied.settings = Object.keys(validated.settings).length;
    }
    if (validated.dictionary !== null) {
      if (mode === 'replace') {
        await callPost(() => post.dictionary.replaceAll(validated.dictionary));
        applied.dictionary = validated.dictionary.length;
      } else {
        const current = (await callPost(() => post.dictionary.list())).entries;
        const { result, applied: n } = mergeDictionary(current, validated.dictionary);
        await callPost(() => post.dictionary.replaceAll(result));
        applied.dictionary = n;
      }
    }
    if (validated.snippets !== null) {
      if (mode === 'replace') {
        await callPost(() => snippets.replaceAll(validated.snippets));
        applied.snippets = validated.snippets.length;
      } else {
        const current = (await callPost(() => snippets.list())).entries;
        const { result, applied: n } = mergeSnippets(current, validated.snippets);
        await callPost(() => snippets.replaceAll(result));
        applied.snippets = n;
      }
    }
    if (validated.statsDays !== null) {
      applied.stats_days = await callPost(() => stats.importDays(validated.statsDays, mode));
    }
    if (validated.history !== null) {
      const p = historyPath();
      if (p) {
        let nextEntries;
        if (mode === 'replace') {
          nextEntries = validated.history;
          applied.history = validated.history.length;
        } else {
          const merged = mergeHistory(readHistoryEntries(), validated.history);
          nextEntries = merged.result;
          applied.history = merged.applied;
        }
        const body2 = nextEntries.map((e) => JSON.stringify(e)).join('\n') + (nextEntries.length ? '\n' : '');
        try {
          writeFileSync(p, body2, { mode: 0o600 });
        } catch (err) {
          throw toHttpError(err);
        }
      }
    }
    sendJson(res, 200, { ok: true, applied, ...(validated.ignoredSettingsKeys.length ? { ignored: validated.ignoredSettingsKeys } : {}) });
    entry.status = 200;
  }

  /** GET /v1/diagnostics (item 3). */
  async function buildDiagnosticsNow() {
    const models = await stt.status();
    const dictCount = (await callPost(() => post.dictionary.list())).entries.length;
    const snippetsCount = (await callPost(() => snippets.list())).entries.length;
    return buildDiagnostics({
      version: VERSION, node: process.version, platform: `${process.platform}-${process.arch}`,
      uptimeS: Math.round((Date.now() - startedAt) / 1000),
      models, defaultModel: stt.defaultModel, settings: settings.get(),
      counts: { dictionary: dictCount, snippets: snippetsCount, history: readHistoryEntries().length, stats_days: await callPost(() => stats.daysCount()) },
      homeBasename: home ? basename(home) : null,
      recentErrors, home,
    });
  }

  /**
   * POST /v1/partial (item 9): xem chữ chạy trực tiếp — chỉ từ điển (applyPreview, không hiệu ứng
   * phụ), KHÔNG post xử lý nặng/LLM, KHÔNG ghi history/thống kê, tối đa 1 yêu cầu đồng thời.
   * @param {http.IncomingMessage} req @param {http.ServerResponse} res @param {URL} url @param {Record<string, unknown>} entry
   */
  async function partial(req, res, url, entry) {
    if (partialBusy) throw new HttpError('busy', 'Engine đang xử lý một yêu cầu xem trước khác.');
    partialBusy = true;
    try {
      const model = url.searchParams.get('model') || stt.defaultModel;
      if (!stt.isKnown(model)) throw new HttpError('bad_request', `Không có model "${model}".`);
      let bytes = await readBody(req, MAX_AUDIO_BYTES);
      let wave = decodeAudio(bytes, req.headers['content-type']);
      bytes = new Uint8Array(0);
      const maxSamples = Math.round(MAX_PARTIAL_AUDIO_SECONDS * wave.sampleRate);
      if (wave.samples.length > maxSamples) {
        // Dài hơn 30s: chỉ lấy 30s CUỐI (xem trước khi đang ghi dài, phần đầu đã xem trước rồi).
        wave = { samples: wave.samples.subarray(wave.samples.length - maxSamples), sampleRate: wave.sampleRate };
      }
      const audioMs = durationMs(wave.samples.length, wave.sampleRate);
      entry.audio_ms = audioMs;
      await stt.ensure(model);
      let text = '';
      let sttMs = 0;
      if (!isSilence(wave.samples, wave.sampleRate)) {
        const r = await stt.transcribe(model, { pcm: wave.samples, sampleRate: wave.sampleRate });
        text = r.text;
        sttMs = r.stt_ms;
      }
      entry.stt_ms = sttMs;
      const d = text === '' ? { text: '' } : await callPost(() => post.dictionary.applyPreview(text));
      sendJson(res, 200, { text: d.text, audio_ms: audioMs, stt_ms: sttMs });
      entry.status = 200;
    } finally {
      partialBusy = false;
    }
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
