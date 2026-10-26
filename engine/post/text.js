// Tiện ích văn bản dùng chung cho engine/post: chuẩn hoá, gấp dấu thanh, tách từ.

/** Dấu thanh tiếng Việt ở dạng NFD: huyền, sắc, ngã, hỏi, nặng. Giữ dấu mũ/trăng/móc và đ. */
const TONE_MARKS = /[̣̀́̃̉]/g;

/** Một "từ" là chuỗi liên tiếp chữ cái, dấu kết hợp hoặc chữ số. */
const WORD_RE = /[\p{L}\p{M}\p{N}]+/gu;

/**
 * Gấp để so khớp: chữ thường, bỏ dấu thanh (giữ â/ă/ê/ô/ơ/ư/đ).
 * @param {string} s
 * @returns {string}
 */
export function fold(s) {
  return s.normalize('NFD').replace(TONE_MARKS, '').normalize('NFC').toLowerCase();
}

/**
 * @typedef {{ word: string, lower: string, folded: string, start: number, end: number }} Token
 */

/**
 * Tách từ kèm vị trí trong chuỗi (chuỗi nên ở dạng NFC).
 * @param {string} text
 * @returns {Token[]}
 */
export function tokenize(text) {
  /** @type {Token[]} */
  const out = [];
  for (const m of text.matchAll(WORD_RE)) {
    const word = m[0];
    out.push({ word, lower: word.toLowerCase(), folded: fold(word), start: m.index, end: m.index + word.length });
  }
  return out;
}

/**
 * Viết hoa chữ cái đầu.
 * @param {string} s
 */
export function capitalize(s) {
  const [first = '', ...rest] = s;
  return first.toUpperCase() + rest.join('');
}

/** @param {string} s */
export function startsUpper(s) {
  return /^\p{Lu}/u.test(s);
}

/** @param {string} s */
export function startsLower(s) {
  return /^\p{Ll}/u.test(s);
}
