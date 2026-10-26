// Chế độ email: viết lại qua endpoint OpenAI-compatible (POST {url}/chat/completions), dùng chung
// client llm.js. Chỉ gửi VĂN BẢN. `settings` (tuỳ chọn) áp cloud_llm/llm_model/llm_timeout_ms.
import { callLlm } from './llm.js';

export const EMAIL_SYSTEM_PROMPT = [
  'Bạn là trợ lý biên tập thư công việc.',
  'Viết lại đoạn văn bản người dùng đọc chính tả thành một email chuyên nghiệp, lịch sự, mạch lạc bằng cùng ngôn ngữ với văn bản gốc (thường là tiếng Việt).',
  'Quy tắc bắt buộc:',
  '- GIỮ NGUYÊN toàn bộ ý, số liệu, ngày giờ, tên riêng, tên sản phẩm, thuật ngữ kỹ thuật tiếng Anh, lệnh, đường dẫn và URL.',
  '- KHÔNG thêm thông tin, cam kết, lời hứa, chữ ký hay chi tiết nào không có trong văn bản gốc.',
  '- Bỏ từ đệm, lặp từ và chỗ ngập ngừng; sửa chính tả và dấu câu.',
  '- Chỉ trả về nội dung email đã viết lại, không giải thích, không bọc trong dấu ngoặc kép hay khối mã.',
].join('\n');

/** Mã lỗi viết lại (xem thêm llm.js: LLM_ERROR_CODES). */
export const REWRITE_ERRORS = ['timeout', 'network', 'empty', 'bad_response', 'no_key', 'no_model', 'cloud_disabled'];

/**
 * @param {{ text: string,
 *           rewrite: import('./llm.js').RewriteConfig,
 *           settings?: import('./llm.js').LlmSettings,
 *           fetchImpl?: typeof fetch }} args
 * @returns {Promise<{ text: string, error: null } | { text: null, error: string }>}
 */
export async function rewriteEmail({ text, rewrite, settings, fetchImpl = fetch }) {
  return callLlm({
    messages: [
      { role: 'system', content: EMAIL_SYSTEM_PROMPT },
      { role: 'user', content: text },
    ],
    rewrite,
    settings,
    fetchImpl,
    // Phản hồi dài bất thường so với đầu vào: coi là phản hồi lạ, không dùng.
    maxOutputChars: Math.max(4000, text.length * 8),
  });
}
