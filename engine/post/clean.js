// Chế độ clean: bỏ từ đệm theo dữ liệu (fillers.json) và chuẩn hoá khoảng trắng/dấu câu.
// Thuần quy tắc; không bao giờ tự thêm dấu câu mà STT không đưa ra.
import { readFileSync } from 'node:fs';
import { tokenize, capitalize } from './text.js';

/**
 * @typedef {{ remove_at: string[], keep_before: string[], keep_after: string[] }} ContextRule
 * @typedef {{ always: string[], always_patterns: string[], keep_after_any: string[],
 *             contextual: Record<string, ContextRule> }} FillerRules
 */

/** @returns {FillerRules} */
export function loadFillerRules(path = new URL('./fillers.json', import.meta.url)) {
  return JSON.parse(readFileSync(path, 'utf8'));
}

const SENTENCE_END_RE = /[.!?…]/;

/**
 * Bỏ từ đệm đứng riêng. Dấu phẩy đi kèm từ đệm cũng bỏ ("Ừm, ..." → "...").
 * @param {string} text NFC
 * @param {FillerRules} rules
 * @returns {{ text: string, applied: {type:string, from:string, to:string}[] }}
 */
export function removeFillers(text, rules) {
  const toks = tokenize(text);
  const always = new Set(rules.always);
  const patterns = rules.always_patterns.map((p) => new RegExp(p, 'u'));
  const keepAfterAny = new Set(rules.keep_after_any);
  /** @type {[number, number][]} */
  const ranges = [];
  const applied = [];

  /** Khoảng giữa hai token có ngắt câu không. */
  const breaksBetween = (a, b) => SENTENCE_END_RE.test(text.slice(toks[a].end, toks[b].start));

  for (let i = 0; i < toks.length; i++) {
    const t = toks[i];
    const prev = i > 0 && !breaksBetween(i - 1, i) ? toks[i - 1] : null;
    const next = i + 1 < toks.length && !breaksBetween(i, i + 1) ? toks[i + 1] : null;
    let remove = false;
    if (always.has(t.lower) || patterns.some((re) => re.test(t.lower))) {
      remove = true;
    } else if (Object.hasOwn(rules.contextual, t.lower)) {
      const rule = rules.contextual[t.lower];
      const position = !next ? 'final' : prev ? 'medial' : 'initial';
      remove =
        rule.remove_at.includes(position) &&
        !rule.keep_before.includes(next?.lower ?? '') &&
        !rule.keep_after.includes(prev?.lower ?? '') &&
        !keepAfterAny.has(prev?.lower ?? '');
    }
    if (!remove) continue;

    let start = t.start;
    let end = t.end;
    const after = /^\s*,/.exec(text.slice(end));
    if (after) {
      end += after[0].length;
      // ", à," giữa câu: bỏ luôn dấu phẩy phía trước để không còn "cần, deploy".
      const before = /,\s*$/.exec(text.slice(i > 0 ? toks[i - 1].end : 0, start));
      if (before && prev) start -= before[0].length;
    }
    ranges.push([start, end]);
    applied.push({ type: 'filler_removed', from: t.word, to: '' });
  }

  if (ranges.length === 0) return { text, applied };
  let out = '';
  let cursor = 0;
  for (const [s, e] of ranges) {
    if (s > cursor) out += text.slice(cursor, s) + ' ';
    cursor = Math.max(cursor, e);
  }
  out += text.slice(cursor);
  return { text: out, applied };
}

/**
 * Gộp khoảng trắng, bỏ khoảng trắng trước dấu câu, gộp dấu phẩy lặp, và (chỉ khi văn bản
 * đã có dấu kết câu) viết hoa đầu câu. Không thêm dấu câu mới.
 * @param {string} text
 * @param {{ exactTerms?: string[] }} [opts] thuật ngữ giữ nguyên hoa/thường (ví dụ npm)
 */
export function normalizeText(text, { exactTerms = [] } = {}) {
  let s = text.replace(/\s+/gu, ' ').trim();
  s = s.replace(/\s+([,.!?;:…)\]}])/gu, '$1');
  s = s.replace(/([(\[{])\s+/gu, '$1');
  s = s.replace(/,(\s*,)+/gu, ',');
  s = s.replace(/,\s*([.!?…])/gu, '$1');
  s = s.replace(/^[,;:]\s*/u, '');
  if (!/[\p{L}\p{N}]/u.test(s)) return '';
  if (SENTENCE_END_RE.test(s)) {
    /** @param {number} at */
    const keep = (at) => exactTerms.some((t) => s.startsWith(t, at) && !/[\p{L}\p{N}]/u.test(s[at + t.length] ?? ''));
    s = s.replace(/(^|[.!?…]\s+)(\p{Ll})/gu, (m, lead, ch, offset) => {
      const at = offset + lead.length;
      return keep(at) ? m : lead + capitalize(ch);
    });
  }
  return s;
}
