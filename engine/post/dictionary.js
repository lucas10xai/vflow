// Từ điển cá nhân: kiểm schema, lưu bền (0600), khớp biến thể nói và thay bằng thuật ngữ.
import { readFileSync, writeFileSync, renameSync, mkdirSync, chmodSync, rmSync } from 'node:fs';
import { dirname } from 'node:path';
import { randomBytes } from 'node:crypto';
import { fold, tokenize, capitalize, startsUpper, startsLower } from './text.js';

export const MAX_ENTRIES = 5000;
const MAX_SPOKEN = 20;
const MAX_LEN = 100;
const ENTRY_KEYS = new Set(['term', 'spoken', 'kind', 'case', 'uses', 'last_used']);
/** Khoảng cách được phép giữa các từ của một biến thể nói: chỉ khoảng trắng/gạch nối. */
const JOINER_RE = /^[\s\-‐‑–]+$/u;

/**
 * @typedef {{ term: string, spoken: string[], kind: 'term'|'replace', case?: 'exact',
 *             uses: number, last_used: string|null }} Entry
 * @typedef {{ type: string, from: string, to: string }} Applied
 */

export class DictionaryError extends Error {
  /** @param {string} message */
  constructor(message) {
    super(message);
    this.code = 'bad_request';
  }
}

/** @param {unknown} s */
function isNonEmptyString(s) {
  return typeof s === 'string' && s.trim() !== '' && s.length <= MAX_LEN;
}

/**
 * Kiểm schema và chuẩn hoá danh sách mục. Ném DictionaryError (thông báo tiếng Việt) nếu sai.
 * @param {unknown} entries
 * @returns {Entry[]}
 */
export function validateEntries(entries) {
  if (!Array.isArray(entries)) throw new DictionaryError('entries phải là một mảng');
  if (entries.length > MAX_ENTRIES) {
    throw new DictionaryError(`quá nhiều mục: ${entries.length} > ${MAX_ENTRIES}`);
  }
  const seen = new Set();
  return entries.map((e, i) => {
    const at = `entries[${i}]`;
    if (e === null || typeof e !== 'object' || Array.isArray(e)) throw new DictionaryError(`${at} phải là object`);
    for (const k of Object.keys(e)) {
      if (!ENTRY_KEYS.has(k)) throw new DictionaryError(`${at} có khoá lạ "${k}"`);
    }
    if (!isNonEmptyString(e.term)) throw new DictionaryError(`${at}.term phải là chuỗi khác rỗng, tối đa ${MAX_LEN} ký tự`);
    const term = e.term.normalize('NFC').trim();
    if (seen.has(term)) throw new DictionaryError(`${at}.term "${term}" bị trùng`);
    seen.add(term);
    if (!Array.isArray(e.spoken) || e.spoken.length === 0 || e.spoken.length > MAX_SPOKEN) {
      throw new DictionaryError(`${at}.spoken phải là mảng 1–${MAX_SPOKEN} chuỗi`);
    }
    const spoken = e.spoken.map((s, j) => {
      if (!isNonEmptyString(s) || tokenize(s).length === 0) {
        throw new DictionaryError(`${at}.spoken[${j}] phải là chuỗi có chữ, tối đa ${MAX_LEN} ký tự`);
      }
      return s.normalize('NFC').trim();
    });
    const kind = e.kind ?? 'term';
    if (kind !== 'term' && kind !== 'replace') throw new DictionaryError(`${at}.kind phải là "term" hoặc "replace"`);
    if (e.case !== undefined && e.case !== 'exact') throw new DictionaryError(`${at}.case chỉ nhận "exact"`);
    const uses = e.uses ?? 0;
    if (!Number.isInteger(uses) || uses < 0) throw new DictionaryError(`${at}.uses phải là số nguyên ≥ 0`);
    const lastUsed = e.last_used ?? null;
    if (lastUsed !== null && (typeof lastUsed !== 'string' || Number.isNaN(Date.parse(lastUsed)))) {
      throw new DictionaryError(`${at}.last_used phải là thời điểm ISO hoặc null`);
    }
    /** @type {Entry} */
    const out = { term, spoken, kind, uses, last_used: lastUsed };
    if (e.case === 'exact') out.case = 'exact';
    return out;
  });
}

/**
 * Ghi JSON nguyên tử (tệp tạm + rename), quyền 0600. Trên Windows Node không áp được
 * quyền POSIX nên bỏ qua chmod; kết quả báo rõ điều đó.
 * @param {string} path
 * @param {unknown} data
 * @returns {'0600'|'not_applied_windows'}
 */
export function writePrivateJson(path, data) {
  mkdirSync(dirname(path), { recursive: true, mode: 0o700 });
  const tmp = `${path}.tmp-${process.pid}-${randomBytes(4).toString('hex')}`;
  try {
    writeFileSync(tmp, JSON.stringify(data, null, 2) + '\n', { mode: 0o600 });
    renameSync(tmp, path);
  } catch (err) {
    rmSync(tmp, { force: true });
    throw err;
  }
  if (process.platform === 'win32') return 'not_applied_windows';
  chmodSync(path, 0o600);
  return '0600';
}

/**
 * @param {{ path: string, seedPath: string, now: () => Date, log: (e: object) => void }} opts
 */
export function createDictionary({ path, seedPath, now, log }) {
  if (typeof path !== 'string' || path === '') throw new TypeError('cần dictionaryPath');

  /** @type {Entry[]} */
  let entries;
  let fromSeed = false;
  try {
    entries = validateEntries(JSON.parse(readFileSync(path, 'utf8')).entries);
  } catch (err) {
    if (/** @type {any} */ (err).code !== 'ENOENT') {
      // Không nhắc nội dung tệp trong lỗi; chỉ nói tệp hỏng.
      const reason = err instanceof DictionaryError ? err.message : 'JSON không hợp lệ';
      throw new DictionaryError(`tệp từ điển hỏng (${reason})`);
    }
    entries = validateEntries(JSON.parse(readFileSync(seedPath, 'utf8')).entries);
    fromSeed = true;
  }

  /** @type {Map<string, {tokens: string[], index: number}[]>} */
  let patterns = compile(entries);

  function save() {
    return writePrivateJson(path, { entries });
  }

  return {
    /** Từ điển đang dùng hạt giống (chưa có tệp riêng). */
    get fromSeed() {
      return fromSeed;
    },

    list() {
      return { entries: entries.map((e) => ({ ...e, spoken: [...e.spoken] })) };
    },

    /**
     * Thay toàn bộ từ điển. Kiểm schema trước, sai thì không đổi gì.
     * @param {unknown} next
     */
    replaceAll(next) {
      const valid = validateEntries(next);
      const prev = entries;
      entries = valid;
      try {
        const permissions = save();
        patterns = compile(entries);
        fromSeed = false;
        return { count: entries.length, permissions };
      } catch (err) {
        entries = prev;
        throw err;
      }
    },

    /**
     * Thay các biến thể nói trong văn bản bằng thuật ngữ; tăng uses/last_used và lưu bền.
     * @param {string} text NFC
     * @returns {{ text: string, applied: Applied[] }}
     */
    apply(text) {
      const { text: out, applied } = matchAndReplace(text, patterns, entries);
      if (applied.length > 0) {
        for (const a of applied) a.entry.uses += 1, (a.entry.last_used = now().toISOString());
        try {
          save();
          fromSeed = false;
        } catch (err) {
          // Văn bản vẫn dùng được; chỉ thống kê dùng không lưu được. Log mã lỗi, không log nội dung.
          log({ event: 'dictionary_save_failed', code: /** @type {any} */ (err).code ?? 'unknown' });
        }
      }
      return { text: out, applied: applied.map(({ entry, ...a }) => a) };
    },

    /**
     * Như `apply()` nhưng KHÔNG có hiệu ứng phụ (không tăng `uses`, không ghi tệp) — dùng cho
     * `/v1/partial` (item 9): xem trước nhiều lần/giây không được ghi đĩa liên tục.
     * @param {string} text NFC
     */
    applyPreview(text) {
      const { text: out, applied } = matchAndReplace(text, patterns, entries);
      return { text: out, applied: applied.map(({ entry, ...a }) => a) };
    },

    /** Các thuật ngữ cần giữ nguyên hoa/thường (không viết hoa đầu câu). */
    exactTerms() {
      return entries.filter((e) => e.case === 'exact').map((e) => e.term);
    },
  };
}

/**
 * Lập chỉ mục: từ đầu (đã gấp) -> các mẫu, mẫu dài trước, cùng độ dài giữ thứ tự mục.
 * @param {Entry[]} entries
 */
function compile(entries) {
  /** @type {Map<string, {tokens: string[], index: number}[]>} */
  const map = new Map();
  entries.forEach((e, index) => {
    for (const s of e.spoken) {
      const tokens = tokenize(s.normalize('NFC')).map((t) => t.folded);
      if (tokens.length === 0) continue;
      const list = map.get(tokens[0]) ?? [];
      list.push({ tokens, index });
      map.set(tokens[0], list);
    }
  });
  for (const list of map.values()) list.sort((a, b) => b.tokens.length - a.tokens.length);
  return map;
}

/**
 * @param {import('./text.js').Token[]} toks
 * @param {number} i
 * @param {string} text
 * Thay các biến thể nói khớp bằng thuật ngữ; THUẦN (không tăng uses/last_used, không ghi tệp) —
 * caller (apply/applyPreview) tự quyết định có áp hiệu ứng phụ không.
 * @param {string} text NFC @param {Map<string, {tokens: string[], index: number}[]>} patterns @param {Entry[]} entries
 */
function matchAndReplace(text, patterns, entries) {
  const toks = tokenize(text);
  /** @type {(Applied & { entry: Entry })[]} */
  const applied = [];
  let out = '';
  let cursor = 0;
  for (let i = 0; i < toks.length; ) {
    const hit = matchAt(toks, i, text, patterns);
    if (!hit) {
      i++;
      continue;
    }
    const entry = entries[hit.index];
    const start = toks[i].start;
    const end = toks[i + hit.length - 1].end;
    const from = text.slice(start, end);
    let to = entry.term;
    if (entry.case !== 'exact' && startsUpper(from) && startsLower(to)) to = capitalize(to);
    out += text.slice(cursor, start) + to;
    cursor = end;
    applied.push({ type: 'dictionary', from, to, entry });
    i += hit.length;
  }
  out += text.slice(cursor);
  return { text: out, applied };
}

/**
 * @param {Map<string, {tokens: string[], index: number}[]>} patterns
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
    if (!boundaryOk(text, toks[i].start, toks[i + c.tokens.length - 1].end)) continue;
    return { index: c.index, length: c.tokens.length };
  }
  return null;
}

/** Gạch nối ở biên ngoài cụm khớp: coi như dính vào định danh ghép, giống "kubernetes-cli". */
const BOUNDARY_HYPHENS = '-‐‑–';

/**
 * Không thay khi cụm dính vào định danh/đường dẫn/URL: x_pút, a.pút, /pút, pút_x, pút.js, pút@…,
 * kubernetes-cli (gạch nối ở biên — khác gạch nối NẰM GIỮA các từ của chính cụm khớp, cho phép
 * ở `JOINER_RE`/`matchAt`).
 * @param {string} text
 * @param {number} start
 * @param {number} end
 */
function boundaryOk(text, start, end) {
  const before = text[start - 1] ?? '';
  const after = text[end] ?? '';
  if (/[_@/\\.]/.test(before) || (before !== '' && BOUNDARY_HYPHENS.includes(before))) return false;
  if (/[_@/\\]/.test(after) || (after !== '' && BOUNDARY_HYPHENS.includes(after))) return false;
  if (after === '.' && /[\p{L}\p{N}]/u.test(text[end + 1] ?? '')) return false;
  return true;
}
