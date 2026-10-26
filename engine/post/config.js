// Cấu hình engine (~/.vflow/config.json): mặc định + kiểm schema (contract/engine-api.md, mục Cấu hình).
import { readFileSync } from 'node:fs';
import { homedir } from 'node:os';
import { join } from 'node:path';

export const MODES = ['normal', 'clean', 'email', 'auto'];

/** Mặc định. Bảng auto.apps: bundle id -> chế độ; không có trong bảng thì là normal. */
export const DEFAULT_CONFIG = Object.freeze({
  default_model: 'zipformer-vi-30m',
  rewrite: {
    url: 'http://127.0.0.1:20128/v1',
    // Không đoán tên model của 9Router: chưa đặt thì email trả rewrite.error = "no_model".
    model: null,
    timeout_ms: 8000,
    key_file: '~/.vflow/rewrite.key',
  },
  remote: { phowhisper: { url: 'http://127.0.0.1:7612' } },
  auto: {
    apps: {
      'com.apple.mail': 'email',
      'com.microsoft.Outlook': 'email',
      'com.readdle.smartemail-Mac': 'email',
      'com.mimestream.Mimestream': 'email',
      'com.apple.Terminal': 'clean',
      'com.googlecode.iterm2': 'clean',
      'dev.warp.Warp-Stable': 'clean',
      'com.mitchellh.ghostty': 'clean',
      'com.tinyspeck.slackmacgap': 'clean',
      'ru.keepcoder.Telegram': 'clean',
      'com.hnc.Discord': 'clean',
      'com.apple.MobileSMS': 'clean',
      'net.whatsapp.WhatsApp': 'clean',
    },
  },
});

/** Các tên khoá gợi ý ai đó dán khoá thẳng vào cấu hình. */
const SECRET_KEYS = ['key', 'api_key', 'apiKey', 'apikey', 'token', 'secret', 'password', 'authorization'];

export class ConfigError extends Error {
  /** @param {string} message */
  constructor(message) {
    super(message);
    this.code = 'bad_config';
  }
}

/** @param {string} p */
export function expandHome(p) {
  return p === '~' ? homedir() : p.startsWith('~/') ? join(homedir(), p.slice(2)) : p;
}

/** @param {unknown} v */
const isObj = (v) => v !== null && typeof v === 'object' && !Array.isArray(v);

/**
 * Đọc cấu hình; tệp không tồn tại (hoặc không truyền path) ⇒ mặc định. Tệp hỏng/sai schema ⇒ ném
 * ConfigError. Thông báo lỗi không bao giờ trích nội dung tệp (có thể có thứ nhạy cảm).
 * @param {string} [path]
 */
export function loadConfig(path) {
  if (!path) return validateConfig({});
  let raw;
  try {
    raw = readFileSync(expandHome(path), 'utf8');
  } catch (err) {
    if (/** @type {any} */ (err).code === 'ENOENT') return validateConfig({});
    throw new ConfigError(`không đọc được tệp cấu hình (${/** @type {any} */ (err).code ?? 'lỗi'})`);
  }
  let json;
  try {
    json = JSON.parse(raw);
  } catch {
    throw new ConfigError('tệp cấu hình không phải JSON hợp lệ');
  }
  return validateConfig(json);
}

/**
 * Trộn với mặc định và kiểm kiểu. Khoá lạ ở cấp trên cùng được giữ nguyên (cho phần khác của engine).
 * @param {unknown} input
 */
export function validateConfig(input) {
  if (!isObj(input)) throw new ConfigError('cấu hình phải là object JSON');
  const c = /** @type {Record<string, any>} */ (input);
  const d = DEFAULT_CONFIG;

  const rewriteIn = c.rewrite ?? {};
  if (!isObj(rewriteIn)) throw new ConfigError('rewrite phải là object');
  for (const k of SECRET_KEYS) {
    if (Object.hasOwn(rewriteIn, k)) {
      throw new ConfigError(`không đặt khoá trực tiếp trong cấu hình (rewrite.${k}); dùng rewrite.key_file trỏ tới tệp chứa khoá`);
    }
  }
  const rewrite = { ...d.rewrite, ...rewriteIn };
  if (typeof rewrite.url !== 'string' || !/^https?:\/\/[^\s]+$/.test(rewrite.url)) {
    throw new ConfigError('rewrite.url phải là URL http(s)');
  }
  if (rewrite.model !== null && (typeof rewrite.model !== 'string' || rewrite.model.trim() === '')) {
    throw new ConfigError('rewrite.model phải là chuỗi khác rỗng hoặc null');
  }
  if (!Number.isInteger(rewrite.timeout_ms) || rewrite.timeout_ms < 100 || rewrite.timeout_ms > 120000) {
    throw new ConfigError('rewrite.timeout_ms phải là số nguyên 100–120000');
  }
  if (rewrite.key_file !== null && (typeof rewrite.key_file !== 'string' || rewrite.key_file === '')) {
    throw new ConfigError('rewrite.key_file phải là đường dẫn tệp hoặc null');
  }

  const defaultModel = c.default_model ?? d.default_model;
  if (typeof defaultModel !== 'string' || defaultModel === '') throw new ConfigError('default_model phải là chuỗi');

  const remoteIn = c.remote ?? {};
  if (!isObj(remoteIn) || (remoteIn.phowhisper !== undefined && !isObj(remoteIn.phowhisper))) {
    throw new ConfigError('remote.phowhisper phải là object');
  }
  const phowhisper = { ...d.remote.phowhisper, ...(remoteIn.phowhisper ?? {}) };
  if (typeof phowhisper.url !== 'string' || !/^https?:\/\/[^\s]+$/.test(phowhisper.url)) {
    throw new ConfigError('remote.phowhisper.url phải là URL http(s)');
  }

  const autoIn = c.auto ?? {};
  if (!isObj(autoIn) || (autoIn.apps !== undefined && !isObj(autoIn.apps))) {
    throw new ConfigError('auto.apps phải là object { bundleId: chế độ }');
  }
  const apps = { ...d.auto.apps, ...(autoIn.apps ?? {}) };
  for (const [id, mode] of Object.entries(apps)) {
    if (!['normal', 'clean', 'email'].includes(mode)) {
      throw new ConfigError(`auto.apps["${id}"] phải là normal, clean hoặc email`);
    }
  }

  return {
    ...c,
    default_model: defaultModel,
    rewrite,
    remote: { ...remoteIn, phowhisper },
    auto: { ...autoIn, apps },
  };
}
