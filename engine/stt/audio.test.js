import { test } from 'node:test';
import assert from 'node:assert/strict';
import { decodeAudio, encodeWav, isSilence, parseL16, parseWav, resample, toInt16 } from './audio.js';

const sine = (freq, rate, seconds, amp = 0.5, phase = 0) => {
  const n = Math.round(rate * seconds);
  const out = new Float32Array(n);
  for (let i = 0; i < n; i++) out[i] = amp * Math.sin(2 * Math.PI * freq * (i / rate) + phase);
  return out;
};

const rms = (x, from = 0, to = x.length) => {
  let s = 0;
  for (let i = from; i < to; i++) s += x[i] * x[i];
  return Math.sqrt(s / (to - from));
};

/** Ghép WAV thủ công để thử các biến thể tiêu đề. */
function rawWav({ format = 1, channels = 1, rate = 16000, bits = 16, blockAlign, data = new Uint8Array(0), extraChunks = [], fmtSize = 16, subFormat }) {
  const fmt = new Uint8Array(fmtSize);
  const fv = new DataView(fmt.buffer);
  fv.setUint16(0, format, true); fv.setUint16(2, channels, true); fv.setUint32(4, rate, true);
  fv.setUint32(8, rate * channels * (bits / 8), true); fv.setUint16(12, blockAlign ?? channels * (bits / 8), true);
  fv.setUint16(14, bits, true);
  if (subFormat !== undefined) { fv.setUint16(16, 22, true); fv.setUint16(24, subFormat, true); }
  const chunk = (id, body) => {
    const pad = body.length % 2;
    const c = new Uint8Array(8 + body.length + pad);
    for (let i = 0; i < 4; i++) c[i] = id.charCodeAt(i);
    new DataView(c.buffer).setUint32(4, body.length, true);
    c.set(body, 8);
    return c;
  };
  const parts = [chunk('fmt ', fmt), ...extraChunks.map(([id, b]) => chunk(id, b)), chunk('data', data)];
  const total = 12 + parts.reduce((n, p) => n + p.length, 0);
  const out = new Uint8Array(total);
  out.set([82, 73, 70, 70], 0); new DataView(out.buffer).setUint32(4, total - 8, true); out.set([87, 65, 86, 69], 8);
  let o = 12;
  for (const p of parts) { out.set(p, o); o += p.length; }
  return out;
}

const pcmBytes = (int16) => new Uint8Array(int16.buffer, int16.byteOffset, int16.byteLength);

test('parseWav: PCM16 mono giữ đúng mẫu và tần số', () => {
  const pcm = Int16Array.from([0, 16384, -16384, 32767, -32768]);
  const w = parseWav(rawWav({ data: pcmBytes(pcm), rate: 22050 }));
  assert.equal(w.sampleRate, 22050);
  assert.deepEqual(Array.from(w.samples), [0, 0.5, -0.5, 32767 / 32768, -1]);
});

test('parseWav: stereo được trộn về mono bằng trung bình', () => {
  const pcm = Int16Array.from([16384, -16384, 8192, 8192]); // 2 khung
  const w = parseWav(rawWav({ channels: 2, data: pcmBytes(pcm) }));
  assert.equal(w.channels, 2);
  assert.deepEqual(Array.from(w.samples), [0, 0.25]);
});

test('parseWav: WAVE_FORMAT_EXTENSIBLE với subformat PCM được nhận, subformat float bị từ chối', () => {
  const data = pcmBytes(Int16Array.from([1000, 2000]));
  const ok = parseWav(rawWav({ format: 0xfffe, fmtSize: 40, subFormat: 1, data }));
  assert.equal(ok.samples.length, 2);
  assert.throws(() => parseWav(rawWav({ format: 0xfffe, fmtSize: 40, subFormat: 3, bits: 16, data })), { code: 'bad_audio' });
});

test('parseWav: bỏ qua khối lạ (LIST lẻ byte có đệm) trước data', () => {
  const pcm = Int16Array.from([100, 200, 300]);
  const w = parseWav(rawWav({ data: pcmBytes(pcm), extraChunks: [['LIST', new Uint8Array([1, 2, 3])]] }));
  assert.deepEqual(Array.from(w.samples).map((x) => Math.round(x * 32768)), [100, 200, 300]);
});

test('parseWav: data khai báo dài hơn thực tế (WAV luồng) ⇒ lấy phần thực có, bỏ nửa khung cuối', () => {
  const wav = rawWav({ data: pcmBytes(Int16Array.from([1, 2, 3])) });
  // Khai báo data = 0xFFFFFFFF và cắt mất 1 byte cuối.
  const cut = wav.slice(0, wav.length - 1);
  // Vị trí trường kích thước của khối data: 12 (RIFF) + 24 (khối fmt) + 4 ("data").
  new DataView(cut.buffer).setUint32(12 + 24 + 4, 0xffffffff, true);
  const w = parseWav(cut);
  assert.equal(w.samples.length, 2);
});

test('parseWav: định dạng lạ ⇒ bad_audio', () => {
  const data = new Uint8Array(8);
  assert.throws(() => parseWav(new Uint8Array([1, 2, 3])), { code: 'bad_audio' });
  assert.throws(() => parseWav(new TextEncoder().encode('RIFF\0\0\0\0AVI LIST')), { code: 'bad_audio' });
  assert.throws(() => parseWav(rawWav({ bits: 8, data })), { code: 'bad_audio' }, '8-bit');
  assert.throws(() => parseWav(rawWav({ bits: 24, data: new Uint8Array(6) })), { code: 'bad_audio' }, '24-bit');
  assert.throws(() => parseWav(rawWav({ format: 3, bits: 32, data })), { code: 'bad_audio' }, 'float');
  assert.throws(() => parseWav(rawWav({ format: 0x55, data })), { code: 'bad_audio' }, 'mp3 trong wav');
  assert.throws(() => parseWav(rawWav({ rate: 4000, data })), { code: 'bad_audio' }, 'tần số quá thấp');
  assert.throws(() => parseWav(rawWav({ channels: 0, blockAlign: 2, data })), { code: 'bad_audio' }, '0 kênh');
  assert.throws(() => parseWav(rawWav({ blockAlign: 3, data })), { code: 'bad_audio' }, 'blockAlign sai');
  const noData = rawWav({ data }).slice(0, 12 + 24); // chỉ có fmt
  new DataView(noData.buffer).setUint32(4, noData.length - 8, true);
  assert.throws(() => parseWav(noData), { code: 'bad_audio', message: /không có khối data/ });
});

test('parseL16 / decodeAudio: little-endian theo contract, tham số rate/channels, độ dài lẻ bị từ chối', () => {
  const pcm = Int16Array.from([256, -256]);
  const w = decodeAudio(pcmBytes(pcm), 'audio/L16; rate=16000; channels=1');
  assert.equal(w.sampleRate, 16000);
  assert.deepEqual(Array.from(w.samples), [256 / 32768, -256 / 32768]);
  const w8 = decodeAudio(pcmBytes(pcm), 'Audio/l16;rate=8000');
  assert.equal(w8.sampleRate, 8000);
  assert.throws(() => parseL16(new Uint8Array(3), 16000, 1), { code: 'bad_audio' });
  assert.throws(() => parseL16(new Uint8Array(6), 16000, 2), { code: 'bad_audio' });
  assert.throws(() => decodeAudio(pcmBytes(pcm), 'audio/L16; rate=abc'), { code: 'bad_audio' });
  assert.throws(() => decodeAudio(pcmBytes(pcm), 'audio/mpeg'), { code: 'bad_audio' });
  assert.throws(() => decodeAudio(pcmBytes(pcm), undefined), { code: 'bad_audio' });
});

test('encodeWav ↔ parseWav khứ hồi không đổi mẫu int16', () => {
  const x = sine(440, 16000, 0.05);
  const back = parseWav(encodeWav(x, 16000));
  assert.deepEqual(Array.from(toInt16(back.samples)), Array.from(toInt16(x)));
});

for (const [from, to] of [[44100, 16000], [48000, 16000], [22050, 16000], [8000, 16000], [16000, 48000]]) {
  test(`resample ${from}→${to}: độ dài đúng, sai số với sine 1 kHz lý tưởng < 0,2%`, () => {
    const x = sine(1000, from, 0.5, 0.5, 0.3);
    const y = resample(x, from, to);
    assert.equal(y.length, Math.round(x.length * to / from));
    const ideal = sine(1000, to, 0.5, 0.5, 0.3);
    // Bỏ 20 ms mỗi đầu (vùng biên của nhân lọc).
    const edge = Math.round(to * 0.02);
    let maxErr = 0;
    for (let i = edge; i < y.length - edge; i++) maxErr = Math.max(maxErr, Math.abs(y[i] - ideal[i]));
    assert.ok(maxErr < 0.001, `sai số tối đa ${maxErr}`);
  });
}

test('resample 48k→16k chặn chồng phổ: tone 12 kHz (trên Nyquist 8 kHz) gần như biến mất', () => {
  const y = resample(sine(12000, 48000, 0.5), 48000, 16000);
  const edge = 320;
  assert.ok(rms(y, edge, y.length - edge) < 0.005, `RMS còn ${rms(y, edge, y.length - edge)}`);
  // Còn tone 3 kHz (trong dải thông) giữ biên độ.
  const z = resample(sine(3000, 48000, 0.5), 48000, 16000);
  assert.ok(Math.abs(rms(z, edge, z.length - edge) - 0.5 / Math.SQRT2) < 0.005);
});

test('resample giữ mức DC kể cả hai đầu, cùng tần số trả bản sao', () => {
  const dc = new Float32Array(1000).fill(0.25);
  const y = resample(dc, 44100, 16000);
  for (const v of y) assert.ok(Math.abs(v - 0.25) < 1e-6);
  const same = resample(dc, 16000, 16000);
  assert.notEqual(same, dc);
  assert.deepEqual(same, dc);
  assert.equal(resample(new Float32Array(0), 44100, 16000).length, 0);
});

test('isSilence: rỗng, số 0, nhiễu -60 dBFS là im lặng; một tiếng nói ngắn -30 dBFS thì không', () => {
  assert.equal(isSilence(new Float32Array(0), 16000), true);
  assert.equal(isSilence(new Float32Array(16000), 16000), true);
  const noise = new Float32Array(16000).map((_, i) => (i % 2 ? 1 : -1) * 0.001); // -60 dBFS
  assert.equal(isSilence(noise, 16000), true);
  const burst = new Float32Array(32000);
  burst.set(sine(300, 16000, 0.1, 0.045), 16000); // ~-30 dBFS RMS trong 100 ms
  assert.equal(isSilence(burst, 16000), false);
});
