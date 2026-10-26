import test from 'node:test';
import assert from 'node:assert/strict';
import { applyAutoGain } from './gain.js';

const RATE = 16000;

/** Sóng sin đơn giản, biên độ cố định, `seconds` giây. */
function tone(amp, seconds, rate = RATE) {
  const n = Math.round(rate * seconds);
  const out = new Float32Array(n);
  for (let i = 0; i < n; i++) out[i] = amp * Math.sin((2 * Math.PI * 220 * i) / rate);
  return out;
}

function peakOf(samples) {
  let p = 0;
  for (const s of samples) p = Math.max(p, Math.abs(s));
  return p;
}
const dbfs = (lin) => 20 * Math.log10(Math.max(lin, 1e-12));

test('mảng rỗng ⇒ trả nguyên (không chia 0/lỗi)', () => {
  const out = applyAutoGain(new Float32Array(0), RATE);
  assert.equal(out.length, 0);
});

test('im lặng tuyệt đối (toàn số 0) ⇒ trả nguyên, không khuếch đại', () => {
  const out = applyAutoGain(new Float32Array(1000), RATE);
  assert.ok(out.every((v) => v === 0));
});

test('tiếng nói nhỏ (-15 dBFS, chưa chạm trần +24dB) được khuếch đại lên gần -3 dBFS', () => {
  const quiet = tone(Math.pow(10, -15 / 20), 1);
  const out = applyAutoGain(quiet, RATE);
  const outDbfs = dbfs(peakOf(out));
  assert.ok(outDbfs > -4 && outDbfs < -2, `đỉnh đầu ra ${outDbfs.toFixed(1)} dBFS phải gần -3 dBFS`);
});

test('tăng tối đa +24 dB: tiếng cực nhỏ (-60 dBFS) KHÔNG được đẩy hết lên -3 dBFS', () => {
  const veryQuiet = tone(Math.pow(10, -60 / 20), 1);
  const out = applyAutoGain(veryQuiet, RATE);
  const inDbfs = dbfs(peakOf(veryQuiet));
  const outDbfs = dbfs(peakOf(out));
  assert.ok(outDbfs <= inDbfs + 24 + 0.5, `không được tăng quá +24 dB (vào ${inDbfs.toFixed(1)}, ra ${outDbfs.toFixed(1)})`);
  assert.ok(outDbfs < -3 + 0.5, 'không đạt -3 dBFS vì bị trần +24dB chặn trước');
});

test('tiếng vốn đã to (-1 dBFS) không bị giảm âm lượng', () => {
  const loud = tone(Math.pow(10, -1 / 20), 1);
  const out = applyAutoGain(loud, RATE);
  assert.ok(dbfs(peakOf(out)) >= -1.5, 'không được làm nhỏ tiếng đã to sẵn');
});

test('im lặng/nhiễu nền rất nhỏ không bị khuếch đại thành tiếng nghe được (cổng nhiễu + trần gain)', () => {
  // Nhiễu trắng biên độ rất nhỏ, không phải giọng nói thật — mô phỏng im lặng có nhiễu máy.
  const noise = new Float32Array(Math.round(RATE * 1));
  let seed = 42;
  const rand = () => { seed = (seed * 1103515245 + 12345) & 0x7fffffff; return seed / 0x7fffffff; };
  for (let i = 0; i < noise.length; i++) noise[i] = (rand() * 2 - 1) * Math.pow(10, -65 / 20);
  const out = applyAutoGain(noise, RATE);
  assert.ok(dbfs(peakOf(out)) < -20, 'nhiễu nền phải vẫn rất nhỏ sau xử lý, không thành tiếng nghe được');
});

test('không méo/clipping: mọi mẫu đầu ra trong [-1, 1]', () => {
  const quiet = tone(Math.pow(10, -20 / 20), 0.5);
  const out = applyAutoGain(quiet, RATE);
  assert.ok(out.every((v) => v >= -1 && v <= 1));
});

test('không cắt đầu/cuối câu: đoạn có giọng nói rõ ở đầu và cuối (xen khoảng lặng giữa) vẫn còn biên độ sau xử lý', () => {
  const speechAmp = Math.pow(10, -25 / 20);
  const head = tone(speechAmp, 0.2);
  const silence = new Float32Array(Math.round(RATE * 0.3));
  const tail = tone(speechAmp, 0.2);
  const full = new Float32Array(head.length + silence.length + tail.length);
  full.set(head, 0);
  full.set(silence, head.length);
  full.set(tail, head.length + silence.length);
  const out = applyAutoGain(full, RATE);
  const headPeak = peakOf(out.subarray(0, head.length));
  const tailPeak = peakOf(out.subarray(head.length + silence.length));
  assert.ok(headPeak > 0.3, `đầu câu phải còn biên độ rõ sau khuếch đại (được ${headPeak})`);
  assert.ok(tailPeak > 0.3, `cuối câu phải còn biên độ rõ sau khuếch đại (được ${tailPeak})`);
});

test('cổng nhiễu: khung nhiễu rất nhỏ giữa hai đoạn giọng nói to bị giảm nhiều hơn khung giọng nói', () => {
  const speechAmp = Math.pow(10, -10 / 20); // to, không cần khuếch đại nhiều
  const noiseAmp = Math.pow(10, -55 / 20); // dưới ngưỡng cổng nhiễu (-45 dBFS)
  const speech = tone(speechAmp, 0.2);
  const noise = tone(noiseAmp, 0.2);
  const full = new Float32Array(speech.length + noise.length);
  full.set(speech, 0);
  full.set(noise, speech.length);
  const out = applyAutoGain(full, RATE);
  const speechPeak = peakOf(out.subarray(0, speech.length));
  // Bỏ khung 30ms đầu tiên của vùng nhiễu: khung đó nằm vắt ngang ranh giới speech/noise
  // (frame 30ms không chia hết độ dài speech) nên vẫn mang rms cao do còn lẫn mẫu giọng nói.
  const frame30ms = Math.round(RATE * 0.03);
  const noisePeak = peakOf(out.subarray(speech.length + frame30ms));
  // Tỉ lệ khuếch đại hiệu dụng của khung nhiễu phải thấp hơn rõ rệt so với khung giọng nói.
  const speechRatio = speechPeak / speechAmp;
  const noiseRatio = noisePeak / noiseAmp;
  assert.ok(noiseRatio < speechRatio * 0.5, `khung nhiễu phải bị cổng giảm nhiều hơn khung giọng nói (nhiễu x${noiseRatio.toFixed(2)}, giọng x${speechRatio.toFixed(2)})`);
});
