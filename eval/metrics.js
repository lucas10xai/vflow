/**
 * WER/CER cho tiếng Việt sau chuẩn hoá (NFC, chữ thường, bỏ dấu câu, gộp khoảng trắng).
 * Hai biến thể: nhạy dấu thanh (giữ nguyên) và không nhạy dấu thanh (bỏ 5 dấu thanh
 * huyền/sắc/hỏi/ngã/nặng nhưng giữ dấu mũ/trăng/móc và chữ đ).
 * Tham chiếu rỗng mà kết quả không rỗng ⇒ tỉ lệ `null` ("không xác định"), không phải 0.
 */

// U+0300 huyền, U+0301 sắc, U+0303 ngã, U+0309 hỏi, U+0323 nặng (thêm U+0340/0341 là bản cũ của huyền/sắc).
const TONE_MARKS = /[̣̀́̃̉̀́]/g;

/**
 * @param {string} text
 * @param {{ tones?: boolean }} [opts] tones=false ⇒ bỏ dấu thanh
 * @returns {string}
 */
export function normalizeText(text, { tones = true } = {}) {
  let s = String(text ?? '').normalize('NFC').toLocaleLowerCase('vi');
  // Dấu câu, ký hiệu và ký tự điều khiển/định dạng (kể cả ZWSP, BOM) ⇒ khoảng trắng.
  s = s.replace(/[\p{P}\p{S}\p{C}]/gu, ' ');
  if (!tones) s = s.normalize('NFD').replace(TONE_MARKS, '').normalize('NFC');
  return s.replace(/[\s ]+/gu, ' ').trim();
}

/**
 * Khoảng cách Levenshtein giữa hai dãy (bộ nhớ O(min)).
 * @template T
 * @param {T[]} a
 * @param {T[]} b
 */
export function editDistance(a, b) {
  if (a.length < b.length) [a, b] = [b, a];
  let prev = new Array(b.length + 1);
  let cur = new Array(b.length + 1);
  for (let j = 0; j <= b.length; j++) prev[j] = j;
  for (let i = 1; i <= a.length; i++) {
    cur[0] = i;
    for (let j = 1; j <= b.length; j++) {
      const sub = prev[j - 1] + (a[i - 1] === b[j - 1] ? 0 : 1);
      cur[j] = Math.min(sub, prev[j] + 1, cur[j - 1] + 1);
    }
    [prev, cur] = [cur, prev];
  }
  return prev[b.length];
}

/** @param {number} errors @param {number} n */
const rate = (errors, n) => (n === 0 ? (errors === 0 ? 0 : null) : errors / n);

/**
 * @typedef {{ errors: number, ref_len: number, rate: number|null }} ErrorCount
 * @typedef {{ wer: ErrorCount, cer: ErrorCount }} Scores
 */

/**
 * Điểm một cặp câu. CER tính trên ký tự (bỏ khoảng trắng), dùng code point.
 * @param {string} ref
 * @param {string} hyp
 * @param {{ tones?: boolean }} [opts]
 * @returns {Scores}
 */
export function score(ref, hyp, opts = {}) {
  const r = normalizeText(ref, opts);
  const h = normalizeText(hyp, opts);
  const rw = r ? r.split(' ') : [];
  const hw = h ? h.split(' ') : [];
  const rc = [...r.replace(/ /g, '')];
  const hc = [...h.replace(/ /g, '')];
  const we = editDistance(rw, hw);
  const ce = editDistance(rc, hc);
  return {
    wer: { errors: we, ref_len: rw.length, rate: rate(we, rw.length) },
    cer: { errors: ce, ref_len: rc.length, rate: rate(ce, rc.length) },
  };
}

/**
 * Cả hai biến thể dấu thanh.
 * @param {string} ref @param {string} hyp
 */
export function scoreBoth(ref, hyp) {
  return { tone: score(ref, hyp, { tones: true }), no_tone: score(ref, hyp, { tones: false }) };
}

/**
 * Gộp điểm cả bộ: tổng lỗi / tổng độ dài tham chiếu.
 * @param {Scores[]} items
 * @returns {Scores}
 */
export function aggregate(items) {
  const sum = (k) => items.reduce(
    (acc, s) => ({ errors: acc.errors + s[k].errors, ref_len: acc.ref_len + s[k].ref_len }),
    { errors: 0, ref_len: 0 },
  );
  const w = sum('wer');
  const c = sum('cer');
  return { wer: { ...w, rate: rate(w.errors, w.ref_len) }, cer: { ...c, rate: rate(c.errors, c.ref_len) } };
}

/** @param {string} s */
const escapeRe = (s) => s.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');

/**
 * Thuật ngữ xuất hiện nguyên văn (không phân biệt hoa/thường, đúng ranh giới từ) trong văn bản.
 * @param {string} text
 * @param {string} term
 */
export function containsTerm(text, term) {
  const t = String(term).normalize('NFC').trim();
  if (!t) return false;
  const re = new RegExp(`(?<![\\p{L}\\p{N}])${escapeRe(t)}(?![\\p{L}\\p{N}])`, 'iu');
  return re.test(String(text ?? '').normalize('NFC'));
}

/**
 * Chỉ số "bắt đúng thuật ngữ tiếng Anh": trong các thuật ngữ có nguyên văn ở tham chiếu,
 * bao nhiêu cũng có trong kết quả. Không có thuật ngữ nào trong tham chiếu ⇒ rate `null`.
 * @param {Array<{ ref: string, hyp: string }>} pairs
 * @param {string[]} terms
 */
export function termRecall(pairs, terms) {
  let expected = 0;
  let hit = 0;
  /** @type {Record<string, {expected:number, hit:number}>} */
  const perTerm = {};
  for (const { ref, hyp } of pairs) {
    for (const term of terms) {
      if (!containsTerm(ref, term)) continue;
      expected++;
      perTerm[term] ??= { expected: 0, hit: 0 };
      perTerm[term].expected++;
      if (containsTerm(hyp, term)) { hit++; perTerm[term].hit++; }
    }
  }
  return { expected, hit, rate: expected === 0 ? null : hit / expected, per_term: perTerm };
}

/**
 * Trung vị và phân vị (nội suy tuyến tính). Mảng rỗng ⇒ null.
 * @param {number[]} values
 * @param {number} p 0..1
 */
export function percentile(values, p) {
  if (values.length === 0) return null;
  const s = [...values].sort((x, y) => x - y);
  const idx = (s.length - 1) * p;
  const lo = Math.floor(idx);
  const hi = Math.ceil(idx);
  return s[lo] + (s[hi] - s[lo]) * (idx - lo);
}
