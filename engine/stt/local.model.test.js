/**
 * Test cần model thật (sherpa-onnx). Tự bỏ qua, có thông báo, khi chưa tải model
 * hoặc khi đặt VFLOW_SKIP_MODEL_TESTS=1 (ví dụ trên Mac để `npm test` nhẹ).
 */
import { test } from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import { createLocalProvider } from './local.js';
import { resolveModelFiles } from './models.js';
import { vflowHome } from './registry.js';
import { parseWav, resample, encodeWav } from './audio.js';
import { score } from '../../eval/metrics.js';

const home = vflowHome();

async function availability(id) {
  if (process.env.VFLOW_SKIP_MODEL_TESTS === '1') return 'bỏ qua vì VFLOW_SKIP_MODEL_TESTS=1';
  try {
    await resolveModelFiles(home, id);
    return null;
  } catch (e) {
    return `bỏ qua: model ${id} chưa dùng được ở ${home} (${e.reason}); chạy "vflow models pull ${id}"`;
  }
}

const offlineSkip = await availability('zipformer-vi-30m');
const streamingSkip = await availability('zipformer-vi-30m-streaming');
if (offlineSkip) console.log(`# ${offlineSkip}`);
if (streamingSkip) console.log(`# ${streamingSkip}`);

const testWavs = () => {
  const dir = path.join(home, 'models', 'zipformer-vi-30m', 'test_wavs');
  return fs.readdirSync(dir).filter((n) => n.endsWith('.wav')).sort().map((n) => path.join(dir, n));
};

test('zipformer-vi-30m: nhận dạng wav mẫu ra chữ tiếng Việt thường, không rỗng', { skip: offlineSkip ?? false }, async () => {
  const p = createLocalProvider({ home });
  await p.loadModel('zipformer-vi-30m');
  for (const f of testWavs()) {
    const w = parseWav(fs.readFileSync(f));
    const r = await p.transcribe({ pcm: w.samples, sampleRate: w.sampleRate });
    assert.ok(r.text.length > 0, `${path.basename(f)} ra rỗng`);
    assert.match(r.text, /[àáảãạăằắẳẵặâầấẩẫậèéẻẽẹêềếểễệìíỉĩịòóỏõọôồốổỗộơờớởỡợùúủũụưừứửữựỳýỷỹỵđ]/u, 'phải có chữ có dấu tiếng Việt');
    assert.equal(r.text, r.text.toLocaleLowerCase('vi'));
    assert.equal(r.audio_ms, Math.round((w.samples.length / w.sampleRate) * 1000));
    assert.ok(r.stt_ms >= 0);
  }
});

test('zipformer-vi-30m: cùng câu ở 22,05/44,1/48 kHz và stereo cho kết quả gần như bản 16 kHz (CER ≤ 10%)', { skip: offlineSkip ?? false }, async () => {
  const p = createLocalProvider({ home });
  await p.loadModel('zipformer-vi-30m');
  const w = parseWav(fs.readFileSync(testWavs()[0]));
  const base = (await p.transcribe({ pcm: w.samples, sampleRate: w.sampleRate })).text;
  for (const rate of [22050, 44100, 48000]) {
    const up = resample(w.samples, w.sampleRate, rate);
    const r = await p.transcribe({ pcm: up, sampleRate: rate });
    const cer = score(base, r.text).cer.rate;
    assert.ok(cer !== null && cer <= 0.1, `${rate} Hz: CER ${cer} ("${r.text}" vs "${base}")`);
  }
  const stereo = new Float32Array(w.samples.length * 2);
  for (let i = 0; i < w.samples.length; i++) { stereo[2 * i] = w.samples[i]; stereo[2 * i + 1] = w.samples[i]; }
  const sw = parseWav(encodeWav(stereo, w.sampleRate, 2));
  const rs = await p.transcribe({ pcm: sw.samples, sampleRate: sw.sampleRate });
  assert.ok(score(base, rs.text).cer.rate <= 0.1);
});

// Model thật "nghe" ra chữ (vd. "đúng") từ im lặng tuyệt đối, nên server phải chặn im lặng TRƯỚC STT.
test('server + model thật: im lặng / nhiễu rất nhỏ ⇒ silence:true, text rỗng (không bịa chữ)', { skip: offlineSkip ?? false }, async (t) => {
  const { createStt } = await import('./index.js');
  const { createServer, listen } = await import('../server/index.js');
  const token = 'a'.repeat(64);
  const post = { process: async ({ textRaw }) => ({ text: textRaw, applied: [], rewrite: { used: false, error: null } }), dictionary: {} };
  const server = createServer({ stt: createStt({ home }), post, token });
  const port = await listen(server, 0);
  t.after(() => new Promise((r) => server.close(r)));
  const noise = new Float32Array(32000).map(() => (Math.random() * 2 - 1) * 0.0015); // ≈ -60 dBFS
  for (const samples of [new Float32Array(16000), noise]) {
    const res = await fetch(`http://127.0.0.1:${port}/v1/transcribe`, {
      method: 'POST', headers: { authorization: `Bearer ${token}`, 'content-type': 'audio/wav' }, body: encodeWav(samples, 16000),
    });
    const body = await res.json();
    assert.equal(res.status, 200);
    assert.equal(body.silence, true);
    assert.equal(body.text, '');
    assert.equal(body.text_raw, '');
  }
  // Câu nói thật vẫn qua được cổng im lặng.
  const w = fs.readFileSync(testWavs()[0]);
  const res = await fetch(`http://127.0.0.1:${port}/v1/transcribe`, {
    method: 'POST', headers: { authorization: `Bearer ${token}`, 'content-type': 'audio/wav' }, body: w,
  });
  const body = await res.json();
  assert.equal(body.silence, undefined);
  assert.ok(body.text_raw.length > 0);
});

test('zipformer-vi-30m-streaming: phiên streaming phát chữ tạm tăng dần và kết quả cuối không rỗng', { skip: streamingSkip ?? (offlineSkip ? 'cần test_wavs của zipformer-vi-30m' : false) }, async () => {
  const p = createLocalProvider({ home });
  await p.loadModel('zipformer-vi-30m-streaming');
  const w = parseWav(fs.readFileSync(testWavs()[0]));
  const partials = [];
  const s = p.createSession({ onPartial: (ev) => partials.push(ev) });
  const chunk = 1600; // 100 ms
  for (let i = 0; i < w.samples.length; i += chunk) s.accept(w.samples.subarray(i, i + chunk), w.sampleRate);
  const fin = s.finish();
  assert.ok(fin.text.length > 0);
  assert.ok(partials.length >= 2, `chỉ có ${partials.length} sự kiện chữ tạm`);
  for (let i = 1; i < partials.length; i++) assert.ok(partials[i].audio_ms >= partials[i - 1].audio_ms);
  assert.throws(() => s.accept(new Float32Array(10), 16000), { code: 'bad_request' });
});
