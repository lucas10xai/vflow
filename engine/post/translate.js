// Dịch là một đường riêng: luôn dùng LLM, không bao giờ là lựa chọn của mode=auto.
import { callLlm } from './llm.js';

const LEAD_RE = /^(?:here(?:'s| is)\s+(?:the\s+)?translation|translation\s*:|bản dịch\s*:)/iu;
const VIETNAMESE_MARK_RE = /[ăâđêôơưàáảãạằắẳẵặầấẩẫậèéẻẽẹềếểễệìíỉĩịòóỏõọồốổỗộờớởỡợùúủũụừứửữựỳýỷỹỵ]/giu;

/** Chặn đáp án là lời bình, dài/ngắn bất thường, hoặc trả nguyên tiếng Việt. */
export function checkTranslateGuard(input, output, target) {
  const out = String(output ?? '').trim();
  if (!out || LEAD_RE.test(out)) return false;
  const ratio = out.length / Math.max(1, input.trim().length);
  // Cặp CJK có thể ngắn hơn đáng kể, các cặp khác vẫn cho phép dịch cô đọng vừa phải.
  const min = ['ja', 'zh', 'ko'].includes(target) ? 0.12 : 0.25;
  if (ratio < min || ratio > 4) return false;
  if (target !== 'vi') {
    const viMarks = (out.match(VIETNAMESE_MARK_RE) ?? []).length;
    if (viMarks / Math.max(1, [...out].length) > 0.04) return false;
  }
  return true;
}

/** @param {{text:string,target:string,formality:string,rewrite:any,settings:any,fetchImpl?:typeof fetch}} args */
export async function translateText({ text, target, formality, rewrite, settings, fetchImpl }) {
  const r = await callLlm({
    rewrite, settings, fetchImpl, temperature: 0,
    messages: [
      { role: 'system', content: `Dịch chính xác văn bản tiếng Việt sang ngôn ngữ mã ${target}. Phong cách: ${formality}. Chỉ trả bản dịch, không lời dẫn, giải thích hay dấu ngoặc.` },
      { role: 'user', content: text },
    ],
    maxTokens: Math.max(64, Math.ceil(text.length * 1.5)),
  });
  if (r.error !== null) return r;
  return checkTranslateGuard(text, r.text, target) ? r : { text: null, error: 'translate_guard' };
}
