// Cài đặt người dùng (GET/PUT /v1/settings, contract/engine-api.md mục Cài đặt người dùng).
// Lưu chung ~/.vflow/config.json (bảo toàn các khoá khác: rewrite.*, auto.apps, …).
import { readFileSync, statSync, writeFileSync, renameSync, mkdirSync, chmodSync, rmSync } from 'node:fs';
import { dirname } from 'node:path';
import { randomBytes } from 'node:crypto';

export const DEFAULT_SETTINGS = Object.freeze({
  cloud_llm: true,
  llm_model: null,
  llm_timeout_ms: 8000,
  actions_enabled: true,
});

const SETTINGS_KEYS = Object.keys(DEFAULT_SETTINGS);
const MAX_MODEL_LEN = 200;

export class SettingsError extends Error {
  /** @param {string} message */
  constructor(message) {
    super(message);
    this.code = 'bad_request';
  }
}

/** @param {unknown} v */
const isObj = (v) => v !== null && typeof v === 'object' && !Array.isArray(v);

/**
 * Kiểm kiểu/giá trị bốn trường cài đặt. Ném SettingsError nếu sai.
 * @param {Record<string, unknown>} v
 */
function validateValues(v) {
  if (typeof v.cloud_llm !== 'boolean') throw new SettingsError('cloud_llm phải là boolean');
  if (v.llm_model !== null && (typeof v.llm_model !== 'string' || v.llm_model.length > MAX_MODEL_LEN)) {
    throw new SettingsError(`llm_model phải là chuỗi tối đa ${MAX_MODEL_LEN} ký tự hoặc null`);
  }
  if (!Number.isInteger(v.llm_timeout_ms) || v.llm_timeout_ms < 1000 || v.llm_timeout_ms > 30000) {
    throw new SettingsError('llm_timeout_ms phải là số nguyên 1000–30000');
  }
  if (typeof v.actions_enabled !== 'boolean') throw new SettingsError('actions_enabled phải là boolean');
  return v;
}

/**
 * Ghi JSON nguyên tử (tệp tạm + rename), quyền 0600 (bỏ qua chmod trên Windows).
 * @param {string} path @param {unknown} data
 */
function writePrivateJson(path, data) {
  mkdirSync(dirname(path), { recursive: true, mode: 0o700 });
  const tmp = `${path}.tmp-${process.pid}-${randomBytes(4).toString('hex')}`;
  try {
    writeFileSync(tmp, JSON.stringify(data, null, 2) + '\n', { mode: 0o600 });
    renameSync(tmp, path);
  } catch (err) {
    rmSync(tmp, { force: true });
    throw err;
  }
  if (process.platform !== 'win32') chmodSync(path, 0o600);
}

/** @param {string} path @returns {number|null} mtimeMs, hoặc null nếu chưa có tệp */
function statMtime(path) {
  try {
    return statSync(path).mtimeMs;
  } catch (err) {
    if (/** @type {any} */ (err).code === 'ENOENT') return null;
    throw new SettingsError(`không đọc được tệp cấu hình (${/** @type {any} */ (err).code ?? 'lỗi'})`);
  }
}

/**
 * Đọc toàn bộ tệp cấu hình thô (không qua engine/post/config.js — settings.js chỉ quan tâm
 * bốn khoá cấp trên cùng, giữ nguyên phần còn lại). Không có tệp ⇒ object rỗng.
 * @param {string} path
 */
function readRaw(path) {
  let text;
  try {
    text = readFileSync(path, 'utf8');
  } catch (err) {
    if (/** @type {any} */ (err).code === 'ENOENT') return {};
    throw new SettingsError(`không đọc được tệp cấu hình (${/** @type {any} */ (err).code ?? 'lỗi'})`);
  }
  let json;
  try {
    json = JSON.parse(text);
  } catch {
    throw new SettingsError('tệp cấu hình không phải JSON hợp lệ');
  }
  if (!isObj(json)) throw new SettingsError('tệp cấu hình phải là object JSON');
  return json;
}

/** @param {Record<string, unknown>} raw */
function pickSettings(raw) {
  const out = { ...DEFAULT_SETTINGS };
  for (const k of SETTINGS_KEYS) if (Object.hasOwn(raw, k)) out[k] = raw[k];
  return validateValues(out);
}

/**
 * @param {{ configPath: string }} opts
 */
export function createSettingsStore({ configPath }) {
  if (typeof configPath !== 'string' || configPath === '') throw new TypeError('cần configPath');

  /** @type {{ mtimeMs: number|null, raw: Record<string, unknown>, settings: Record<string, unknown> } | null} */
  let cache = null;

  function load() {
    const raw = readRaw(configPath);
    const settings = pickSettings(raw);
    cache = { mtimeMs: statMtime(configPath), raw, settings };
    return cache;
  }

  /** Đọc lại từ tệp nếu mtime đổi (PUT của chính mình, hoặc tệp bị sửa tay). */
  function current() {
    const mtimeMs = statMtime(configPath);
    if (!cache || cache.mtimeMs !== mtimeMs) return load();
    return cache;
  }

  return {
    /** @returns {{ cloud_llm: boolean, llm_model: string|null, llm_timeout_ms: number, actions_enabled: boolean }} */
    get() {
      return { ...current().settings };
    },

    /**
     * Nhận tập con các trường, kiểm kiểu/giá trị, ghi đè vào tệp cấu hình (bảo toàn khoá khác).
     * @param {unknown} patch
     */
    update(patch) {
      if (!isObj(patch)) throw new SettingsError('patch phải là object JSON');
      for (const k of Object.keys(patch)) {
        if (!SETTINGS_KEYS.includes(k)) throw new SettingsError(`khoá lạ "${k}"`);
      }
      const { raw, settings } = current();
      const merged = validateValues({ ...settings, ...patch });
      const nextRaw = { ...raw, ...merged };
      writePrivateJson(configPath, nextRaw);
      cache = { mtimeMs: statMtime(configPath), raw: nextRaw, settings: merged };
      return { ...merged };
    },
  };
}
