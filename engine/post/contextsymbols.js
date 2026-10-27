// A4 (context_symbols): ký hiệu lập trình/URL theo NGỮ CẢNH ứng dụng đích. Chạy trong hậu xử lý
// cùng bước với dấu câu bằng giọng (engine/post/punctuation.js) — chỉ áp dụng khi `app` (bundle id
// request gửi lên) thuộc danh sách ứng dụng terminal/IDE/AI/chat nhóm mã hoá cứng dưới đây; ngoài
// danh sách đó các cụm như "gạch chéo"/"a còng" PHẢI giữ nguyên là chữ thường (lời nói bình thường).
//
// Bundle id mã hoá cứng đã được tra chéo nhiều nguồn công khai (xem báo cáo E3); một vài công cụ
// AI nêu trong yêu cầu (Codex dạng app macOS riêng, Orca, Windsurf sau khi đổi tên) KHÔNG có bundle
// id nào xác nhận được chắc chắn tại thời điểm viết — bỏ qua CHỦ Ý thay vì đoán (truth-first), xem
// contract/engine-api.md mục "Ký hiệu theo ngữ cảnh".
import { tokenize, fold } from './text.js';

export const ALLOWED_APPS = new Set([
  // Terminal
  'com.apple.Terminal', 'com.googlecode.iterm2', 'dev.warp.Warp-Stable', 'com.mitchellh.ghostty',
  'org.alacritty', 'io.alacritty', 'net.kovidgoyal.kitty', 'com.github.wez.wezterm',
  // IDE / trình soạn thảo
  'com.microsoft.VSCode', 'com.microsoft.VSCodeInsiders', 'com.vscodium',
  'com.todesktop.230313mzl4w4u92', // Cursor (cùng id đã dùng ở config/config.js auto.apps)
  'com.apple.dt.Xcode', 'dev.zed.Zed', 'com.sublimetext.3', 'com.sublimetext.4', 'com.panic.Nova',
  // Công cụ AI (chỉ các id xác nhận được)
  'com.anthropic.claudefordesktop', 'com.openai.chat',
  // Chat nhóm
  'com.tinyspeck.slackmacgap', 'com.hnc.Discord', 'com.microsoft.teams2', 'com.microsoft.teams',
]);
/** Họ JetBrains: rất nhiều id (com.jetbrains.intellij, .pycharm, .WebStorm, .goland, …) — so khớp tiền tố. */
const JETBRAINS_PREFIX = 'com.jetbrains.';
/** Chỉ Slack/Discord mới có quy tắc "/lệnh ở ĐẦU câu" (lệnh slash của chat, không áp cho IDE/terminal). */
const SLASH_COMMAND_APPS = new Set(['com.tinyspeck.slackmacgap', 'com.hnc.Discord']);
/** Chat nhóm: "a còng nam" là NHẮC TÊN ("chào @nam") — giữ khoảng trắng đứng trước. Terminal/IDE thì dính liền
 * ("nam a còng gmail" ⇒ "nam@gmail", dạng email/cấu hình). */
const MENTION_APPS = new Set(['com.tinyspeck.slackmacgap', 'com.hnc.Discord', 'com.microsoft.teams2', 'com.microsoft.teams']);

/** So khớp bundle id CHÍNH XÁC (phân biệt hoa/thường — không fold/lowercase). @param {unknown} app */
export function isAllowedApp(app) {
  if (typeof app !== 'string' || app === '') return false;
  if (ALLOWED_APPS.has(app)) return true;
  return app.startsWith(JETBRAINS_PREFIX);
}

/** @typedef {{ words: string[], output: string, keepLeft: boolean }} Rule */

/** @type {Rule[]} */
const SYMBOL_RULES = [
  { phrase: 'hai chấm hai gạch chéo', output: '://' },
  { phrase: 'gạch chéo ngược', output: '\\' },
  { phrase: 'gạch chéo', output: '/' },
  // Cờ dòng lệnh: "git gạch nối gạch nối help" ⇒ "git --help" (giữ khoảng trắng TRƯỚC, dính vào từ sau).
  // Một "gạch nối" đơn vẫn dính hai phía ("a gạch nối b" ⇒ "a-b").
  { phrase: 'gạch nối gạch nối', output: '--', keepLeft: true },
  { phrase: 'gạch nối', output: '-' },
  { phrase: 'gạch dưới', output: '_' },
  { phrase: 'a còng', output: '@' },
  { phrase: 'dấu thăng', output: '#' },
  { phrase: 'dấu đô la', output: '$' },
  { phrase: 'dấu và', output: '&' },
  { phrase: 'dấu sao', output: '*' },
  { phrase: 'dấu bằng', output: '=' },
  { phrase: 'dấu cộng', output: '+' },
]
  .map((r) => ({ words: r.phrase.split(' ').map(fold), output: r.output, keepLeft: r.keepLeft === true }))
  .sort((a, b) => b.words.length - a.words.length);

/** Khoảng cách được phép giữa các từ của một cụm: chỉ khoảng trắng/gạch nối. */
const JOINER_RE = /^[\s\-‐‑–]+$/u;
/** Dấu kết mệnh đề: không coi là "liền sau" nếu có dấu câu này giữa hai token. */
const CLAUSE_BREAK_RE = /[.,!?;:…\n]/;

const ACONG_WORDS = fold('a còng').split(' ');
const GACHCHEO_WORDS = fold('gạch chéo').split(' ');

/**
 * @param {import('./text.js').Token[]} toks @param {number} i @param {string} text @param {string[]} words
 * @returns {number|null} chỉ số token cuối của cụm, hoặc null nếu không khớp tại i
 */
function matchWordsAt(toks, i, text, words) {
  if (i + words.length > toks.length) return null;
  for (let k = 0; k < words.length; k++) {
    if (toks[i + k].folded !== words[k]) return null;
    if (k > 0 && !JOINER_RE.test(text.slice(toks[i + k - 1].end, toks[i + k].start))) return null;
  }
  return i + words.length - 1;
}

/** Từ ngay sau cụm (endIndex) có phải một "tên" liền mạch để nuốt vào lệnh/mention không? */
function hasAttachableWordAfter(toks, endIndex, text) {
  if (endIndex + 1 >= toks.length) return false;
  const gap = text.slice(toks[endIndex].end, toks[endIndex + 1].start);
  if (CLAUSE_BREAK_RE.test(gap)) return false;
  return true;
}

/** @param {import('./text.js').Token[]} toks @param {number} i @param {string} text */
function matchSymbolRule(toks, i, text) {
  for (const rule of SYMBOL_RULES) {
    const end = matchWordsAt(toks, i, text, rule.words);
    if (end !== null) return { endIndex: end, output: rule.output, keepLeft: rule.keepLeft };
  }
  return null;
}

/** Ký hiệu một ký tự (hoặc cụm) không phải chữ/số: dính liền hai bên (vd "/", "://", "@", "_"). */
const isGlue = (output) => !/[\p{L}\p{N}]/u.test(output);

/**
 * Khoảng trắng "để gõ tiếp" sau `@tên`/`/lệnh` CHỈ khi phía sau còn chữ/số (bỏ qua khoảng trắng):
 * cuối câu hoặc trước dấu câu/xuống dòng thì không thêm (tránh "an@example " dư dấu cách cuối).
 * @param {string} text @param {number} pos vị trí ngay sau từ vừa nuốt
 */
function spaceIfWordFollows(text, pos) {
  const m = /^[ \t]*(\S)/u.exec(text.slice(pos));
  return m && /[\p{L}\p{N}]/u.test(m[1]) ? ' ' : '';
}

/**
 * @param {string} text NFC (toàn bộ câu nói, ĐÃ qua từ điển — chạy cùng bước voice_punctuation)
 * @param {{ app?: string }} [opts]
 * @returns {{ text: string, applied: {type:'context_symbol', from:string, to:string}[] }}
 */
export function applyContextSymbols(text, { app } = {}) {
  if (!isAllowedApp(app)) return { text, applied: [] };
  const toks = tokenize(text);
  if (toks.length === 0) return { text, applied: [] };
  /** @type {{type:'context_symbol', from:string, to:string}[]} */
  const applied = [];
  let out = '';
  let cursor = 0;
  let i = 0;
  while (i < toks.length) {
    // "/lệnh" ở ĐẦU CÂU, chỉ Slack/Discord: "gạch chéo deploy" ⇒ "/deploy " (dính liền + 1 khoảng
    // trắng để gõ tiếp — khác quy tắc glue chung vì đây là lệnh, không phải nối đường dẫn).
    if (i === 0 && SLASH_COMMAND_APPS.has(app)) {
      const end = matchWordsAt(toks, i, text, GACHCHEO_WORDS);
      if (end !== null && hasAttachableWordAfter(toks, end, text)) {
        const wordTok = toks[end + 1];
        out += text.slice(cursor, toks[i].start);
        out += `/${wordTok.word}${spaceIfWordFollows(text, wordTok.end)}`;
        applied.push({ type: 'context_symbol', from: text.slice(toks[i].start, wordTok.end), to: `/${wordTok.word}` });
        cursor = wordTok.end;
        const after = /^[ \t]+/u.exec(text.slice(cursor));
        if (after) cursor += after[0].length;
        i = end + 2;
        continue;
      }
    }
    // "@tên": "a còng nam" ⇒ "@nam " (dính liền + 1 khoảng trắng), ở bất kỳ vị trí trong câu.
    {
      const end = matchWordsAt(toks, i, text, ACONG_WORDS);
      if (end !== null && hasAttachableWordAfter(toks, end, text)) {
        const wordTok = toks[end + 1];
        out += MENTION_APPS.has(app) ? text.slice(cursor, toks[i].start) : text.slice(cursor, toks[i].start).replace(/[ \t]+$/u, '');
        out += `@${wordTok.word}${spaceIfWordFollows(text, wordTok.end)}`;
        applied.push({ type: 'context_symbol', from: text.slice(toks[i].start, wordTok.end), to: `@${wordTok.word}` });
        cursor = wordTok.end;
        const after = /^[ \t]+/u.exec(text.slice(cursor));
        if (after) cursor += after[0].length;
        i = end + 2;
        continue;
      }
    }
    const m = matchSymbolRule(toks, i, text);
    if (!m) { i++; continue; }
    const from = text.slice(toks[i].start, toks[m.endIndex].end);
    out += text.slice(cursor, toks[i].start);
    if (isGlue(m.output) && !m.keepLeft) out = out.replace(/[ \t]+$/u, '');
    out += m.output;
    cursor = toks[m.endIndex].end;
    if (isGlue(m.output)) {
      const after = /^[ \t]+/u.exec(text.slice(cursor));
      if (after) cursor += after[0].length;
    }
    applied.push({ type: 'context_symbol', from, to: m.output });
    i = m.endIndex + 1;
  }
  out += text.slice(cursor);
  return { text: out, applied };
}
