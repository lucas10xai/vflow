// Gợi ý mục từ điển từ một lần người dùng sửa chữ (before -> after). Chỉ gợi ý, không ghi gì.
import { tokenize, fold } from './text.js';

const MAX_TOKENS = 300;
const MAX_BEFORE_WORDS = 4;
const MAX_AFTER_WORDS = 3;
const MAX_HUNKS = 3;

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
