// Ghi âm dài (contract/engine-api.md mục "Ghi âm dài"): xử lý audio dài theo ĐOẠN để không giữ
// toàn bộ audio trong bộ đệm/tính năng của model nhận dạng một lần (RAM không tăng vô hạn theo độ
// dài audio) — cắt ở khoảng lặng khi có thể, chồng nhẹ giữa hai đoạn, ghép lại không lặp chữ ở biên.
import { isSilence } from './audio.js';

export const DEFAULT_CHUNK_SECONDS = 25;
export const DEFAULT_OVERLAP_SECONDS = 1.5;
const SEARCH_WINDOW_SECONDS = 4; // tìm điểm lặng quanh mốc cắt mong muốn, trong khoảng này
const MAX_OVERLAP_WORDS = 12;

/**
 * Điểm cắt tốt nhất (giữa một khung 30ms im lặng) gần `targetIndex` nhất, trong phạm vi tìm kiếm.
 * `-1` nếu không có khoảng lặng nào trong phạm vi (cắt cứng tại targetIndex).
 * @param {Float32Array} samples @param {number} sampleRate @param {number} targetIndex @param {number} searchSamples
 */
function findSilenceCut(samples, sampleRate, targetIndex, searchSamples) {
  const frame = Math.max(1, Math.round(sampleRate * 0.03));
  const lo = Math.max(frame, targetIndex - searchSamples);
  const hi = Math.min(samples.length - frame, targetIndex + searchSamples);
  let best = -1;
  let bestDist = Infinity;
  for (let i = lo; i <= hi; i += frame) {
    if (isSilence(samples.subarray(i, Math.min(samples.length, i + frame)), sampleRate)) {
      const dist = Math.abs(i - targetIndex);
      if (dist < bestDist) {
        bestDist = dist;
        best = i;
      }
    }
  }
  return best;
}

/**
 * @typedef {{ start: number, end: number }} ChunkRange chỉ số mẫu [start, end)
 */

/**
 * Chia audio thành các đoạn <= chunkSeconds, ưu tiên cắt ở khoảng lặng, chồng lấn `overlapSeconds`
 * giữa hai đoạn liên tiếp (để STT không mất chữ ở biên đoạn).
 * @param {Float32Array} samples @param {number} sampleRate
 * @param {{ chunkSeconds?: number, overlapSeconds?: number }} [opts]
 * @returns {ChunkRange[]}
 */
export function planChunks(samples, sampleRate, { chunkSeconds = DEFAULT_CHUNK_SECONDS, overlapSeconds = DEFAULT_OVERLAP_SECONDS } = {}) {
  const chunkLen = Math.round(chunkSeconds * sampleRate);
  if (samples.length <= chunkLen) return [{ start: 0, end: samples.length }];

  const overlapLen = Math.round(overlapSeconds * sampleRate);
  const searchLen = Math.round(SEARCH_WINDOW_SECONDS * sampleRate);
  /** @type {ChunkRange[]} */
  const chunks = [];
  let start = 0;
  while (start < samples.length) {
    const target = start + chunkLen;
    if (target >= samples.length) {
      chunks.push({ start, end: samples.length });
      break;
    }
    const cut = findSilenceCut(samples, sampleRate, target, searchLen);
    const end = cut === -1 ? target : cut;
    chunks.push({ start, end });
    const minNextStart = chunks[chunks.length - 1].start + 1;
    start = Math.max(end - overlapLen, minNextStart);
  }
  return chunks;
}

/**
 * Chữ chung dài nhất ở ĐUÔI `prevWords` khớp ĐẦU `nextWords` (không phân hoa/thường) — phần
 * chồng lấn do hai đoạn cùng chứa. Trả số từ khớp (0 nếu không khớp gì).
 * @param {string[]} prevWords @param {string[]} nextWords
 */
function overlapWordCount(prevWords, nextWords) {
  const maxK = Math.min(MAX_OVERLAP_WORDS, prevWords.length, nextWords.length);
  for (let k = maxK; k >= 1; k--) {
    const a = prevWords.slice(-k).join(' ').toLowerCase();
    const b = nextWords.slice(0, k).join(' ').toLowerCase();
    if (a === b) return k;
  }
  return 0;
}

/**
 * Ghép chữ của các đoạn đã nhận dạng, bỏ phần lặp ở biên (do đoạn chồng lấn), KHÔNG mất chữ.
 * @param {string[]} texts
 * @returns {string}
 */
export function mergeChunkTexts(texts) {
  let out = '';
  let outWords = [];
  for (const raw of texts) {
    const text = raw.trim();
    if (text === '') continue;
    const words = text.split(/\s+/);
    if (out === '') {
      out = text;
      outWords = words;
      continue;
    }
    const k = overlapWordCount(outWords, words);
    const rest = words.slice(k);
    if (rest.length > 0) {
      out += ' ' + rest.join(' ');
      outWords = rest;
    } else {
      outWords = [];
    }
  }
  return out;
}

/**
 * Nhận dạng audio dài theo đoạn: tại mọi thời điểm chỉ một đoạn (<= chunkSeconds) được đưa vào
 * `decodeChunk`, giữ RAM/tính năng của model bị giới hạn — không tăng tuyến tính theo tổng độ dài.
 * @param {Float32Array} samples @param {number} sampleRate
 * @param {(chunk: Float32Array) => Promise<string>} decodeChunk
 * @param {{ chunkSeconds?: number, overlapSeconds?: number }} [opts]
 * @returns {Promise<string>}
 */
export async function transcribeChunked(samples, sampleRate, decodeChunk, opts) {
  const chunks = planChunks(samples, sampleRate, opts);
  const texts = [];
  for (const c of chunks) texts.push(await decodeChunk(samples.subarray(c.start, c.end)));
  return mergeChunkTexts(texts);
}
