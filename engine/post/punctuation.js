// Lệnh dấu câu bằng giọng (contract/engine-api.md mục "Lệnh dấu câu bằng giọng"): từ khoá ĐỦ DÀI
// (≥ 2 từ) để không nhầm với lời nói thường ("chấm điểm", "câu hỏi" phải giữ nguyên — không có
// khoá nào chỉ một từ như "chấm"/"hỏi" đứng riêng). Chạy cho mọi chế độ TRỪ `dev` (caller quyết
// định, xem engine/post/index.js) và trừ khi bị tắt (settings.voice_punctuation=false).
import { tokenize } from './text.js';

/** @typedef {{ phrase: string, to: string }} Rule */

/** @type {Rule[]} */
const RULES = [
  { phrase: 'xuống hai dòng', to: '\n\n' },
  { phrase: 'xuống dòng', to: '\n' },
  { phrase: 'đoạn mới', to: '\n\n' },
  { phrase: 'dấu chấm phẩy', to: ';' },
  { phrase: 'dấu chấm than', to: '!' },
  { phrase: 'chấm than', to: '!' },
  { phrase: 'dấu hỏi chấm', to: '?' },
  { phrase: 'chấm hỏi', to: '?' },
  { phrase: 'dấu chấm', to: '.' },
  { phrase: 'dấu phẩy', to: ',' },
  { phrase: 'dấu hai chấm', to: ':' },
  { phrase: 'dấu ba chấm', to: '…' },
  { phrase: 'ba chấm', to: '…' },
  { phrase: 'mở ngoặc kép', to: '“' },
  { phrase: 'đóng ngoặc kép', to: '”' },
  { phrase: 'mở ngoặc', to: '(' },
  { phrase: 'đóng ngoặc', to: ')' },
  { phrase: 'dấu gạch ngang', to: '–' },
  { phrase: 'gạch ngang', to: '–' },
];

/** Dấu kết câu: viết hoa chữ cái ngay sau. "," ":" ";" KHÔNG nằm trong tập này. */
const SENTENCE_END = new Set(['.', '!', '?', '\n', '\n\n']);

/** Dính vào từ TRƯỚC (bỏ khoảng trắng trước dấu) — đúng yêu cầu contract cho , . ? ! : ; và mở rộng
 * hợp lý cho … ) ” (cùng nhóm "đóng"). */
const LEFT_ONLY = new Set(['.', ',', '?', '!', ':', ';', '…', ')', '”']);
/** Dính vào từ SAU (bỏ khoảng trắng sau dấu) — dấu "mở". */
const RIGHT_ONLY = new Set(['(', '“']);
/** Xuống dòng: bỏ khoảng trắng CẢ HAI phía (khoảng trắng quanh lệnh nói thường chỉ là ngẫu nhiên). */
const BOTH_SIDES = new Set(['\n', '\n\n']);

/** Khoảng cách được phép giữa các từ của một cụm lệnh: chỉ khoảng trắng/gạch nối. */
const JOINER_RE = /^[\s\-‐‑–]+$/u;

/**
 * @typedef {{ tokens: string[], to: string }} CompiledRule
 */

/** Lập chỉ mục: từ đầu (đã gấp) -> các cụm, cụm dài hơn khớp trước (vd "mở ngoặc kép" trước "mở ngoặc"). */
function compilePatterns() {
  /** @type {Map<string, CompiledRule[]>} */
  const map = new Map();
  for (const r of RULES) {
    const tokens = tokenize(r.phrase).map((t) => t.folded);
    if (tokens.length === 0) continue;
    const list = map.get(tokens[0]) ?? [];
    list.push({ tokens, to: r.to });
    map.set(tokens[0], list);
  }
  for (const list of map.values()) list.sort((a, b) => b.tokens.length - a.tokens.length);
  return map;
}

const PATTERNS = compilePatterns();

/**
 * @param {import('./text.js').Token[]} toks @param {number} i @param {string} text
 * @param {Map<string, CompiledRule[]>} patterns
 */
function matchAt(toks, i, text, patterns) {
  const candidates = patterns.get(toks[i].folded);
  if (!candidates) return null;
  outer: for (const c of candidates) {
    if (i + c.tokens.length > toks.length) continue;
    for (let k = 1; k < c.tokens.length; k++) {
      if (toks[i + k].folded !== c.tokens[k]) continue outer;
      if (!JOINER_RE.test(text.slice(toks[i + k - 1].end, toks[i + k].start))) continue outer;
    }
    return { length: c.tokens.length, to: c.to };
  }
  return null;
}

/**
 * Thay các cụm lệnh dấu câu bằng ký hiệu tương ứng; dính dấu vào từ trước (bỏ khoảng trắng thừa),
 * tự viết hoa chữ cái đầu tiên sau mỗi dấu kết câu (. ? ! và xuống dòng) — không viết hoa sau , : ;.
 * @param {string} text NFC
 * @returns {{ text: string, applied: {type:'voice_punctuation', from:string, to:string}[] }}
 */
export function applyVoicePunctuation(text) {
  const toks = tokenize(text);
  /** @type {{type:'voice_punctuation', from:string, to:string}[]} */
  const applied = [];
  /** @type {number[]} vị trí trong `out` ngay sau một dấu kết câu — cần viết hoa chữ tiếp theo */
  const boundaries = [];
  let out = '';
  let cursor = 0;
  for (let i = 0; i < toks.length; ) {
    const hit = matchAt(toks, i, text, PATTERNS);
    if (!hit) {
      i++;
      continue;
    }
    const start = toks[i].start;
    let end = toks[i + hit.length - 1].end;
    const stripBefore = LEFT_ONLY.has(hit.to) || BOTH_SIDES.has(hit.to);
    const stripAfter = RIGHT_ONLY.has(hit.to) || BOTH_SIDES.has(hit.to);
    const before = stripBefore ? text.slice(cursor, start).replace(/[ \t]+$/u, '') : text.slice(cursor, start);
    // Whisper thường đã trả dấu câu. Không nhân đôi đúng cùng dấu khi người nói vẫn đọc lệnh.
    const duplicate = LEFT_ONLY.has(hit.to) && before.endsWith(hit.to);
    out += before + (duplicate ? '' : hit.to);
    if (SENTENCE_END.has(hit.to)) boundaries.push(out.length);
    applied.push({ type: 'voice_punctuation', from: text.slice(start, end), to: hit.to });
    if (stripAfter) {
      const after = /^[ \t]+/u.exec(text.slice(end));
      if (after) end += after[0].length;
    }
    cursor = end;
    i += hit.length;
  }
  out += text.slice(cursor);

  let result = out;
  for (const b of boundaries) {
    const m = /\p{L}/u.exec(result.slice(b));
    if (m && /\p{Ll}/u.test(m[0])) {
      const at = b + m.index;
      result = result.slice(0, at) + result[at].toUpperCase() + result.slice(at + 1);
    }
  }
  return { text: result, applied };
}
