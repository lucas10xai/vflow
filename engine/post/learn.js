// Gợi ý mục từ điển từ một lần người dùng sửa chữ (before -> after).
// `suggestCorrections` chỉ gợi ý ngay (không ghi gì) — dùng cho POST /v1/corrections cũ.
// `createCorrectionsStore` (item 8, contract/engine-api.md mục "Gợi ý từ điển") LƯU các cặp
// before/after ngắn (≤ 5 từ, không lưu cả câu) vào $VFLOW_HOME/corrections.json (0600, tối đa 500
// mục gần nhất), dùng để tổng hợp GET /v1/dictionary/suggestions (chỉ cặp xuất hiện ≥ 2 lần, chưa
// có trong từ điển) — KHÔNG gửi gì lên mạng.
import { readFileSync, existsSync } from 'node:fs';
import { tokenize, fold } from './text.js';
import { writePrivateJson } from './dictionary.js';

const MAX_TOKENS = 300;
const MAX_BEFORE_WORDS = 4;
const MAX_AFTER_WORDS = 3;
const MAX_HUNKS = 3;
export const MAX_CORRECTIONS = 500;

/**
 * @param {{ before: unknown, after: unknown }} input
 * @param {{ term: string, spoken: string[] }[]} entries mục hiện có (để bỏ gợi ý đã có)
 * @returns {{ suggestions: { term: string, spoken: string[] }[] }}
 */
export function suggestCorrections({ before, after }, entries) {
  if (typeof before !== 'string' || typeof after !== 'string') return { suggestions: [] };
  const b = before.normalize('NFC');
  const a = after.normalize('NFC');
  if (b === a) return { suggestions: [] };
  const bt = tokenize(b);
  const at = tokenize(a);
  if (bt.length === 0 || at.length === 0 || bt.length > MAX_TOKENS || at.length > MAX_TOKENS) {
    return { suggestions: [] };
  }

  const hunks = diffHunks(bt.map((t) => t.lower), at.map((t) => t.lower));
  const replaced = hunks.filter((h) => h.b1 > h.b0 && h.a1 > h.a0);
  // Sửa nhiều chỗ hoặc sửa quá nửa câu: đó là viết lại, không phải sửa thuật ngữ.
  const changedWords = hunks.reduce((n, h) => n + Math.max(h.b1 - h.b0, h.a1 - h.a0), 0);
  if (replaced.length === 0 || hunks.length > MAX_HUNKS || changedWords > Math.max(MAX_BEFORE_WORDS, bt.length / 2)) {
    return { suggestions: [] };
  }

  /** @type {Map<string, Set<string>>} */
  const known = new Map(entries.map((e) => [e.term, new Set(e.spoken.map((s) => foldPhrase(s)))]));
  /** @type {Map<string, string[]>} */
  const out = new Map();
  for (const h of replaced) {
    if (h.b1 - h.b0 > MAX_BEFORE_WORDS || h.a1 - h.a0 > MAX_AFTER_WORDS) continue;
    const spoken = b.slice(bt[h.b0].start, bt[h.b1 - 1].end).toLowerCase();
    const term = a.slice(at[h.a0].start, at[h.a1 - 1].end);
    // Chỉ khác dấu thanh/hoa thường: từ điển đã khớp bỏ qua những thứ đó, không có gì để học.
    if (foldPhrase(spoken) === foldPhrase(term)) continue;
    // Chỉ là số: thường là sửa số liệu, không phải thuật ngữ.
    if (/^[\d\s.,]+$/.test(term)) continue;
    if (known.get(term)?.has(foldPhrase(spoken))) continue;
    const list = out.get(term) ?? [];
    if (!list.includes(spoken)) list.push(spoken);
    out.set(term, list);
  }
  return { suggestions: [...out].map(([term, spoken]) => ({ term, spoken })) };
}

/** @param {string} s */
function foldPhrase(s) {
  return tokenize(s).map((t) => fold(t.word)).join(' ');
}

/**
 * Diff mức từ bằng LCS; trả các đoạn khác nhau [b0,b1) ↔ [a0,a1).
 * @param {string[]} x
 * @param {string[]} y
 */
function diffHunks(x, y) {
  const n = x.length;
  const m = y.length;
  const L = Array.from({ length: n + 1 }, () => new Uint16Array(m + 1));
  for (let i = n - 1; i >= 0; i--) {
    for (let j = m - 1; j >= 0; j--) {
      L[i][j] = x[i] === y[j] ? L[i + 1][j + 1] + 1 : Math.max(L[i + 1][j], L[i][j + 1]);
    }
  }
  /** @type {{b0:number,b1:number,a0:number,a1:number}[]} */
  const hunks = [];
  let i = 0;
  let j = 0;
  /** @type {{b0:number,a0:number}|null} */
  let open = null;
  const close = () => {
    if (open) hunks.push({ b0: open.b0, b1: i, a0: open.a0, a1: j });
    open = null;
  };
  while (i < n || j < m) {
    if (i < n && j < m && x[i] === y[j]) {
      close();
      i++;
      j++;
    } else {
      open ??= { b0: i, a0: j };
      if (j < m && (i === n || L[i][j + 1] >= L[i + 1][j])) j++;
      else i++;
    }
  }
  close();
  return hunks;
}

export class CorrectionsError extends Error {
  /** @param {string} message */
  constructor(message) {
    super(message);
    this.code = 'internal';
  }
}

/** @param {string} path */
function loadCorrectionsRaw(path) {
  if (!existsSync(path)) return { version: 1, entries: [], dismissed: [] };
  let raw;
  try {
    raw = readFileSync(path, 'utf8');
  } catch (err) {
    throw new CorrectionsError(`không đọc được tệp sửa lỗi (${/** @type {any} */ (err).code ?? 'lỗi'})`);
  }
  let json;
  try {
    json = JSON.parse(raw);
  } catch {
    throw new CorrectionsError('tệp sửa lỗi hỏng (JSON không hợp lệ)');
  }
  if (!json || typeof json !== 'object' || Array.isArray(json) || !Array.isArray(json.entries)) {
    throw new CorrectionsError('tệp sửa lỗi hỏng (sai cấu trúc)');
  }
  return {
    version: 1,
    entries: json.entries.filter((e) => e && typeof e.term === 'string' && typeof e.spoken === 'string'),
    dismissed: Array.isArray(json.dismissed) ? json.dismissed.filter((t) => typeof t === 'string') : [],
  };
}

/**
 * Lưu bền các sự sửa (before->after) ngắn để tổng hợp gợi ý từ điển (`GET /v1/dictionary/suggestions`).
 * @param {{ path: string, now?: () => Date, log?: (e: object) => void }} opts
 */
export function createCorrectionsStore({ path, now = () => new Date(), log = () => {} }) {
  if (typeof path !== 'string' || path === '') throw new TypeError('cần path');
  let data = loadCorrectionsRaw(path);

  function persist() {
    try {
      writePrivateJson(path, data);
    } catch (err) {
      log({ event: 'corrections_save_failed', code: /** @type {any} */ (err)?.code ?? 'unknown' });
    }
  }

  return {
    /**
     * Rút các cặp (term, spoken) ngắn từ một lần sửa và lưu lại — dùng CHÍNH logic lọc nhiễu của
     * `suggestCorrections` (không lưu cả câu, không lưu sửa số liệu/dấu thanh/hoa thường...).
     * @param {unknown} before @param {unknown} after
     */
    record(before, after) {
      try {
        const { suggestions } = suggestCorrections({ before, after }, []);
        if (suggestions.length === 0) return;
        const at = now().toISOString();
        for (const s of suggestions) for (const spoken of s.spoken) data.entries.push({ term: s.term, spoken, at });
        if (data.entries.length > MAX_CORRECTIONS) data.entries = data.entries.slice(-MAX_CORRECTIONS);
        persist();
      } catch (err) {
        log({ event: 'corrections_record_failed', code: /** @type {any} */ (err)?.code ?? 'unknown' });
      }
    },

    /**
     * Gộp theo (term, spoken); chỉ trả cặp xuất hiện ≥ 2 lần, chưa có trong từ điển, chưa bị dismiss.
     * @param {{ term: string, spoken: string[] }[]} dictionaryEntries
     * @returns {{ suggestions: { term: string, variants: string[], count: number, last_seen: string }[] }}
     */
    suggestions(dictionaryEntries = []) {
      const known = new Map(dictionaryEntries.map((e) => [e.term, new Set(e.spoken.map(foldPhrase))]));
      /** @type {Map<string, Map<string, { count: number, last_seen: string }>>} */
      const byTerm = new Map();
      for (const e of data.entries) {
        if (known.get(e.term)?.has(foldPhrase(e.spoken))) continue;
        const bySpoken = byTerm.get(e.term) ?? new Map();
        const c = bySpoken.get(e.spoken) ?? { count: 0, last_seen: e.at };
        c.count += 1;
        if (e.at > c.last_seen) c.last_seen = e.at;
        bySpoken.set(e.spoken, c);
        byTerm.set(e.term, bySpoken);
      }
      const out = [];
      for (const [term, bySpoken] of byTerm) {
        const variants = [];
        let count = 0;
        let lastSeen = null;
        for (const [spoken, c] of bySpoken) {
          if (c.count < 2) continue;
          variants.push(spoken);
          count += c.count;
          if (!lastSeen || c.last_seen > lastSeen) lastSeen = c.last_seen;
        }
        if (variants.length > 0 && !data.dismissed.includes(term)) out.push({ term, variants, count, last_seen: lastSeen });
      }
      return { suggestions: out };
    },

    /** Ghi nhớ đã bỏ qua một gợi ý theo `term` — không hiện lại ở suggestions() nữa. */
    dismiss(term) {
      if (typeof term !== 'string' || term.trim() === '') throw new CorrectionsError('term phải là chuỗi khác rỗng');
      if (!data.dismissed.includes(term)) {
        data.dismissed.push(term);
        persist();
      }
      return { ok: true };
    },
  };
}
