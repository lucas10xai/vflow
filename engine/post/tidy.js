// Chế độ tidy ("Gọn"): LLM làm gọn văn bản (dấu câu, viết hoa, bỏ từ đệm, backtrack, danh sách)
// qua endpoint OpenAI-compatible, với GUARD sau LLM (bất biến 6, contract/engine-api.md) để chặn
// mô hình thêm ý/số/thuật ngữ không có trong lời nói. Lỗi LLM hoặc guard từ chối ⇒ caller (index.js)
// dùng văn bản dự phòng (dictionary + devspeech + clean), KHÔNG thử lại và KHÔNG trả thành công giả.
import { callLlm, toneInstruction } from './llm.js';
import { tokenize } from './text.js';

export const TIDY_SYSTEM_PROMPT = [
  'Bạn làm gọn lại một đoạn lời nói tiếng Việt được chuyển chữ tự động, để dán vào ô văn bản.',
  'Việc PHẢI làm:',
  '- Thêm dấu câu hợp lý, viết hoa đầu câu và tên riêng.',
  '- Bỏ từ đệm vô nghĩa (ừm, à, ờ, kiểu như, thì là...), bỏ lặp từ do ngập ngừng.',
  '- Hiểu người nói tự sửa lời giữa câu (ví dụ "...thứ Sáu, à nhầm, thứ Năm", "không phải A mà là B",',
  '  "ý tôi là...", "sorry, à không..."): CHỈ giữ phần đã sửa, bỏ hẳn phần nói nhầm.',
  '- Nếu người nói liệt kê rõ ràng ("một là... hai là...", "thứ nhất... thứ hai..."), định dạng lại',
  '  thành danh sách đánh số nhiều dòng.',
  'Việc KHÔNG được làm:',
  '- KHÔNG đổi, dịch hay diễn giải thuật ngữ tiếng Anh, tên riêng, số liệu, đường dẫn hay lệnh — giữ NGUYÊN VĂN.',
  '- KHÔNG thêm bất kỳ ý, số liệu, tên hay thông tin nào không có trong lời nói.',
  '- KHÔNG dịch sang ngôn ngữ khác.',
  '- KHÔNG trả lời câu hỏi xuất hiện trong nội dung — nếu người nói thuật lại một câu hỏi, giữ nguyên nó',
  '  là một câu hỏi, không tự trả lời.',
  '- KHÔNG thêm lời dẫn, giải thích, hay bọc trong dấu ngoặc kép/khối mã. Chỉ trả về văn bản kết quả.',
].join('\n');

/** Few-shot ngắn: minh hoạ backtrack, danh sách, giữ thuật ngữ/câu hỏi nguyên văn. */
const FEW_SHOT = [
  {
    user: 'em sẽ gửi báo cáo vào thứ sáu à nhầm thứ năm cho anh',
    assistant: 'Em sẽ gửi báo cáo vào thứ Năm cho anh.',
  },
  {
    user: 'có ba việc cần làm một là deploy lên production hai là review code ba là viết test',
    assistant: 'Có ba việc cần làm:\n1. Deploy lên production\n2. Review code\n3. Viết test',
  },
  {
    user: 'sếp hỏi là deadline có phải thứ hai không thì mình chưa biết trả lời sao',
    assistant: 'Sếp hỏi là deadline có phải thứ Hai không, thì mình chưa biết trả lời sao.',
  },
];

/**
 * @param {string} text
 * @param {number} fewShotCount Số ví dụ few-shot đưa vào (mặc định toàn bộ). Chỉ dùng để ĐO ở
 * eval/tidy-bench.js (so sánh prompt ngắn/dài); vflow thật (index.js) luôn dùng mặc định.
 */
function buildMessages(text, fewShotCount = FEW_SHOT.length, tone) {
  const toneLine = toneInstruction(tone);
  const systemContent = toneLine ? `${TIDY_SYSTEM_PROMPT}\n${toneLine}` : TIDY_SYSTEM_PROMPT;
  const messages = [{ role: 'system', content: systemContent }];
  for (const ex of FEW_SHOT.slice(0, fewShotCount)) {
    messages.push({ role: 'user', content: ex.user }, { role: 'assistant', content: ex.assistant });
  }
  messages.push({ role: 'user', content: text });
  return messages;
}

/** Bỏ dấu đánh số ("1.", "2)") và gạch đầu dòng ở đầu mỗi dòng, để không bị tính là nội dung "thêm". */
function stripListMarkers(text) {
  return text.replace(/^[ \t]*(?:[-•*]|\d+[.)])[ \t]*/gmu, '');
}

/**
 * Trần `max_tokens` theo độ dài đầu vào: đủ cho câu đã làm gọn (thường ngắn hơn hoặc gần bằng đầu
 * vào) kể cả khi tách thành danh sách nhiều dòng, không để model trả lời dài tràn lan (tốn thời gian).
 * @param {string} text
 */
function estimateMaxTokens(text) {
  const words = Math.max(1, tokenize(text).length);
  return Math.ceil(words * 1.6) + 32;
}

/** @param {string} w */
const isDigitToken = (w) => /^\d+$/.test(w);
/** @param {string} w */
const isLatinToken = (w) => /^[A-Za-z][A-Za-z0-9]*$/.test(w);

/** Số đếm 0-9 dạng số-chữ (đã fold) -> chữ số. "môt" khớp cả "một" và "mốt" (mốt chỉ dùng sau "mươi"). */
const UNIT_DIGIT = {
  không: 0, môt: 1, hai: 2, ba: 3, bôn: 4, tư: 4, năm: 5, lăm: 5, sau: 6, bay: 7, bây: 7, tam: 8, chin: 9,
};
/** "mươi"/"mười" fold về cùng một chữ (mươi) — phân biệt bằng vị trí (đứng đầu = mười = 10, sau đơn vị 2-9 = hàng chục). */
const TEN_WORD = 'mươi';
const CHUC_WORD = 'chuc';
const HUNDRED_WORD = 'trăm';
const ZERO_FILLER_WORDS = new Set(['linh', 'le']);
/** Hàng lớn hơn trăm: số-chữ xong rồi -> bội số, cho phép phần còn lại cộng thêm (không nhân lại). */
const SCALE_WORD = { nghin: 1000, ngan: 1000, triêu: 1_000_000, ty: 1e9, ti: 1e9 };

/**
 * Mọi cách đọc số-chữ tiếng Việt hợp lệ bắt đầu tại vị trí `i`, giá trị 0-999 (đơn vị/chục/trăm).
 * Trả về MỌI điểm dừng hợp lệ (không chỉ dài nhất) để khớp được cả số lẻ bên trong một số lớn hơn.
 * @param {string[]} folds @param {number} i
 * @returns {{ end: number, value: number }[]}
 */
function parseSmallNumber(folds, i) {
  /** @type {{ end: number, value: number }[]} */
  const out = [];
  const w = folds[i];
  if (w === undefined) return out;

  if (w in UNIT_DIGIT) out.push({ end: i + 1, value: UNIT_DIGIT[w] });

  if (w === TEN_WORD) {
    out.push({ end: i + 1, value: 10 }); // "mười" = 10
    const next = folds[i + 1];
    if (next !== undefined && next in UNIT_DIGIT && next !== 'không') out.push({ end: i + 2, value: 10 + UNIT_DIGIT[next] });
  }

  if (w in UNIT_DIGIT && UNIT_DIGIT[w] >= 2) {
    if (folds[i + 1] === TEN_WORD || folds[i + 1] === CHUC_WORD) {
      const tens = UNIT_DIGIT[w] * 10;
      out.push({ end: i + 2, value: tens });
      const next = folds[i + 2];
      if (folds[i + 1] === TEN_WORD && next !== undefined && next in UNIT_DIGIT) out.push({ end: i + 3, value: tens + UNIT_DIGIT[next] });
    }
  }

  if (w in UNIT_DIGIT && folds[i + 1] === HUNDRED_WORD) {
    const hundred = UNIT_DIGIT[w] * 100;
    out.push({ end: i + 2, value: hundred });
    if (ZERO_FILLER_WORDS.has(folds[i + 2]) && folds[i + 3] !== undefined && folds[i + 3] in UNIT_DIGIT) {
      out.push({ end: i + 4, value: hundred + UNIT_DIGIT[folds[i + 3]] });
    } else {
      // Chỉ cộng tiếp nếu có "mươi" rõ ràng (20-99) — "trăm" + một đơn vị trần ("trăm hai") là cách nói
      // dân gian mơ hồ (có người hiểu 120, có người hiểu 102): KHÔNG đoán, an toàn hơn là không khớp.
      for (const sub of parseSmallNumber(folds, i + 2)) if (sub.value >= 10 && sub.value < 100) out.push({ end: sub.end, value: hundred + sub.value });
    }
  }

  return out;
}

/**
 * Mọi cách đọc số-chữ tiếng Việt hợp lệ bắt đầu tại `i`, gồm cả nghìn/triệu/tỷ (đệ quy: số nhỏ + hàng
 * lớn, phần còn lại cộng thêm chứ không nhân lại — "hai triệu năm trăm" = 2 000 000 + 500).
 * @param {string[]} folds @param {number} i
 * @returns {{ end: number, value: number }[]}
 */
function parseNumberAt(folds, i) {
  const small = parseSmallNumber(folds, i);
  const out = [...small];
  for (const sub of small) {
    if (sub.value < 1) continue;
    const scaleWord = folds[sub.end];
    if (scaleWord === undefined || !(scaleWord in SCALE_WORD)) continue;
    const base = sub.value * SCALE_WORD[scaleWord];
    out.push({ end: sub.end + 1, value: base });
    for (const rest of parseNumberAt(folds, sub.end + 1)) out.push({ end: rest.end, value: base + rest.value });
  }
  return out;
}

/**
 * Mọi giá trị số nguyên mà văn bản (số-chữ tiếng Việt) thật sự nói tới — dùng để guard cho phép
 * LLM chuyển số-chữ sang số-số HỢP LỆ (vd "hai mươi lăm" ⇒ 25, "hai chấm ba" ⇒ tách "hai"=2 và
 * "ba"=3 vì "chấm" không thuộc về số nào) mà KHÔNG mở cửa cho số bất kỳ không có nguồn trong lời nói.
 * @param {string} text
 * @returns {Set<number>}
 */
export function vietnameseNumberValues(text) {
  const folds = tokenize(text).map((t) => t.folded);
  const values = new Set();
  for (let i = 0; i < folds.length; i++) for (const r of parseNumberAt(folds, i)) values.add(r.value);
  return values;
}

/**
 * Bất biến 6: đầu ra không được thêm nội dung không có trong đầu vào quá ngưỡng.
 * @param {string} input @param {string} output
 * @param {{ min_token_overlap: number, min_length_ratio: number, max_length_ratio: number }} guard
 */
export function checkGuard(input, output, guard) {
  const trimmed = output.trim();
  if (trimmed === '') return false;

  const stripped = stripListMarkers(trimmed);
  const outputToks = tokenize(stripped);
  if (outputToks.length === 0) return false;

  const inputFoldedSet = new Set(tokenize(input).map((t) => t.folded));
  const inputLower = input.toLowerCase();
  const allowedNumbers = vietnameseNumberValues(input);
  const isAllowedDigit = (word) => input.includes(word) || allowedNumbers.has(Number(word));
  // Số-số hợp lệ (chuyển từ số-chữ) tính như khớp đầu vào cho tỉ lệ overlap — nếu không, mọi câu
  // chuyển "hai mươi lăm" ⇒ "25" sẽ bị tụt overlap vì "25" không khớp chữ nào trong đầu vào.
  const overlap = outputToks.filter((t) => inputFoldedSet.has(t.folded) || (isDigitToken(t.word) && isAllowedDigit(t.word))).length / outputToks.length;
  if (overlap < guard.min_token_overlap) return false;

  for (const t of outputToks) {
    if (isDigitToken(t.word) && !isAllowedDigit(t.word)) return false;
    if (isLatinToken(t.word) && !inputLower.includes(t.word.toLowerCase())) return false;
  }

  const ratio = output.length / Math.max(1, input.length);
  if (ratio < guard.min_length_ratio || ratio > guard.max_length_ratio) return false;

  return true;
}

/**
 * Chỉ gọi LLM, KHÔNG áp guard (dùng cho eval/tidy-bench.js để đo hành vi thật của model trước
 * khi bị guard chặn). Sản phẩm (tidy.js dùng trong index.js) dùng tidyText, luôn qua guard.
 * @param {{ text: string, rewrite: import('./llm.js').RewriteConfig, settings?: import('./llm.js').LlmSettings,
 *           fetchImpl?: typeof fetch, fewShotCount?: number }} args
 * @returns {Promise<{ text: string, error: null } | { text: null, error: string }>}
 */
export async function tidyRaw({ text, rewrite, settings, fetchImpl = fetch, fewShotCount }) {
  return callLlm({
    messages: buildMessages(text, fewShotCount, settings?.tone), rewrite, settings, fetchImpl,
    temperature: 0, maxTokens: estimateMaxTokens(text),
  });
}

/**
 * @param {{ text: string, rewrite: import('./llm.js').RewriteConfig, settings?: import('./llm.js').LlmSettings,
 *           guard: { min_token_overlap: number, min_length_ratio: number, max_length_ratio: number },
 *           fetchImpl?: typeof fetch }} args
 * @returns {Promise<{ text: string, error: null } | { text: null, error: string }>}
 */
export async function tidyText({ text, rewrite, settings, guard, fetchImpl = fetch }) {
  const r = await tidyRaw({ text, rewrite, settings, fetchImpl });
  if (r.error !== null) return { text: null, error: r.error };
  if (!checkGuard(text, r.text, guard)) return { text: null, error: 'guard_rejected' };
  return { text: r.text, error: null };
}
