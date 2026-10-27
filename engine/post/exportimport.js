// Xuất/nhập cấu hình người dùng (contract/engine-api.md mục "Xuất/nhập", item 2).
// Bất biến: gói xuất/nhập TUYỆT ĐỐI không chứa token, khoá 9Router hay bất cứ bí mật nào — chỉ
// khoá cấu hình người dùng thường (dictionary/snippets/settings đã lược/stats/history tuỳ chọn).
// Nhập kiểm NGHIÊM toàn bộ trước khi áp dụng bất cứ phần nào (không nhập nửa vời).
import { validateEntries as validateDictionaryEntries } from './dictionary.js';
import { validateEntries as validateSnippetEntries, normalizeMatch } from './snippets.js';

export const EXPORT_FORMAT = 'vflow-export';
export const EXPORT_VERSION = 1;
export const MAX_IMPORT_BYTES = 20 * 1024 * 1024;
/** Khoá không bao giờ được nhập từ gói, dù xuất hiện trong settings — bị bỏ qua và báo `ignored`. */
const SECRET_SETTINGS_KEYS = ['token', 'key', 'api_key', 'apikey', 'rewrite_key', 'llm_api_key', 'rewrite', 'secret', 'password'];
/** Khoá cài đặt đã gỡ khỏi engine (gói xuất từ bản cũ vẫn chứa): bỏ qua và báo `ignored` thay vì từ chối cả gói. */
const RETIRED_SETTINGS_KEYS = ['vocab_boost'];

export class ImportError extends Error {
  /** @param {string} message */
  constructor(message) {
    super(message);
    this.code = 'bad_request';
  }
}

/**
 * @param {{ dictionary: {entries:any[]}, snippets: {entries:any[]}, settings: Record<string, unknown>,
 *           stats: { backfilled: boolean, days: Record<string, unknown> }, history?: any[] }} args
 */
export function buildExport({ dictionary, snippets, settings, stats, history }) {
  const out = {
    format: EXPORT_FORMAT,
    version: EXPORT_VERSION,
    exported_at: new Date().toISOString(),
    dictionary: dictionary.entries,
    snippets: snippets.entries,
    settings,
    stats,
  };
  if (Array.isArray(history)) out.history = history;
  return out;
}

const HISTORY_KEYS = new Set(['id', 'at', 'mode', 'model', 'text_raw', 'text', 'app', 'audio_ms', 'total_ms']);

/** Kiểm NGHIÊM một mục history (định dạng client/Sources/VFlowCore/History.swift). @param {unknown} e @param {string} at */
function validateHistoryEntry(e, at) {
  if (e === null || typeof e !== 'object' || Array.isArray(e)) throw new ImportError(`${at} phải là object`);
  const o = /** @type {Record<string, unknown>} */ (e);
  for (const k of Object.keys(o)) if (!HISTORY_KEYS.has(k)) throw new ImportError(`${at} có khoá lạ "${k}"`);
  if (typeof o.id !== 'string' || o.id === '') throw new ImportError(`${at}.id phải là chuỗi khác rỗng`);
  if (typeof o.at !== 'string' || Number.isNaN(Date.parse(o.at))) throw new ImportError(`${at}.at phải là thời điểm ISO hợp lệ`);
  if (typeof o.mode !== 'string' || o.mode === '') throw new ImportError(`${at}.mode phải là chuỗi khác rỗng`);
  if (typeof o.model !== 'string') throw new ImportError(`${at}.model phải là chuỗi`);
  if (typeof o.text_raw !== 'string') throw new ImportError(`${at}.text_raw phải là chuỗi`);
  if (typeof o.text !== 'string') throw new ImportError(`${at}.text phải là chuỗi`);
  if (o.app !== undefined && typeof o.app !== 'string') throw new ImportError(`${at}.app phải là chuỗi`);
  if (o.audio_ms !== undefined && !(Number.isInteger(o.audio_ms) && o.audio_ms >= 0)) throw new ImportError(`${at}.audio_ms phải là số nguyên ≥ 0`);
  if (o.total_ms !== undefined && !(Number.isInteger(o.total_ms) && o.total_ms >= 0)) throw new ImportError(`${at}.total_ms phải là số nguyên ≥ 0`);
}

const STATS_DAY_KEYS = new Set(['words', 'audio_ms', 'count', 'apps']);

/** @param {unknown} day @param {string} at */
function validateStatsDay(day, at) {
  if (day === null || typeof day !== 'object' || Array.isArray(day)) throw new ImportError(`${at} phải là object`);
  const d = /** @type {Record<string, unknown>} */ (day);
  for (const k of Object.keys(d)) if (!STATS_DAY_KEYS.has(k)) throw new ImportError(`${at} có khoá lạ "${k}"`);
  for (const k of ['words', 'audio_ms', 'count']) {
    if (!Number.isInteger(d[k]) || /** @type {number} */ (d[k]) < 0) throw new ImportError(`${at}.${k} phải là số nguyên ≥ 0`);
  }
  if (d.apps === undefined) return;
  if (d.apps === null || typeof d.apps !== 'object' || Array.isArray(d.apps)) throw new ImportError(`${at}.apps phải là object`);
  for (const [app, a] of Object.entries(/** @type {Record<string, any>} */ (d.apps))) {
    if (a === null || typeof a !== 'object') throw new ImportError(`${at}.apps["${app}"] phải là object`);
    if (!Number.isInteger(a.words) || a.words < 0) throw new ImportError(`${at}.apps["${app}"].words phải là số nguyên ≥ 0`);
    if (!Number.isInteger(a.count) || a.count < 0) throw new ImportError(`${at}.apps["${app}"].count phải là số nguyên ≥ 0`);
  }
}

/**
 * Kiểm NGHIÊM toàn bộ gói nhập; ném ImportError (chỉ rõ phần/chỉ mục) ngay khi gặp lỗi đầu tiên —
 * KHÔNG áp dụng gì (caller chỉ áp dụng sau khi hàm này trả về không lỗi).
 * @param {unknown} pkg
 * @returns {{ dictionary: any[]|null, snippets: any[]|null, settings: Record<string, unknown>|null,
 *             ignoredSettingsKeys: string[], statsDays: Record<string, unknown>|null, history: any[]|null }}
 */
export function validateImportPackage(pkg) {
  if (pkg === null || typeof pkg !== 'object' || Array.isArray(pkg)) throw new ImportError('gói nhập phải là object JSON');
  const p = /** @type {Record<string, unknown>} */ (pkg);
  if (p.format !== EXPORT_FORMAT) throw new ImportError(`format phải là "${EXPORT_FORMAT}"`);
  if (p.version !== EXPORT_VERSION) throw new ImportError(`version phải là ${EXPORT_VERSION}`);

  let dictionary = null;
  if (p.dictionary !== undefined) {
    try {
      dictionary = validateDictionaryEntries(p.dictionary);
    } catch (err) {
      throw new ImportError(`dictionary: ${/** @type {Error} */ (err).message}`);
    }
  }
  let snippets = null;
  if (p.snippets !== undefined) {
    try {
      snippets = validateSnippetEntries(p.snippets);
    } catch (err) {
      throw new ImportError(`snippets: ${/** @type {Error} */ (err).message}`);
    }
  }

  let settings = null;
  const ignoredSettingsKeys = [];
  if (p.settings !== undefined) {
    if (p.settings === null || typeof p.settings !== 'object' || Array.isArray(p.settings)) {
      throw new ImportError('settings phải là object');
    }
    settings = { .../** @type {object} */ (p.settings) };
    for (const secret of [...SECRET_SETTINGS_KEYS, ...RETIRED_SETTINGS_KEYS]) {
      if (Object.hasOwn(settings, secret)) {
        delete settings[secret];
        ignoredSettingsKeys.push(secret);
      }
    }
    // Quyền riêng tư: một TỆP không được tự BẬT ghi âm lịch sử (chỉ người dùng bật qua PUT /v1/settings).
    // Gói nói `audio_history:false` thì áp dụng bình thường (tắt là hướng an toàn).
    if (settings.audio_history === true) {
      delete settings.audio_history;
      ignoredSettingsKeys.push('audio_history');
    }
  }

  let statsDays = null;
  if (p.stats !== undefined) {
    const s = /** @type {any} */ (p.stats);
    if (s === null || typeof s !== 'object' || Array.isArray(s) || typeof s.days !== 'object' || s.days === null) {
      throw new ImportError('stats phải là object { days: {...} }');
    }
    for (const [key, day] of Object.entries(s.days)) {
      if (!/^\d{4}-\d{2}-\d{2}$/.test(key)) throw new ImportError(`stats.days có khoá ngày không hợp lệ "${key}"`);
      validateStatsDay(day, `stats.days["${key}"]`);
    }
    statsDays = s.days;
  }

  let history = null;
  if (p.history !== undefined) {
    if (!Array.isArray(p.history)) throw new ImportError('history phải là mảng');
    p.history.forEach((e, i) => validateHistoryEntry(e, `history[${i}]`));
    history = p.history;
  }

  return { dictionary, snippets, settings, ignoredSettingsKeys, statsDays, history };
}

/**
 * Merge danh sách theo khoá duy nhất `key`: giữ mục hiện có khi trùng (không tạo trùng, không
 * ghi đè dữ liệu đang dùng). Trả số mục THỰC SỰ được thêm.
 * @param {any[]} current @param {any[]} incoming @param {(e:any) => string} keyOf
 */
export function mergeListSkipDuplicates(current, incoming, keyOf) {
  const seen = new Set(current.map(keyOf));
  const added = [];
  for (const e of incoming) {
    const k = keyOf(e);
    if (seen.has(k)) continue;
    seen.add(k);
    added.push(e);
  }
  return { result: [...current, ...added], applied: added.length };
}

/** @param {any[]} current @param {any[]} incoming */
export const mergeDictionary = (current, incoming) => mergeListSkipDuplicates(current, incoming, (e) => e.term);
/** @param {any[]} current @param {any[]} incoming */
export const mergeSnippets = (current, incoming) => mergeListSkipDuplicates(current, incoming, (e) => normalizeMatch(e.trigger));
/** @param {any[]} current @param {any[]} incoming */
export const mergeHistory = (current, incoming) => mergeListSkipDuplicates(current, incoming, (e) => e.id);
