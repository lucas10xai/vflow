// Hậu xử lý văn bản STT: từ điển cá nhân, làm sạch, chọn chế độ, LLM (tidy/email), devspeech,
// hành động (enter), snippets (tuỳ chọn, từ E1b), Command Mode.
import { fileURLToPath } from 'node:url';
import { createDictionary } from './dictionary.js';
import { loadFillerRules, removeFillers, normalizeText } from './clean.js';
import { applyDevspeech } from './devspeech.js';
import { extractEnterAction } from './actions.js';
import { applyVoicePunctuation } from './punctuation.js';
import { applyContextSymbols } from './contextsymbols.js';
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
 *           snippets?: SnippetsPort, settings?: SettingsPort,
 *           corrections?: ReturnType<typeof import('./learn.js').createCorrectionsStore> }} opts
 *   config: kết quả loadConfig() (hoặc object thô, sẽ được kiểm lại). seedPath/log là tuỳ chọn mở rộng.
 *   snippets/settings: tuỳ chọn, cung cấp bởi phần snippets/settings (E1b); vắng mặt ⇒ dùng mặc định
 *   (cloud_llm:true, llm_model từ config.rewrite.model, actions_enabled:true, không snippet).
 *   settings.get() được gọi lại ở MỖI yêu cầu (có hiệu lực ngay, không cache).
 *   corrections: tuỳ chọn (item 8); vắng mặt ⇒ dictionary.suggestions() luôn rỗng, learnCorrection
 *   không lưu gì (chỉ gợi ý ngay như trước).
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
  corrections,
}) {
  const cfg = validateConfig(config);
  const dict = createDictionary({ path: typeof dictionaryPath === 'string' ? expandHome(dictionaryPath) : dictionaryPath, seedPath, now, log });
  const fillerRules = loadFillerRules();

  /**
   * Chế độ `auto` tra `app_rules` (settings, item 4) TRƯỚC luật cứng `cfg.auto.apps`. Luật chọn
   * chế độ đám mây (tidy/email) chỉ có hiệu lực khi `cloud_llm` bật; tắt thì rơi về `clean` và báo
   * `degradedReason:"cloud_disabled"` (client hiểu vì sao tidy/email không chạy dù có luật).
   * @param {string} mode @param {unknown} app @param {ReturnType<typeof currentSettings>} s
   * @returns {{ mode: string, degradedReason: string|null }}
   */
  function resolveMode(mode, app, s) {
    if (mode !== 'auto') return { mode, degradedReason: null };
    const byRule = typeof app === 'string' && Object.hasOwn(s.app_rules, app) ? s.app_rules[app] : null;
    const byHard = typeof app === 'string' && Object.hasOwn(cfg.auto.apps, app) ? cfg.auto.apps[app] : null;
    const target = byRule || byHard || 'normal';
    if ((target === 'tidy' || target === 'email') && !s.cloud_llm) {
      return { mode: 'clean', degradedReason: 'cloud_disabled' };
    }
    return { mode: target, degradedReason: null };
  }

  /** llm.error -> degraded_reason công khai (contract/engine-api.md mục "Thời hạn LLM"). */
  function mapDegradedReason(llmError) {
    if (llmError === 'cloud_disabled') return 'cloud_disabled';
    if (llmError === 'timeout') return 'llm_timeout';
    if (llmError === 'guard_rejected') return 'guard';
    return 'llm_error';
  }

  /** Cài đặt hiệu lực hiện tại; gọi lại mỗi yêu cầu, không cache. */
  function currentSettings() {
    const s = (typeof settings?.get === 'function' ? settings.get() : null) ?? {};
    return {
      cloud_llm: s.cloud_llm ?? true,
      llm_model: s.llm_model ?? cfg.rewrite.model,
      llm_timeout_ms: s.llm_timeout_ms ?? cfg.rewrite.timeout_ms,
      actions_enabled: s.actions_enabled ?? true,
      app_rules: s.app_rules ?? {},
      voice_punctuation: s.voice_punctuation ?? true,
      context_symbols: s.context_symbols ?? true,
      tone: s.tone ?? 'neutral',
      learn_from_edits: s.learn_from_edits ?? true,
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
     *                     rewrite: { used: boolean, error: string|null }, actions: string[],
     *                     degraded: boolean, degraded_reason: string|null }>}
     *   mode: chế độ thực sự đã áp (auto đã được phân giải).
     *   degraded/degraded_reason (item 7, contract/engine-api.md mục "Thời hạn LLM"): true khi kết
     *   quả là bản dự phòng cục bộ thay cho đám mây đã định (quá giờ/lỗi/guard từ chối, hoặc luật
     *   app_rules chọn đám mây nhưng cloud_llm đang tắt).
     */
    async process({ textRaw, mode = 'normal', app }) {
      if (typeof textRaw !== 'string') throw new PostError('textRaw phải là chuỗi');
      if (!MODES.includes(mode)) throw new PostError(`chế độ không hợp lệ: ${String(mode).slice(0, 20)}`);
      const s = currentSettings();
      const resolved = resolveMode(mode, app, s);
      const effective = resolved.mode;
      const rewrite = { used: false, error: null };
      const degradedBase = { degraded: resolved.degradedReason !== null, degraded_reason: resolved.degradedReason };
      const raw = textRaw.normalize('NFC');
      if (raw.trim() === '') return { text: '', mode: effective, applied: [], rewrite, actions: [], ...degradedBase };

      // 1) Snippets: cả câu khớp trigger, hoặc "chèn <trigger>" ⇒ trả nguyên văn, bỏ qua mọi bước sau.
      if (typeof snippets?.expand === 'function') {
        const sn = snippets.expand(raw);
        if (sn?.matched) return { text: sn.text, mode: effective, applied: sn.applied ?? [], rewrite, actions: [], degraded: false, degraded_reason: null };
      }

      // 2) Hành động cuối câu ("nhấn/bấm enter").
      const act = extractEnterAction(raw, { actionsEnabled: s.actions_enabled });

      // 3) Từ điển.
      const d = dict.apply(act.text);

      // 3b) Ký hiệu theo ngữ cảnh (A4): MỌI chế độ, chạy TRƯỚC devspeech/dấu câu (cụm dài như "hai
      // chấm hai gạch chéo" ⇒ "://" phải được bắt trước khi devspeech cắt "hai chấm" ⇒ "https:hai/").
      // Chỉ có hiệu lực khi `app` thuộc danh sách cho phép (terminal/IDE/chat/AI) và context_symbols
      // bật. Terminal/IDE ở chế độ auto ⇒ dev, nên dev PHẢI chạy bước này, nếu không tính năng gần
      // như vô hiệu đúng ở những app nó dành cho.
      const symbolsEnabled = s.context_symbols !== false;
      const cs = symbolsEnabled ? applyContextSymbols(d.text, { app }) : { text: d.text, applied: [] };

      // 4) Dấu câu bằng giọng (item 5): mọi chế độ TRỪ dev, trừ khi bị tắt.
      const voiceEnabled = effective !== 'dev' && s.voice_punctuation !== false;
      const vp = voiceEnabled ? applyVoicePunctuation(cs.text) : { text: cs.text, applied: [] };

      if (effective === 'normal') {
        return { text: vp.text, mode: effective, applied: [...d.applied, ...cs.applied, ...vp.applied], rewrite, actions: act.actions, degraded: false, degraded_reason: null };
      }

      if (effective === 'clean') {
        const c = cleanRules(vp.text);
        return { text: c.text, mode: effective, applied: [...d.applied, ...cs.applied, ...vp.applied, ...c.applied], rewrite, actions: act.actions, ...degradedBase };
      }

      if (effective === 'dev') {
        const c = cleanRules(cs.text);
        const ds = applyDevspeech(c.text);
        return { text: ds.text, mode: effective, applied: [...d.applied, ...cs.applied, ...c.applied, ...ds.applied], rewrite, actions: act.actions, degraded: false, degraded_reason: null };
      }

      if (effective === 'tidy') {
        // Thứ tự an toàn (không đổi hành vi devspeech đã có): devspeech trước (bắt đủ "mở ngoặc
        // vuông/nhọn/tròn"…), dấu câu bằng giọng sau (bắt phần devspeech không biết: "dấu chấm",
        // "chấm than", "xuống dòng"…). Biết hạn chế: "dấu hai chấm" trong tidy có thể bị quy tắc
        // devspeech "hai chấm" bắt một phần trước — xem contract/engine-api.md.
        const ds = applyDevspeech(cs.text);
        const vp2 = voiceEnabled ? applyVoicePunctuation(ds.text) : { text: ds.text, applied: [] };
        const c = cleanRules(vp2.text);
        const fallbackApplied = [...d.applied, ...cs.applied, ...ds.applied, ...vp2.applied, ...c.applied];
        const r = await tidyText({ text: c.text, rewrite: cfg.rewrite, settings: s, guard: cfg.tidy.guard, fetchImpl });
        if (r.error !== null) {
          log({ event: 'tidy_failed', code: r.error });
          return { text: c.text, mode: effective, applied: fallbackApplied, rewrite: { used: false, error: r.error }, actions: act.actions, degraded: true, degraded_reason: mapDegradedReason(r.error) };
        }
        return { text: r.text, mode: effective, applied: fallbackApplied, rewrite: { used: true, error: null }, actions: act.actions, degraded: false, degraded_reason: null };
      }

      // email
      const r = await rewriteEmail({ text: vp.text, rewrite: cfg.rewrite, settings: s, fetchImpl });
      if (r.error !== null) {
        log({ event: 'rewrite_failed', code: r.error });
        return { text: vp.text, mode: effective, applied: [...d.applied, ...cs.applied, ...vp.applied], rewrite: { used: false, error: r.error }, actions: act.actions, degraded: true, degraded_reason: mapDegradedReason(r.error) };
      }
      return { text: r.text, mode: effective, applied: [...d.applied, ...cs.applied, ...vp.applied], rewrite: { used: true, error: null }, actions: act.actions, degraded: false, degraded_reason: null };
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
      /**
       * Gợi ý ngay (như trước) VÀ, nếu có kho `corrections` và `learn_from_edits` đang bật, lưu
       * sự sửa lại để tổng hợp `GET /v1/dictionary/suggestions` (item 8).
       * @param {{ before: unknown, after: unknown }} input
       */
      learnCorrection: (input) => {
        const result = suggestCorrections(input ?? {}, dict.list().entries);
        if (corrections && currentSettings().learn_from_edits !== false) {
          corrections.record(input?.before, input?.after);
        }
        return result;
      },
      /** `GET /v1/dictionary/suggestions` (item 8): chỉ gồm cặp xuất hiện ≥ 2 lần, chưa có trong từ điển. */
      suggestions: () => (corrections ? corrections.suggestions(dict.list().entries) : { suggestions: [] }),
      /** `POST /v1/dictionary/suggestions/dismiss` (item 8). @param {string} term */
      dismissSuggestion: (term) => (corrections ? corrections.dismiss(term) : { ok: true }),
      /** `POST /v1/partial` (item 9): CHỈ từ điển, không hiệu ứng phụ (không tăng uses/ghi tệp). */
      applyPreview: (text) => dict.applyPreview(text),
    },
  };
}
