// Chế độ tidy ("Gọn"): LLM làm gọn văn bản (dấu câu, viết hoa, bỏ từ đệm, backtrack, danh sách)
// qua endpoint OpenAI-compatible, với GUARD sau LLM (bất biến 6, contract/engine-api.md) để chặn
// mô hình thêm ý/số/thuật ngữ không có trong lời nói. Lỗi LLM hoặc guard từ chối ⇒ caller (index.js)
// dùng văn bản dự phòng (dictionary + devspeech + clean), KHÔNG thử lại và KHÔNG trả thành công giả.
import { callLlm } from './llm.js';
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

/** @param {string} text */
function buildMessages(text) {
  const messages = [{ role: 'system', content: TIDY_SYSTEM_PROMPT }];
  for (const ex of FEW_SHOT) {
    messages.push({ role: 'user', content: ex.user }, { role: 'assistant', content: ex.assistant });
  }
  messages.push({ role: 'user', content: text });
  return messages;
}

/** Bỏ dấu đánh số ("1.", "2)") và gạch đầu dòng ở đầu mỗi dòng, để không bị tính là nội dung "thêm". */
function stripListMarkers(text) {
  return text.replace(/^[ \t]*(?:[-•*]|\d+[.)])[ \t]*/gmu, '');
}

/** @param {string} w */
const isDigitToken = (w) => /^\d+$/.test(w);
/** @param {string} w */
const isLatinToken = (w) => /^[A-Za-z][A-Za-z0-9]*$/.test(w);

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
  const overlap = outputToks.filter((t) => inputFoldedSet.has(t.folded)).length / outputToks.length;
  if (overlap < guard.min_token_overlap) return false;

  const inputLower = input.toLowerCase();
  for (const t of outputToks) {
    if (isDigitToken(t.word) && !input.includes(t.word)) return false;
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
 *           fetchImpl?: typeof fetch }} args
 * @returns {Promise<{ text: string, error: null } | { text: null, error: string }>}
 */
export async function tidyRaw({ text, rewrite, settings, fetchImpl = fetch }) {
  return callLlm({ messages: buildMessages(text), rewrite, settings, fetchImpl });
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
