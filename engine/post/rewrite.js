// Chế độ email: viết lại qua endpoint OpenAI-compatible (POST {url}/chat/completions).
// Chỉ gửi VĂN BẢN. Khoá đọc từ rewrite.key_file mỗi lần gọi; không bao giờ đưa khoá vào
// lỗi, log hay kết quả — mọi lỗi chỉ là một mã cố định.
import { readFileSync } from 'node:fs';
import { expandHome } from './config.js';

export const EMAIL_SYSTEM_PROMPT = [
  'Bạn là trợ lý biên tập thư công việc.',
  'Viết lại đoạn văn bản người dùng đọc chính tả thành một email chuyên nghiệp, lịch sự, mạch lạc bằng cùng ngôn ngữ với văn bản gốc (thường là tiếng Việt).',
  'Quy tắc bắt buộc:',
  '- GIỮ NGUYÊN toàn bộ ý, số liệu, ngày giờ, tên riêng, tên sản phẩm, thuật ngữ kỹ thuật tiếng Anh, lệnh, đường dẫn và URL.',
  '- KHÔNG thêm thông tin, cam kết, lời hứa, chữ ký hay chi tiết nào không có trong văn bản gốc.',
  '- Bỏ từ đệm, lặp từ và chỗ ngập ngừng; sửa chính tả và dấu câu.',
  '- Chỉ trả về nội dung email đã viết lại, không giải thích, không bọc trong dấu ngoặc kép hay khối mã.',
].join('\n');

/** Mã lỗi viết lại. */
export const REWRITE_ERRORS = ['timeout', 'network', 'empty', 'bad_response', 'no_key', 'no_model'];

/**
 * @param {{ text: string,
 *           rewrite: { url: string, model: string|null, timeout_ms: number, key_file: string|null },
 *           fetchImpl?: typeof fetch }} args
 * @returns {Promise<{ text: string, error: null } | { text: null, error: string }>}
 */
export async function rewriteEmail({ text, rewrite, fetchImpl = fetch }) {
  const key = readKey(rewrite.key_file);
  if (!key) return { text: null, error: 'no_key' };
  if (!rewrite.model) return { text: null, error: 'no_model' };

  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), rewrite.timeout_ms);
  try {
    let res;
    try {
      res = await fetchImpl(`${rewrite.url.replace(/\/+$/, '')}/chat/completions`, {
        method: 'POST',
        headers: { 'content-type': 'application/json', authorization: `Bearer ${key}` },
        body: JSON.stringify({
          model: rewrite.model,
          temperature: 0.2,
          stream: false,
          messages: [
            { role: 'system', content: EMAIL_SYSTEM_PROMPT },
            { role: 'user', content: text },
          ],
        }),
        signal: controller.signal,
        redirect: 'error',
      });
    } catch {
      return { text: null, error: controller.signal.aborted ? 'timeout' : 'network' };
    }
    if (!res.ok) {
      await res.body?.cancel().catch(() => {});
      return { text: null, error: `http_${res.status}` };
    }
    let body;
    try {
      body = await res.text();
    } catch {
      return { text: null, error: controller.signal.aborted ? 'timeout' : 'network' };
    }
    return parseCompletion(body, text);
  } finally {
    clearTimeout(timer);
  }
}

/**
 * @param {string} body
 * @param {string} input
 * @returns {{ text: string, error: null } | { text: null, error: string }}
 */
function parseCompletion(body, input) {
  if (body.trim() === '') return { text: null, error: 'empty' };
  let json;
  try {
    json = JSON.parse(body);
  } catch {
    return { text: null, error: 'bad_response' };
  }
  const choice = Array.isArray(json?.choices) ? json.choices[0] : undefined;
  if (!choice || typeof choice !== 'object') return { text: null, error: 'bad_response' };
  const content = choice.message?.content;
  if (content === null || content === undefined || content === '') return { text: null, error: 'empty' };
  if (typeof content !== 'string') return { text: null, error: 'bad_response' };
  // Một số model trả kèm khối suy luận; bỏ đi.
  const out = content.replace(/<think>[\s\S]*?<\/think>/g, '').trim();
  if (out === '') return { text: null, error: 'empty' };
  // Dài bất thường so với đầu vào: coi là phản hồi lạ, không dùng.
  if (out.length > Math.max(4000, input.length * 8)) return { text: null, error: 'bad_response' };
  return { text: out, error: null };
}

/**
 * @param {string|null} keyFile
 * @returns {string|null}
 */
function readKey(keyFile) {
  if (!keyFile) return null;
  try {
    const key = readFileSync(expandHome(keyFile), 'utf8').trim();
    return key === '' || /[\r\n]/.test(key) ? null : key;
  } catch {
    return null;
  }
}
