// Snippets (đoạn văn mẫu gọi bằng lời): kiểm schema, lưu bền (0600), mở rộng theo
// contract/engine-api.md (mục Snippets) — khớp cả câu HOẶC "chèn <trigger>" ở bất kỳ vị trí.
import { readFileSync, writeFileSync, renameSync, mkdirSync, chmodSync, rmSync } from 'node:fs';
import { dirname } from 'node:path';
import { randomBytes } from 'node:crypto';
import { fold, tokenize } from './text.js';

export const MAX_ENTRIES = 500;
const MAX_TRIGGER = 60;
const MAX_TEXT = 5000;
const ENTRY_KEYS = new Set(['trigger', 'text', 'uses', 'last_used']);
/** Khoảng cách được phép giữa các từ của trigger/"chèn": chỉ khoảng trắng/gạch nối. */
const JOINER_RE = /^[\s\-‐‑–]+$/u;
/** Từ dẫn "chèn" (và biến thể dấu/hoa thường) — fold("chèn") = "chen". */
const INSERT_WORD = 'chen';

/**
 * @typedef {{ trigger: string, text: string, uses: number, last_used: string|null }} Entry
 * @typedef {{ type: 'snippet', from: string, to: 'snippet' }} Applied
 */

export class SnippetError extends Error {
  /** @param {string} message */
  constructor(message) {
    super(message);
    this.code = 'bad_request';
  }
}

/** @param {unknown} s @param {number} max */
function isNonEmptyString(s, max) {
  return typeof s === 'string' && s.trim() !== '' && s.length <= max;
}

/**
 * Chuẩn hoá để so khớp cả câu / trùng trigger: bỏ dấu thanh, hoa→thường (fold), bỏ dấu câu,
 * gộp khoảng trắng thừa.
 * @param {string} s
 */
export function normalizeMatch(s) {
  return fold(s).replace(/[\p{P}]/gu, ' ').replace(/\s+/g, ' ').trim();
}

/**
 * Kiểm schema và chuẩn hoá danh sách snippet. Ném SnippetError (tiếng Việt) nếu sai.
 * @param {unknown} entries
 * @returns {Entry[]}
 */
export function validateEntries(entries) {
  if (!Array.isArray(entries)) throw new SnippetError('entries phải là một mảng');
  if (entries.length > MAX_ENTRIES) {
    throw new SnippetError(`quá nhiều mục: ${entries.length} > ${MAX_ENTRIES}`);
  }
  const seenNorm = new Set();
  return entries.map((e, i) => {
    const at = `entries[${i}]`;
    if (e === null || typeof e !== 'object' || Array.isArray(e)) throw new SnippetError(`${at} phải là object`);
    for (const k of Object.keys(e)) {
      if (!ENTRY_KEYS.has(k)) throw new SnippetError(`${at} có khoá lạ "${k}"`);
    }
    if (!isNonEmptyString(e.trigger, MAX_TRIGGER)) {
      throw new SnippetError(`${at}.trigger phải là chuỗi khác rỗng, tối đa ${MAX_TRIGGER} ký tự`);
    }
    const trigger = e.trigger.normalize('NFC').trim();
    const norm = normalizeMatch(trigger);
    if (norm === '') throw new SnippetError(`${at}.trigger phải có chữ`);
    if (seenNorm.has(norm)) {
      throw new SnippetError(`${at}.trigger "${trigger}" trùng với một mục khác (sau khi bỏ dấu/hoa thường/dấu câu)`);
    }
    seenNorm.add(norm);
    if (typeof e.text !== 'string' || e.text === '' || e.text.length > MAX_TEXT) {
      throw new SnippetError(`${at}.text phải là chuỗi khác rỗng, tối đa ${MAX_TEXT} ký tự`);
    }
    const text = e.text.normalize('NFC');
    const uses = e.uses ?? 0;
    if (!Number.isInteger(uses) || uses < 0) throw new SnippetError(`${at}.uses phải là số nguyên ≥ 0`);
    const lastUsed = e.last_used ?? null;
    if (lastUsed !== null && (typeof lastUsed !== 'string' || Number.isNaN(Date.parse(lastUsed)))) {
      throw new SnippetError(`${at}.last_used phải là thời điểm ISO hoặc null`);
    }
    return { trigger, text, uses, last_used: lastUsed };
  });
}

/**
 * Ghi JSON nguyên tử (tệp tạm + rename), quyền 0600 (bỏ qua chmod trên Windows).
 * @param {string} path @param {unknown} data
 * @returns {'0600'|'not_applied_windows'}
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
  if (process.platform === 'win32') return 'not_applied_windows';
  chmodSync(path, 0o600);
  return '0600';
}

/**
 * Lập chỉ mục trigger -> từ (đã gấp dấu/hoa thường), dài nhất trước (cụm dài nhất thắng).
 * @param {Entry[]} entries
 */
function compile(entries) {
  return entries
    .map((e, index) => ({ tokens: tokenize(e.trigger).map((t) => t.folded), index }))
    .filter((p) => p.tokens.length > 0)
    .sort((a, b) => b.tokens.length - a.tokens.length);
}

/**
 * @param {{ path: string, now?: () => Date, log?: (e: object) => void }} opts
 */
export function createSnippetStore({ path, now = () => new Date(), log = () => {} }) {
  if (typeof path !== 'string' || path === '') throw new TypeError('cần path');

  /** @type {Entry[]} */
  let entries;
  try {
    entries = validateEntries(JSON.parse(readFileSync(path, 'utf8')).entries);
  } catch (err) {
    if (/** @type {any} */ (err).code !== 'ENOENT') {
      // Không nhắc nội dung tệp (có thể là snippet) trong thông báo lỗi.
      const reason = err instanceof SnippetError ? err.message : 'JSON không hợp lệ';
      throw new SnippetError(`tệp snippets hỏng (${reason})`);
    }
    entries = [];
  }

  let index = compile(entries);

  function save() {
    return writePrivateJson(path, { entries });
  }

  /** @param {number} i */
  function touch(i) {
    entries[i].uses += 1;
    entries[i].last_used = now().toISOString();
    try {
      save();
    } catch (err) {
      // Mở rộng vẫn dùng được; chỉ thống kê không lưu được. Log mã lỗi, không log nội dung.
      log({ event: 'snippet_save_failed', code: /** @type {any} */ (err).code ?? 'unknown' });
    }
  }

  return {
    list() {
      return { entries: entries.map((e) => ({ ...e })) };
    },

    /**
     * Thay toàn bộ snippets. Kiểm schema trước, sai thì không đổi gì.
     * @param {unknown} next
     */
    replaceAll(next) {
      const valid = validateEntries(next);
      const prev = entries;
      entries = valid;
      try {
        const permissions = save();
        index = compile(entries);
        return { count: entries.length, permissions };
      } catch (err) {
        entries = prev;
        index = compile(entries);
        throw err;
      }
    },

    /**
     * Mở rộng snippet trong một câu nói: khớp cả câu (chuẩn hoá) bằng một trigger, HOẶC
     * "chèn <trigger>" ở bất kỳ vị trí (cụm dài nhất thắng); không mở rộng ở dạng khác.
     * @param {string} text
     * @returns {{ text: string, applied: Applied[], matched: boolean }}
     */
    expand(text) {
      if (typeof text !== 'string') throw new TypeError('text phải là chuỗi');
      const src = text.normalize('NFC');

      if (entries.length === 0) return { text: src, applied: [], matched: false };

      const whole = normalizeMatch(src);
      if (whole !== '') {
        const i = entries.findIndex((e) => normalizeMatch(e.trigger) === whole);
        if (i !== -1) {
          touch(i);
          return { text: entries[i].text, applied: [{ type: 'snippet', from: entries[i].trigger, to: 'snippet' }], matched: true };
        }
      }

      const toks = tokenize(src);
      /** @type {{ start: number, end: number, index: number }[]} */
      const hits = [];
      for (let i = 0; i < toks.length; i++) {
        if (toks[i].folded !== INSERT_WORD) continue;
        const start = i + 1;
        if (start >= toks.length) continue;
        if (!JOINER_RE.test(src.slice(toks[i].end, toks[start].start))) continue;
        const hit = matchTrigger(toks, start, src, index);
        if (hit) hits.push({ start: toks[i].start, end: toks[start + hit.length - 1].end, index: hit.index });
      }
      if (hits.length === 0) return { text: src, applied: [], matched: false };

      hits.sort((a, b) => a.start - b.start);
      /** @type {Applied[]} */
      const applied = [];
      const used = [];
      let out = '';
      let cursor = 0;
      for (const h of hits) {
        if (h.start < cursor) continue; // chồng lấn: giữ khớp trước
        out += src.slice(cursor, h.start) + entries[h.index].text;
        cursor = h.end;
        applied.push({ type: 'snippet', from: entries[h.index].trigger, to: 'snippet' });
        used.push(h.index);
      }
      out += src.slice(cursor);
      for (const i of used) touch(i);
      return { text: out, applied, matched: applied.length > 0 };
    },
  };
}

/**
 * Tìm trigger khớp dài nhất bắt đầu tại vị trí token `start`.
 * @param {import('./text.js').Token[]} toks
 * @param {number} start
 * @param {string} text
 * @param {{tokens: string[], index: number}[]} patterns đã sắp theo độ dài giảm dần
 */
function matchTrigger(toks, start, text, patterns) {
  outer: for (const p of patterns) {
    if (start + p.tokens.length > toks.length) continue;
    for (let k = 0; k < p.tokens.length; k++) {
      if (toks[start + k].folded !== p.tokens[k]) continue outer;
      if (k > 0 && !JOINER_RE.test(text.slice(toks[start + k - 1].end, toks[start + k].start))) continue outer;
    }
    return { index: p.index, length: p.tokens.length };
  }
  return null;
}
