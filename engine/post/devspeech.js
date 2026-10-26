// Quy tắc đọc kiểu lập trình (chế độ dev, và dùng trong tidy trước khi gửi LLM). Thuần quy tắc,
// không gọi gì ra ngoài. Bảng cụm->ký hiệu khai báo ở DATA bên dưới, không rải mã rải rác.
import { readFileSync } from 'node:fs';
import { fold, tokenize, capitalize } from './text.js';

/** @typedef {{ compound_max_words: number, compound_stop_words: string[] }} DevspeechData */

/** @returns {DevspeechData} */
function loadDevspeechData(path = new URL('./devspeech.data.json', import.meta.url)) {
  return JSON.parse(readFileSync(path, 'utf8'));
}

const DATA = loadDevspeechData();
/** Số từ tối đa một cụm đặt tên biến nuốt (xem devspeech.data.json). */
const COMPOUND_MAX_WORDS = DATA.compound_max_words;
/** Từ nối/chuyển ý thông dụng: cụm đặt tên biến dừng NGAY trước từ này, giữ nguyên văn phần sau. */
const COMPOUND_STOP_WORDS = DATA.compound_stop_words.map((p) => p.split(' ').map(fold));

/** Cụm cố định -> ký hiệu. Sắp theo số từ giảm dần để khớp cụm dài nhất trước. */
const SYMBOL_RULES = [
  { phrase: 'mở ngoặc vuông', output: '[' },
  { phrase: 'đóng ngoặc vuông', output: ']' },
  { phrase: 'mở ngoặc nhọn', output: '{' },
  { phrase: 'đóng ngoặc nhọn', output: '}' },
  { phrase: 'mở ngoặc tròn', output: '(' },
  { phrase: 'đóng ngoặc tròn', output: ')' },
  { phrase: 'dấu nháy đơn', output: "'" },
  { phrase: 'dấu nháy kép', output: '"' },
  { phrase: 'gạch dưới', output: '_' },
  { phrase: 'gạch ngang', output: '-' },
  { phrase: 'gạch chéo', output: '/' },
  { phrase: 'sờ lát', output: '/' },
  { phrase: 'hai chấm', output: ':' },
  { phrase: 'dấu bằng', output: '=' },
  { phrase: 'mở ngoặc', output: '(' },
  { phrase: 'đóng ngoặc', output: ')' },
  { phrase: 'dấu nháy', output: "'" },
]
  .map((r) => ({ words: r.phrase.split(' ').map(fold), output: r.output }))
  .sort((a, b) => b.words.length - a.words.length);

/** Cụm đặt tên biến -> kiểu ghép chữ, áp cho các từ còn lại của câu phía sau cụm. */
const COMPOUND_RULES = [
  { phrase: 'viết thường nối gạch dưới', style: 'snake' },
  { phrase: 'viết hoa nối', style: 'camel' },
  { phrase: 'camel case', style: 'camel' },
  { phrase: 'pascal case', style: 'pascal' },
  { phrase: 'kebab case', style: 'kebab' },
]
  .map((r) => ({ words: r.phrase.split(' ').map(fold), style: r.style }))
  .sort((a, b) => b.words.length - a.words.length);

/** Đuôi tệp biết trước: "chấm" ngay trước đuôi này luôn thành ".". */
const KNOWN_EXTENSIONS = new Set([
  'js', 'jsx', 'mjs', 'ts', 'tsx', 'py', 'md', 'json', 'sh', 'bash', 'yaml', 'yml',
  'swift', 'html', 'css', 'scss', 'txt', 'xml', 'toml', 'rs', 'go', 'java', 'rb', 'c', 'cpp', 'h',
]);

const FOLD_CHAM = fold('chấm');

/**
 * Từ tiếng Việt thông dụng KHÔNG dấu trùng hình với chữ Latin (đại từ, số đếm...): loại khỏi quy
 * tắc "chấm giữa hai định danh" để tránh đổi nhầm "hai chấm ba", "anh chấm em". Danh sách KHÔNG
 * đầy đủ (giống rủi ro đã biết ở dictionary.seed.json) — chỉ chặn các trường hợp thường gặp nhất.
 */
const COMMON_VI_ASCII_WORDS = new Set([
  'anh', 'em', 'con', 'ba', 'hai', 'nam', 'nay', 'mai', 'cho', 'do', 'vi', 'can', 'to', 'la',
  'toi', 'minh', 'may', 'tao', 'no', 'ta', 'ca', 'da', 'ga', 'ra', 'sa', 'va', 'xa', 'gia', 'sang',
]);

/** Từ chỉ chứa chữ/số ASCII (giống định danh lập trình: biến, tên tệp, đuôi tệp...). */
function isAsciiIdentifier(word) {
  return /^[A-Za-z][A-Za-z0-9]*$/.test(word) && !COMMON_VI_ASCII_WORDS.has(word.toLowerCase());
}

/** Ký hiệu một ký tự không phải chữ/số: luôn dính liền hai bên (glue), vd "_","/",".". */
function isGlueSymbol(output) {
  return output.length === 1 && !/[\p{L}\p{N}]/u.test(output);
}

/**
 * @param {string[]} words (đã fold) @param {'snake'|'camel'|'pascal'|'kebab'} style
 */
function buildName(words, style) {
  if (style === 'snake') return words.join('_');
  if (style === 'kebab') return words.join('-');
  if (style === 'camel') return words.map((w, i) => (i === 0 ? w : capitalize(w))).join('');
  return words.map((w) => capitalize(w)).join(''); // pascal
}

/** @param {import('./text.js').Token[]} toks @param {number} i */
function matchSymbolRule(toks, i) {
  for (const rule of SYMBOL_RULES) {
    const n = rule.words.length;
    if (i + n > toks.length) continue;
    if (rule.words.every((w, k) => toks[i + k].folded === w)) return { endIndex: i + n - 1, output: rule.output };
  }
  // "chấm" → "." chỉ khi giữa hai định danh liền kề hoặc ngay trước đuôi tệp biết trước.
  if (toks[i].folded === FOLD_CHAM && i > 0 && i + 1 < toks.length) {
    const prevWord = toks[i - 1].word;
    const nextWord = toks[i + 1].word;
    const nextIsExt = KNOWN_EXTENSIONS.has(nextWord.toLowerCase());
    const bothIdentifiers = isAsciiIdentifier(prevWord) && isAsciiIdentifier(nextWord);
    if (nextIsExt || bothIdentifiers) return { endIndex: i, output: '.' };
  }
  return null;
}

/** Cuối một mệnh đề: dấu câu giữa hai token kề nhau. */
const CLAUSE_END_RE = /[.,!?;:…]/;

/** Từ nối/chuyển ý (COMPOUND_STOP_WORDS) bắt đầu đúng tại vị trí j? @param {import('./text.js').Token[]} toks @param {number} j */
function matchStopWordAt(toks, j) {
  for (const sw of COMPOUND_STOP_WORDS) {
    const n = sw.length;
    if (j + n > toks.length) continue;
    if (sw.every((w, k) => toks[j + k].folded === w)) return true;
  }
  return false;
}

/** @param {import('./text.js').Token[]} toks @param {number} i @param {string} text */
function matchCompoundRule(toks, i, text) {
  for (const rule of COMPOUND_RULES) {
    const n = rule.words.length;
    if (i + n > toks.length) continue;
    if (!rule.words.every((w, k) => toks[i + k].folded === w)) continue;
    const argsStart = i + n;
    let end = argsStart - 1;
    const words = [];
    for (let j = argsStart; j < toks.length; j++) {
      if (j > argsStart && CLAUSE_END_RE.test(text.slice(toks[j - 1].end, toks[j].start))) break;
      if (words.length >= COMPOUND_MAX_WORDS) break;
      if (matchStopWordAt(toks, j)) break;
      words.push(toks[j].folded);
      end = j;
    }
    if (words.length === 0) continue; // không có đối số ⇒ không áp quy tắc, giữ nguyên cụm
    return { endIndex: end, output: buildName(words, rule.style) };
  }
  return null;
}

/**
 * @param {string} text NFC
 * @returns {{ text: string, applied: {type:string, from:string, to:string}[] }}
 */
export function applyDevspeech(text) {
  const toks = tokenize(text);
  const applied = [];
  let out = '';
  let cursor = 0;
  let i = 0;
  while (i < toks.length) {
    const m = matchSymbolRule(toks, i) ?? matchCompoundRule(toks, i, text);
    if (!m) {
      out += text.slice(cursor, toks[i].end);
      cursor = toks[i].end;
      i++;
      continue;
    }
    const from = text.slice(toks[i].start, toks[m.endIndex].end);
    out += text.slice(cursor, toks[i].start);
    if (isGlueSymbol(m.output)) out = out.replace(/[ \t]+$/u, '');
    out += m.output;
    cursor = toks[m.endIndex].end;
    if (isGlueSymbol(m.output)) {
      const after = /^[ \t]+/u.exec(text.slice(cursor));
      if (after) cursor += after[0].length;
    }
    applied.push({ type: 'devspeech', from, to: m.output });
    i = m.endIndex + 1;
  }
  out += text.slice(cursor);
  return { text: out, applied };
}
