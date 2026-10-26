/**
 * Chấm một bộ câu: cặp `<tên>.wav` + `<tên>.txt` trong cùng thư mục.
 * Báo WER/CER nhạy và không nhạy dấu thanh, cùng chỉ số bắt thuật ngữ tiếng Anh
 * (danh sách ở eval/prompts/terms.json nếu tệp tồn tại).
 */
import fs from 'node:fs';
import fsp from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { aggregate, scoreBoth, termRecall } from './metrics.js';

export const TERMS_PATH = fileURLToPath(new URL('./prompts/terms.json', import.meta.url));

/**
 * @param {string} file
 * @returns {Promise<string[]|null>} null nếu tệp không tồn tại
 */
export async function loadTerms(file = TERMS_PATH) {
  let raw;
  try {
    raw = await fsp.readFile(file, 'utf8');
  } catch (err) {
    if (/** @type {any} */ (err).code === 'ENOENT') return null;
    throw err;
  }
  const data = JSON.parse(raw);
  if (!Array.isArray(data) || !data.every((t) => typeof t === 'string')) {
    throw new Error(`${file} phải là mảng chuỗi, ví dụ ["deploy","commit"]`);
  }
  return data.filter((t) => t.trim() !== '');
}

/**
 * Tìm các cặp wav/txt. Wav thiếu txt bị liệt kê riêng (không âm thầm bỏ qua).
 * @param {string} dir
 */
export async function findPairs(dir) {
  const names = await fsp.readdir(dir);
  const wavs = names.filter((n) => /\.wav$/i.test(n)).sort();
  const pairs = [];
  const missingRef = [];
  for (const w of wavs) {
    const base = w.replace(/\.wav$/i, '');
    const txt = names.find((n) => n.toLowerCase() === `${base.toLowerCase()}.txt`);
    if (!txt) { missingRef.push(w); continue; }
    pairs.push({ name: base, wav: path.join(dir, w), ref: (await fsp.readFile(path.join(dir, txt), 'utf8')).trim() });
  }
  return { pairs, missingRef };
}

/**
 * @param {{ items: Array<{ name: string, ref: string, hyp: string, audio_ms?: number, stt_ms?: number }>,
 *           terms: string[]|null }} input
 */
export function summarize({ items, terms }) {
  const scored = items.map((it) => ({ ...it, scores: scoreBoth(it.ref, it.hyp) }));
  return {
    count: items.length,
    tone: aggregate(scored.map((s) => s.scores.tone)),
    no_tone: aggregate(scored.map((s) => s.scores.no_tone)),
    terms: terms === null
      ? { status: 'không có eval/prompts/terms.json', rate: null }
      : termRecall(items.map(({ ref, hyp }) => ({ ref, hyp })), terms),
    items: scored,
  };
}

const pct = (r) => (r === null || r === undefined ? 'không xác định' : `${(r * 100).toFixed(2)}%`);

/** @param {ReturnType<typeof summarize> & { model: string, set: string, missing_ref: string[] }} s */
export function evalMarkdown(s) {
  const lines = [
    `### Eval \`${s.model}\` — bộ \`${s.set}\` (${s.count} câu)`,
    '',
    '| Chỉ số | Nhạy dấu thanh | Không nhạy dấu thanh |',
    '|---|---:|---:|',
    `| WER | ${pct(s.tone.wer.rate)} (${s.tone.wer.errors}/${s.tone.wer.ref_len}) | ${pct(s.no_tone.wer.rate)} (${s.no_tone.wer.errors}/${s.no_tone.wer.ref_len}) |`,
    `| CER | ${pct(s.tone.cer.rate)} (${s.tone.cer.errors}/${s.tone.cer.ref_len}) | ${pct(s.no_tone.cer.rate)} (${s.no_tone.cer.errors}/${s.no_tone.cer.ref_len}) |`,
    '',
    'terms' in s && s.terms && 'expected' in s.terms
      ? `Thuật ngữ tiếng Anh bắt đúng: ${s.terms.hit}/${s.terms.expected} (${pct(s.terms.rate)})`
      : `Thuật ngữ tiếng Anh: ${/** @type {any} */ (s.terms).status}`,
  ];
  if (s.missing_ref.length) lines.push('', `Wav thiếu tệp .txt tham chiếu (không chấm): ${s.missing_ref.join(', ')}`);
  return lines.join('\n');
}

export const exists = (p) => fs.existsSync(p);
