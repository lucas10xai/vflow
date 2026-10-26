// Hành động sau khi dán (post.actions, xem contract/engine-api.md mục "Hành động").
// Hiện chỉ có "enter": lời nói KẾT THÚC bằng "nhấn enter"/"bấm enter" (đúng ở cuối, bỏ dấu/hoa
// thường/dấu câu khi so khớp) ⇒ cắt cụm đó khỏi text, trả actions:["enter"].
import { fold, tokenize } from './text.js';

const WORD_PRESS = [fold('nhấn'), fold('bấm')];
const WORD_ENTER = fold('enter');
/** Sau cụm "...enter" chỉ được còn lại dấu câu/khoảng trắng, không còn từ nào khác. */
const TRAILING_PUNCT_RE = /^[\s.,!?;:…"'”’)\]]*$/u;

/**
 * @param {string} text NFC
 * @param {{ actionsEnabled?: boolean }} [opts]
 * @returns {{ text: string, actions: string[] }}
 */
export function extractEnterAction(text, { actionsEnabled = true } = {}) {
  if (!actionsEnabled) return { text, actions: [] };
  const toks = tokenize(text);
  if (toks.length < 2) return { text, actions: [] };

  const last = toks[toks.length - 1];
  const prev = toks[toks.length - 2];
  if (last.folded !== WORD_ENTER || !WORD_PRESS.includes(prev.folded)) return { text, actions: [] };
  if (!TRAILING_PUNCT_RE.test(text.slice(last.end))) return { text, actions: [] };

  const cut = text.slice(0, prev.start).replace(/[\s,]+$/u, '');
  return { text: cut, actions: ['enter'] };
}
