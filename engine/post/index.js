// Hậu xử lý văn bản STT: từ điển cá nhân, làm sạch, chọn chế độ, viết lại email.
import { fileURLToPath } from 'node:url';
import { createDictionary } from './dictionary.js';
import { loadFillerRules, removeFillers, normalizeText } from './clean.js';
import { rewriteEmail } from './rewrite.js';
import { suggestCorrections } from './learn.js';
import { MODES, validateConfig, expandHome } from './config.js';

export { loadConfig, DEFAULT_CONFIG } from './config.js';

export const DEFAULT_SEED_PATH = fileURLToPath(new URL('../../config/dictionary.seed.json', import.meta.url));

export class PostError extends Error {
  /** @param {string} message */
  constructor(message) {
    super(message);
    this.code = 'bad_request';
  }
}

/** Log mặc định: một dòng JSON lên stderr, chỉ chứa sự kiện và mã lỗi (không văn bản, không khoá). */
function defaultLog(/** @type {object} */ event) {
  process.stderr.write(`${JSON.stringify({ src: 'vflow.post', ...event })}\n`);
}

/**
 * @param {{ dictionaryPath: string, config?: object, fetchImpl?: typeof fetch, now?: () => Date,
 *           seedPath?: string, log?: (event: object) => void }} opts
 *   config: kết quả loadConfig() (hoặc object thô, sẽ được kiểm lại). seedPath/log là tuỳ chọn mở rộng.
 */
export function createPostProcessor({
  dictionaryPath,
  config = {},
  fetchImpl = fetch,
  now = () => new Date(),
  seedPath = DEFAULT_SEED_PATH,
  log = defaultLog,
}) {
  const cfg = validateConfig(config);
  const dict = createDictionary({ path: typeof dictionaryPath === 'string' ? expandHome(dictionaryPath) : dictionaryPath, seedPath, now, log });
  const fillerRules = loadFillerRules();

  /** @param {string} mode @param {unknown} app */
  function resolveMode(mode, app) {
    if (mode !== 'auto') return mode;
    return (typeof app === 'string' && Object.hasOwn(cfg.auto.apps, app) && cfg.auto.apps[app]) || 'normal';
  }

  return {
    /**
     * @param {{ textRaw: string, mode?: string, app?: string }} args
     * @returns {Promise<{ text: string, mode: string, applied: {type:string,from:string,to:string}[],
     *                     rewrite: { used: boolean, error: string|null } }>}
     *   mode: chế độ thực sự đã áp (auto đã được phân giải).
     */
    async process({ textRaw, mode = 'normal', app }) {
      if (typeof textRaw !== 'string') throw new PostError('textRaw phải là chuỗi');
      if (!MODES.includes(mode)) throw new PostError(`chế độ không hợp lệ: ${String(mode).slice(0, 20)}`);
      const effective = resolveMode(mode, app);
      const rewrite = { used: false, error: null };
      const raw = textRaw.normalize('NFC');
      if (raw.trim() === '') return { text: '', mode: effective, applied: [], rewrite };

      if (effective === 'clean') {
        const f = removeFillers(raw, fillerRules);
        const d = dict.apply(f.text);
        const text = normalizeText(d.text, { exactTerms: dict.exactTerms() });
        return { text, mode: effective, applied: [...f.applied, ...d.applied], rewrite };
      }

      const d = dict.apply(raw);
      if (effective === 'normal') return { text: d.text, mode: effective, applied: d.applied, rewrite };

      const r = await rewriteEmail({ text: d.text, rewrite: cfg.rewrite, fetchImpl });
      if (r.error !== null) {
        log({ event: 'rewrite_failed', code: r.error });
        return { text: d.text, mode: effective, applied: d.applied, rewrite: { used: false, error: r.error } };
      }
      return { text: r.text, mode: effective, applied: d.applied, rewrite: { used: true, error: null } };
    },

    dictionary: {
      list: () => dict.list(),
      /** @param {unknown} entries */
      replaceAll: (entries) => dict.replaceAll(entries),
      /** @param {{ before: unknown, after: unknown }} input */
      learnCorrection: (input) => suggestCorrections(input ?? {}, dict.list().entries),
    },
  };
}
