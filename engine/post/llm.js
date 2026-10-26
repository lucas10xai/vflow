// Client LLM dùng chung (email, tidy, command): POST {rewrite.url}/chat/completions, stream:false.
// Đọc được CẢ JSON thường LẪN SSE (9Router quan sát thật: trả SSE dù không yêu cầu stream).
// Khoá đọc từ rewrite.key_file mỗi lần gọi; không bao giờ đưa khoá/văn bản vào log/lỗi/kết quả.
import { readFileSync } from 'node:fs';
import { expandHome } from './config.js';

/** Mã lỗi có thể trả (ngoài `http_<status>`). */
export const LLM_ERROR_CODES = ['timeout', 'network', 'empty', 'bad_response', 'no_key', 'no_model', 'cloud_disabled'];

/**
 * Giọng điệu (settings.tone, contract/engine-api.md mục "Giọng điệu và nói nhỏ"): chỉ thêm MỘT
 * dòng hướng dẫn phong cách vào system prompt của tidy/email — không đổi nghĩa/thêm thông tin,
 * không ảnh hưởng guard (guard vẫn kiểm đầu ra như cũ, độc lập với tone).
 * @type {Record<string, string>}
 */
export const TONE_LINES = {
  formal: 'Giữ giọng văn trang trọng, lịch sự, đúng chuẩn mực công việc — không đổi ý nghĩa, không thêm thông tin.',
  casual: 'Giữ giọng văn tự nhiên, gần gũi, thân mật nhưng vẫn rõ ràng, đúng ngữ pháp — không đổi ý nghĩa, không thêm thông tin.',
};

/** @param {string|undefined|null} tone @returns {string|null} */
export function toneInstruction(tone) {
  return (tone && TONE_LINES[tone]) || null;
}

/**
 * @typedef {{ url: string, model: string|null, timeout_ms: number, key_file: string|null }} RewriteConfig
 * @typedef {{ cloud_llm?: boolean, llm_model?: string|null, llm_timeout_ms?: number }} LlmSettings
 */

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

/**
 * Gọi endpoint OpenAI-compatible. Không ném lỗi: mọi thất bại trả về `{ text: null, error }`.
 * @param {{ messages: {role:string, content:string}[], rewrite: RewriteConfig, settings?: LlmSettings,
 *           fetchImpl?: typeof fetch, maxOutputChars?: number, temperature?: number, maxTokens?: number }} args
 * @returns {Promise<{ text: string, error: null } | { text: null, error: string }>}
 */
export async function callLlm({ messages, rewrite, settings, fetchImpl = fetch, maxOutputChars, temperature = 0.2, maxTokens }) {
  const cloudLlm = settings?.cloud_llm ?? true;
  if (!cloudLlm) return { text: null, error: 'cloud_disabled' };

  const model = settings?.llm_model ?? rewrite.model;
  if (!model) return { text: null, error: 'no_model' };

  const key = readKey(rewrite.key_file);
  if (!key) return { text: null, error: 'no_key' };

  const timeoutMs = settings?.llm_timeout_ms ?? rewrite.timeout_ms;
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), timeoutMs);
  try {
    let res;
    try {
      res = await fetchImpl(`${rewrite.url.replace(/\/+$/, '')}/chat/completions`, {
        method: 'POST',
        headers: { 'content-type': 'application/json', authorization: `Bearer ${key}` },
        body: JSON.stringify({ model, temperature, stream: false, messages, ...(maxTokens ? { max_tokens: maxTokens } : {}) }),
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
    return finishContent(parseBody(body), maxOutputChars);
  } finally {
    clearTimeout(timer);
  }
}

/**
 * Phân tích thân phản hồi: thử JSON thường trước, rồi SSE (`data: {...}` từng dòng, bỏ `[DONE]`,
 * ghép `choices[0].delta.content`).
 * @param {string} body
 * @returns {{ content: string, error: null } | { content: null, error: string }}
 */
function parseBody(body) {
  const trimmed = body.trim();
  if (trimmed === '') return { content: null, error: 'empty' };

  const asJson = tryParseJson(trimmed);
  if (asJson !== undefined) return extractFromChoice(asJson);

  const lines = trimmed.split(/\r?\n/).filter((l) => l.startsWith('data:'));
  if (lines.length === 0) return { content: null, error: 'bad_response' };
  let content = '';
  let any = false;
  for (const line of lines) {
    const payload = line.slice(5).trim();
    if (payload === '' || payload === '[DONE]') continue;
    const obj = tryParseJson(payload);
    if (obj === undefined) return { content: null, error: 'bad_response' };
    const delta = obj?.choices?.[0]?.delta?.content;
    if (typeof delta === 'string') {
      content += delta;
      any = true;
    } else if (delta !== undefined && delta !== null) {
      return { content: null, error: 'bad_response' };
    }
  }
  if (!any) return { content: null, error: 'bad_response' };
  return { content, error: null };
}

/** @param {string} s @returns {any} undefined nếu không phải JSON hợp lệ */
function tryParseJson(s) {
  try {
    return JSON.parse(s);
  } catch {
    return undefined;
  }
}

/** @param {any} json */
function extractFromChoice(json) {
  const choice = Array.isArray(json?.choices) ? json.choices[0] : undefined;
  if (!choice || typeof choice !== 'object') return { content: null, error: 'bad_response' };
  const content = choice.message?.content;
  if (content === null || content === undefined || content === '') return { content: null, error: 'empty' };
  if (typeof content !== 'string') return { content: null, error: 'bad_response' };
  return { content, error: null };
}

/**
 * @param {{ content: string, error: null } | { content: null, error: string }} parsed
 * @param {number|undefined} maxOutputChars
 * @returns {{ text: string, error: null } | { text: null, error: string }}
 */
function finishContent(parsed, maxOutputChars) {
  if (parsed.error !== null) return { text: null, error: parsed.error };
  // Một số model trả kèm khối suy luận; bỏ đi.
  const out = parsed.content.replace(/<think>[\s\S]*?<\/think>/g, '').trim();
  if (out === '') return { text: null, error: 'empty' };
  if (typeof maxOutputChars === 'number' && out.length > maxOutputChars) return { text: null, error: 'bad_response' };
  return { text: out, error: null };
}
