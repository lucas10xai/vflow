// Command Mode (contract/engine-api.md mục "Command Mode"): sửa (có selection) hoặc soạn mới
// (không có selection) văn bản theo lệnh nói. Lỗi KHÔNG BAO GIỜ trả văn bản giả.
import { callLlm } from './llm.js';

export const MAX_FIELD_CHARS = 20000;

export class CommandError extends Error {
  /** @param {string} code @param {string} message */
  constructor(code, message) {
    super(message);
    this.code = code;
  }
}

const EDIT_SYSTEM_PROMPT = [
  'Bạn sửa một đoạn văn bản đang được chọn trong ứng dụng khác, theo lệnh nói của người dùng.',
  'Chỉ trả về ĐÚNG đoạn văn bản đã sửa để thay thế đoạn đang chọn — không lời dẫn, không giải thích,',
  'không bọc trong dấu ngoặc kép hay khối mã (```), không lặp lại lệnh.',
  'Giữ nguyên định dạng (xuống dòng, danh sách, mã…) và ngôn ngữ gốc của đoạn đang chọn, trừ khi lệnh',
  'yêu cầu đổi. Chỉ thay đổi đúng những gì lệnh yêu cầu, không tự thêm nội dung khác.',
].join('\n');

const DRAFT_SYSTEM_PROMPT = [
  'Bạn soạn mới một đoạn văn bản theo lệnh nói của người dùng, để dán vào ô văn bản đang focus.',
  'Chỉ trả về ĐÚNG nội dung đã soạn — không lời dẫn, không giải thích, không bọc trong dấu ngoặc kép',
  'hay khối mã (```), không lặp lại lệnh.',
].join('\n');

/** @param {string} v @param {string} field */
function checkFieldLength(v, field) {
  if (typeof v === 'string' && v.length > MAX_FIELD_CHARS) {
    throw new CommandError('bad_request', `${field} vượt quá ${MAX_FIELD_CHARS} ký tự.`);
  }
}

/** @param {{instruction:string, selection:string, context:string}} fields */
function buildMessages({ instruction, selection, context }) {
  if (selection.trim() !== '') {
    const parts = [`Lệnh: ${instruction}`];
    if (context.trim() !== '') parts.push(`Văn bản xung quanh (chỉ để tham khảo ngữ cảnh, KHÔNG trả lại):\n${context}`);
    parts.push(`Đoạn đang chọn (sửa lại đúng đoạn này theo lệnh):\n${selection}`);
    return [{ role: 'system', content: EDIT_SYSTEM_PROMPT }, { role: 'user', content: parts.join('\n\n') }];
  }
  const parts = [`Lệnh: ${instruction}`];
  if (context.trim() !== '') parts.push(`Văn bản xung quanh (chỉ để tham khảo ngữ cảnh):\n${context}`);
  return [{ role: 'system', content: DRAFT_SYSTEM_PROMPT }, { role: 'user', content: parts.join('\n\n') }];
}

/** Mã lỗi LLM dùng chung -> mã lỗi Command Mode theo contract. */
function toCommandCode(llmError) {
  if (llmError === 'cloud_disabled') return 'cloud_disabled';
  if (llmError === 'timeout') return 'timeout';
  return 'rewrite_unavailable'; // network, empty, bad_response, no_key, no_model, http_<status>
}

/**
 * @param {{ instruction: unknown, selection?: unknown, context?: unknown,
 *           rewrite: import('./llm.js').RewriteConfig, settings?: import('./llm.js').LlmSettings,
 *           fetchImpl?: typeof fetch }} args
 * @returns {Promise<{ text: string, kind: 'edit'|'draft', timings_ms: { llm: number } }>}
 */
export async function runCommand({ instruction, selection = '', context = '', rewrite, settings, fetchImpl = fetch }) {
  if (typeof instruction !== 'string' || instruction.trim() === '') {
    throw new CommandError('bad_request', 'instruction phải là chuỗi khác rỗng.');
  }
  if (typeof selection !== 'string') throw new CommandError('bad_request', 'selection phải là chuỗi.');
  if (typeof context !== 'string') throw new CommandError('bad_request', 'context phải là chuỗi.');
  checkFieldLength(instruction, 'instruction');
  checkFieldLength(selection, 'selection');
  checkFieldLength(context, 'context');

  const kind = selection.trim() !== '' ? 'edit' : 'draft';
  const started = Date.now();
  const r = await callLlm({ messages: buildMessages({ instruction, selection, context }), rewrite, settings, fetchImpl });
  const llmMs = Date.now() - started;
  if (r.error !== null) throw new CommandError(toCommandCode(r.error), commandErrorMessage(r.error));
  return { text: r.text, kind, timings_ms: { llm: llmMs } };
}

/** @param {string} code */
function commandErrorMessage(code) {
  if (code === 'cloud_disabled') return 'Chế độ đám mây đang tắt, không thể dùng Command Mode.';
  if (code === 'timeout') return 'Lệnh xử lý quá thời gian, vui lòng thử lại.';
  return 'Không thể xử lý lệnh lúc này (dịch vụ viết lại không khả dụng).';
}
