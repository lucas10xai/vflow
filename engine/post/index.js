// Hậu xử lý văn bản STT: từ điển cá nhân, làm sạch, chọn chế độ, LLM (tidy/email), devspeech,
// hành động (enter), snippets (tuỳ chọn, từ E1b), Command Mode.
import { fileURLToPath } from 'node:url';
import { createDictionary } from './dictionary.js';
import { loadFillerRules, removeFillers, normalizeText } from './clean.js';
import { applyDevspeech } from './devspeech.js';
import { extractEnterAction } from './actions.js';
import { rewriteEmail } from './rewrite.js';
import { tidyText } from './tidy.js';
import { runCommand } from './command.js';
import { suggestCorrections } from './learn.js';
import { MODES, validateConfig, expandHome } from './config.js';

export { loadConfig, DEFAULT_CONFIG } from './config.js';
export { CommandError } from './command.js';

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
 * @typedef {{ expand: (text: string) => { text: string, applied: {type:string,from:string,to:string}[], matched: boolean } }} SnippetsPort
 * @typedef {{ get: () => { cloud_llm?: boolean, llm_model?: string|null, llm_timeout_ms?: number, actions_enabled?: boolean } }} SettingsPort
 */

/**
 * @param {{ dictionaryPath: string, config?: object, fetchImpl?: typeof fetch, now?: () => Date,
 *           seedPath?: string, log?: (event: object) => void,
 *           snippets?: SnippetsPort, settings?: SettingsPort }} opts
 *   config: kết quả loadConfig() (hoặc object thô, sẽ được kiểm lại). seedPath/log là tuỳ chọn mở rộng.
 *   snippets/settings: tuỳ chọn, cung cấp bởi phần snippets/settings (E1b); vắng mặt ⇒ dùng mặc định
 *   (cloud_llm:true, llm_model từ config.rewrite.model, actions_enabled:true, không snippet).
 *   settings.get() được gọi lại ở MỖI yêu cầu (có hiệu lực ngay, không cache).
 */
export function createPostProcessor({
  dictionaryPath,
  config = {},
  fetchImpl = fetch,
  now = () => new Date(),
  seedPath = DEFAULT_SEED_PATH,
  log = defaultLog,
  snippets,
  settings,
}) {
  const cfg = validateConfig(config);
  const dict = createDictionary({ path: typeof dictionaryPath === 'string' ? expandHome(dictionaryPath) : dictionaryPath, seedPath, now, log });
  const fillerRules = loadFillerRules();

  /** @param {string} mode @param {unknown} app */
  function resolveMode(mode, app) {
    if (mode !== 'auto') return mode;
    return (typeof app === 'string' && Object.hasOwn(cfg.auto.apps, app) && cfg.auto.apps[app]) || 'normal';
  }

  /** Cài đặt hiệu lực hiện tại; gọi lại mỗi yêu cầu, không cache. */
  function currentSettings() {
    const s = (typeof settings?.get === 'function' ? settings.get() : null) ?? {};
    return {
      cloud_llm: s.cloud_llm ?? true,
      llm_model: s.llm_model ?? cfg.rewrite.model,
      llm_timeout_ms: s.llm_timeout_ms ?? cfg.rewrite.timeout_ms,
      actions_enabled: s.actions_enabled ?? true,
    };
  }

  /** Bỏ từ đệm + chuẩn hoá khoảng trắng/dấu câu/viết hoa. Thuần quy tắc. */
  function cleanRules(text) {
    const f = removeFillers(text, fillerRules);
    const normalized = normalizeText(f.text, { exactTerms: dict.exactTerms() });
    return { text: normalized, applied: f.applied };
  }

  return {
    /**
     * @param {{ textRaw: string, mode?: string, app?: string }} args
     * @returns {Promise<{ text: string, mode: string, applied: {type:string,from:string,to:string}[],
     *                     rewrite: { used: boolean, error: string|null }, actions: string[] }>}
     *   mode: chế độ thực sự đã áp (auto đã được phân giải).
     */
    async process({ textRaw, mode = 'normal', app }) {
      if (typeof textRaw !== 'string') throw new PostError('textRaw phải là chuỗi');
      if (!MODES.includes(mode)) throw new PostError(`chế độ không hợp lệ: ${String(mode).slice(0, 20)}`);
      const effective = resolveMode(mode, app);
      const rewrite = { used: false, error: null };
      const raw = textRaw.normalize('NFC');
      if (raw.trim() === '') return { text: '', mode: effective, applied: [], rewrite, actions: [] };

      const s = currentSettings();

      // 1) Snippets: cả câu khớp trigger, hoặc "chèn <trigger>" ⇒ trả nguyên văn, bỏ qua mọi bước sau.
      if (typeof snippets?.expand === 'function') {
        const sn = snippets.expand(raw);
        if (sn?.matched) return { text: sn.text, mode: effective, applied: sn.applied ?? [], rewrite, actions: [] };
      }

      // 2) Hành động cuối câu ("nhấn/bấm enter").
      const act = extractEnterAction(raw, { actionsEnabled: s.actions_enabled });

      // 3) Từ điển.
      const d = dict.apply(act.text);

      if (effective === 'normal') {
        return { text: d.text, mode: effective, applied: d.applied, rewrite, actions: act.actions };
      }

      if (effective === 'clean') {
        const c = cleanRules(d.text);
        return { text: c.text, mode: effective, applied: [...d.applied, ...c.applied], rewrite, actions: act.actions };
      }

      if (effective === 'dev') {
        const c = cleanRules(d.text);
        const ds = applyDevspeech(c.text);
        return { text: ds.text, mode: effective, applied: [...d.applied, ...c.applied, ...ds.applied], rewrite, actions: act.actions };
      }

      if (effective === 'tidy') {
        const ds = applyDevspeech(d.text);
        const c = cleanRules(ds.text);
        const fallbackApplied = [...d.applied, ...ds.applied, ...c.applied];
        const r = await tidyText({ text: c.text, rewrite: cfg.rewrite, settings: s, guard: cfg.tidy.guard, fetchImpl });
        if (r.error !== null) {
          log({ event: 'tidy_failed', code: r.error });
          return { text: c.text, mode: effective, applied: fallbackApplied, rewrite: { used: false, error: r.error }, actions: act.actions };
        }
        return { text: r.text, mode: effective, applied: fallbackApplied, rewrite: { used: true, error: null }, actions: act.actions };
      }

      // email
      const r = await rewriteEmail({ text: d.text, rewrite: cfg.rewrite, settings: s, fetchImpl });
      if (r.error !== null) {
        log({ event: 'rewrite_failed', code: r.error });
        return { text: d.text, mode: effective, applied: d.applied, rewrite: { used: false, error: r.error }, actions: act.actions };
      }
      return { text: r.text, mode: effective, applied: d.applied, rewrite: { used: true, error: null }, actions: act.actions };
    },

    /**
     * Command Mode (contract/engine-api.md): sửa (có selection) hoặc soạn mới (không có) theo lệnh.
     * Lỗi ném CommandError (.code, .message tiếng Việt); KHÔNG BAO GIỜ trả văn bản giả.
     * @param {{ instruction: string, selection?: string, context?: string, app?: string }} args
     * @returns {Promise<{ text: string, kind: 'edit'|'draft', timings_ms: { llm: number } }>}
     */
    async command({ instruction, selection = '', context = '' }) {
      const s = currentSettings();
      return runCommand({ instruction, selection, context, rewrite: cfg.rewrite, settings: s, fetchImpl });
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
