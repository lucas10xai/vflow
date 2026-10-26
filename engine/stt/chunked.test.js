import test from 'node:test';
import assert from 'node:assert/strict';
import { planChunks, mergeChunkTexts, transcribeChunked, DEFAULT_CHUNK_SECONDS } from './chunked.js';

const RATE = 16000;

/** Sóng sin (giọng nói giả) biên độ to, `seconds` giây, bắt đầu/kết thúc tại `offset`. */
function tone(seconds, rate = RATE, amp = 0.3) {
  const n = Math.round(rate * seconds);
  const out = new Float32Array(n);
  for (let i = 0; i < n; i++) out[i] = amp * Math.sin((2 * Math.PI * 220 * i) / rate);
  return out;
}
function silence(seconds, rate = RATE) {
  return new Float32Array(Math.round(rate * seconds));
}
function concat(...parts) {
  const total = parts.reduce((n, p) => n + p.length, 0);
  const out = new Float32Array(total);
  let off = 0;
  for (const p of parts) {
    out.set(p, off);
    off += p.length;
  }
  return out;
}

test('audio ngắn (<= chunkSeconds) ⇒ một đoạn duy nhất, không cắt gì', () => {
  const samples = tone(5);
  const chunks = planChunks(samples, RATE, { chunkSeconds: 25 });
  assert.deepEqual(chunks, [{ start: 0, end: samples.length }]);
});

test('audio dài ⇒ nhiều đoạn, mỗi đoạn không vượt quá chunkSeconds + biên tìm khoảng lặng', () => {
  // 70s giọng nói liên tục, không có khoảng lặng ⇒ buộc cắt cứng ở mốc chunkSeconds.
  const samples = tone(70);
  const chunkSeconds = 25;
  const chunks = planChunks(samples, RATE, { chunkSeconds, overlapSeconds: 1 });
  assert.ok(chunks.length >= 3, `phải chia nhiều đoạn, được ${chunks.length}`);
  for (const c of chunks) {
    const durSec = (c.end - c.start) / RATE;
    assert.ok(durSec <= chunkSeconds + 4 + 0.01, `đoạn ${durSec}s vượt quá chunkSeconds + biên tìm kiếm`);
  }
  // Có chồng lấn giữa các đoạn liên tiếp (đoạn sau bắt đầu trước khi đoạn trước kết thúc).
  for (let i = 1; i < chunks.length; i++) assert.ok(chunks[i].start < chunks[i - 1].end);
  // Phủ hết toàn bộ audio, không bỏ sót đoạn cuối.
  assert.equal(chunks[chunks.length - 1].end, samples.length);
});

test('ưu tiên cắt tại khoảng lặng gần mốc chunkSeconds nhất (không cắt giữa từ)', () => {
  // 20s nói, 2s lặng (điểm cắt tự nhiên), rồi 20s nói nữa — đặt mốc chunkSeconds=21 (giữa khoảng lặng).
  const speech1 = tone(20);
  const gap = silence(2);
  const speech2 = tone(20);
  const samples = concat(speech1, gap, speech2);
  const chunks = planChunks(samples, RATE, { chunkSeconds: 21, overlapSeconds: 0.5 });
  assert.ok(chunks.length >= 2);
  const firstEnd = chunks[0].end;
  // Điểm cắt phải rơi trong khoảng lặng [20s, 22s), không rơi giữa vùng có tiếng nói.
  assert.ok(firstEnd >= speech1.length && firstEnd <= speech1.length + gap.length,
    `điểm cắt (mẫu ${firstEnd}) phải nằm trong khoảng lặng [${speech1.length}, ${speech1.length + gap.length}]`);
});

test('mergeChunkTexts: bỏ từ lặp ở biên do đoạn chồng lấn, giữ đúng thứ tự, không mất chữ', () => {
  const merged = mergeChunkTexts([
    'xin chào các bạn hôm nay chúng ta học',
    'chúng ta học về vflow và sherpa onnx',
    'onnx rất nhanh trên cpu',
  ]);
  assert.equal(merged, 'xin chào các bạn hôm nay chúng ta học về vflow và sherpa onnx rất nhanh trên cpu');
});

test('mergeChunkTexts: đoạn không trùng gì vẫn nối liền bằng khoảng trắng', () => {
  assert.equal(mergeChunkTexts(['một hai ba', 'bốn năm sáu']), 'một hai ba bốn năm sáu');
});

test('mergeChunkTexts: bỏ qua đoạn rỗng (STT câm ở một đoạn chồng lấn toàn im lặng)', () => {
  assert.equal(mergeChunkTexts(['một hai', '', 'ba bốn']), 'một hai ba bốn');
  assert.equal(mergeChunkTexts(['', '']), '');
});

test('transcribeChunked: KHÔNG đoạn nào đưa vào decodeChunk vượt quá chunkSeconds + biên tìm kiếm (RAM bị chặn trên)', async () => {
  const totalSeconds = 20 * 60; // 20 phút
  const samples = tone(totalSeconds);
  const chunkSeconds = 25;
  let maxChunkSamples = 0;
  let calls = 0;
  const decodeChunk = async (chunk) => {
    calls++;
    maxChunkSamples = Math.max(maxChunkSamples, chunk.length);
    return `đoạn ${calls}`;
  };
  const text = await transcribeChunked(samples, RATE, decodeChunk, { chunkSeconds, overlapSeconds: 1 });
  assert.ok(calls > 1, 'phải gọi decodeChunk nhiều lần cho audio 20 phút');
  const maxAllowed = (chunkSeconds + SEARCH_WINDOW_SECONDS_FOR_TEST) * RATE;
  assert.ok(maxChunkSamples <= maxAllowed, `đoạn lớn nhất ${maxChunkSamples} mẫu vượt trần cho phép ${maxAllowed}`);
  assert.ok(text.length > 0);
});
const SEARCH_WINDOW_SECONDS_FOR_TEST = 4.01;

test('audio rất ngắn hơn chunkSeconds mặc định: transcribeChunked chỉ gọi decodeChunk một lần', async () => {
  const samples = tone(3);
  let calls = 0;
  const text = await transcribeChunked(samples, RATE, async (c) => { calls++; return 'chào'; });
  assert.equal(calls, 1);
  assert.equal(text, 'chào');
  assert.ok(3 < DEFAULT_CHUNK_SECONDS);
});
