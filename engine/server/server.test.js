/**
 * Test server theo contract/engine-api.md. STT là provider giả qua `providerFactory`
 * (đi qua bộ quản lý thật); hậu xử lý là bản giả có từ điển đơn giản — hậu xử lý thật
 * ở engine/post được ghép ở `vflow serve` và kiểm ở đợt tích hợp.
 */
import { test, before, after } from 'node:test';
import assert from 'node:assert/strict';
import http from 'node:http';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { createServer, listen } from './index.js';
import { ensureToken, tokenMatches } from './token.js';
import { createStt } from '../stt/index.js';
import { encodeWav, toInt16 } from '../stt/audio.js';

const SPOKEN = 'anh đi plôi bản mới nhé';

const sine = (rate, seconds, amp = 0.3) => {
  const x = new Float32Array(Math.round(rate * seconds));
  for (let i = 0; i < x.length; i++) x[i] = amp * Math.sin(2 * Math.PI * 220 * (i / rate));
  return x;
};

/** Provider giả: ghi lại đầu vào, trả câu cố định. */
function fakeProviders() {
  const calls = [];
  const factory = (id) => {
    if (!['fake', 'mute', 'broken', 'zipformer-vi-30m', 'phowhisper-large'].includes(id)) return null;
    if (id === 'broken') {
      return { loaded: false, loadModel: async () => { const e = new Error('Model "broken" thiếu tệp encoder.'); Object.assign(e, { code: 'model_unavailable', reason: 'files_missing' }); throw e; }, transcribe: async () => { throw new Error('không được gọi'); } };
    }
    const p = {
      loaded: false,
      async loadModel() { p.loaded = true; },
      async transcribe({ pcm, sampleRate }) {
        calls.push({ id, n: pcm.length, sampleRate });
        return { text: id === 'mute' ? '' : SPOKEN, audio_ms: Math.round((pcm.length / sampleRate) * 1000), stt_ms: 12 };
      },
    };
    return p;
  };
  return { calls, factory };
}

function fakePost({ rewriteFails = false } = {}) {
  const state = { entries: [{ term: 'deploy', spoken: ['đi plôi'] }], lastReplace: null };
  return {
    state,
    async process({ textRaw, mode }) {
      const text = textRaw.replace('đi plôi', 'deploy');
      const applied = text === textRaw ? [] : [{ type: 'dictionary', from: 'đi plôi', to: 'deploy' }];
      if (mode === 'email' && rewriteFails) return { text, mode, applied, rewrite: { used: false, error: 'timeout' } };
      return { text, mode, applied, rewrite: { used: false, error: null } };
    },
    dictionary: {
      list: () => ({ entries: state.entries }),
      replaceAll: (entries) => {
        if (entries.some((e) => typeof e.term !== 'string')) { const e = new Error('entries[0].term phải là chuỗi'); e.code = 'bad_request'; throw e; }
        if (entries.some((e) => e.term === 'disk')) throw Object.assign(new Error('EACCES: /secret/path'), { code: 'EACCES' });
        state.entries = entries;
      },
      learnCorrection: ({ before: b, after: a }) => ({ suggestions: [{ term: a, spoken: [b] }] }),
    },
  };
}

/**
 * @param {number} port
 * @param {{ method?: string, path: string, headers?: Record<string,string>, body?: Uint8Array|string }} o
 */
function request(port, { method = 'GET', path: p, headers = {}, body }) {
  return new Promise((resolve, reject) => {
    const req = http.request({ host: '127.0.0.1', port, method, path: p, headers: { host: `127.0.0.1:${port}`, ...headers } }, (res) => {
      const chunks = [];
      res.on('data', (c) => chunks.push(c));
      res.on('end', () => {
        const text = Buffer.concat(chunks).toString('utf8');
        let json = null;
        try { json = JSON.parse(text); } catch { /* không phải JSON */ }
        resolve({ status: res.statusCode, headers: res.headers, json, text });
      });
    });
    req.on('error', reject);
    if (body !== undefined) req.write(body);
    req.end();
  });
}

let tmp; let server; let port; let token; let logs; let fakes; let post; let realServer; let realPort;

/** Liệt kê đệ quy mọi tệp dưới một thư mục. */
function listFiles(dir) {
  if (!fs.existsSync(dir)) return [];
  return fs.readdirSync(dir, { recursive: true, withFileTypes: true })
    .filter((d) => d.isFile()).map((d) => path.join(d.parentPath ?? d.path, d.name)).sort();
}

before(async () => {
  tmp = fs.mkdtempSync(path.join(os.tmpdir(), 'vflow-server-test-'));
  ({ token } = await ensureToken(path.join(tmp, 'token')));
  logs = [];
  fakes = fakeProviders();
  post = fakePost({ rewriteFails: true });
  const stt = createStt({ home: tmp, providerFactory: fakes.factory, config: { default_model: 'fake' } });
  server = createServer({ stt, post, token, log: (e) => logs.push(JSON.stringify(e)), maxAudioSeconds: 120 });
  port = await listen(server, 0);
  // Server thứ hai dùng bộ quản lý STT thật với thư mục rỗng (chưa tải model nào).
  const realStt = createStt({ home: path.join(tmp, 'empty-home'), env: {} });
  realServer = createServer({ stt: realStt, post: fakePost(), token, log: () => {} });
  realPort = await listen(realServer, 0);
});

after(async () => {
  await new Promise((r) => server.close(r));
  await new Promise((r) => realServer.close(r));
  fs.rmSync(tmp, { recursive: true, force: true });
});

const auth = () => ({ authorization: `Bearer ${token}` });
const wav = (rate, seconds, channels = 1) => {
  const mono = sine(rate, seconds);
  if (channels === 1) return encodeWav(mono, rate);
  const inter = new Float32Array(mono.length * channels);
  for (let i = 0; i < mono.length; i++) for (let c = 0; c < channels; c++) inter[i * channels + c] = mono[i];
  return encodeWav(inter, rate, channels);
};

test('token: 64 hex, tệp 0600 (POSIX), đọc lại cùng giá trị, tệp hỏng ⇒ lỗi chứ không ghi đè', async () => {
  assert.match(token, /^[0-9a-f]{64}$/);
  const f = path.join(tmp, 'token');
  if (process.platform !== 'win32') assert.equal(fs.statSync(f).mode & 0o777, 0o600);
  assert.equal((await ensureToken(f)).token, token);
  const bad = path.join(tmp, 'bad-token');
  fs.writeFileSync(bad, 'abc');
  await assert.rejects(ensureToken(bad), /không đúng định dạng/);
  assert.equal(fs.readFileSync(bad, 'utf8'), 'abc');
  assert.ok(tokenMatches(token, token));
  assert.ok(!tokenMatches(token.slice(0, -1) + (token.at(-1) === 'a' ? 'b' : 'a'), token));
});

test('server chỉ nghe 127.0.0.1', () => {
  assert.equal(server.address().address, '127.0.0.1');
});

test('GET /healthz không cần token; model chưa dùng được luôn có reason', async () => {
  const r = await request(realPort, { path: '/healthz' });
  assert.equal(r.status, 200);
  assert.equal(r.json.ok, true);
  assert.equal(r.json.version, '0.1.0');
  const local = r.json.models.find((m) => m.id === 'zipformer-vi-30m');
  assert.deepEqual(local, { id: 'zipformer-vi-30m', kind: 'local', loaded: false, reason: 'not_downloaded' });
  const remote = r.json.models.find((m) => m.id === 'phowhisper-large');
  assert.equal(remote.reason, 'missing_token');
  for (const m of r.json.models) if (!m.loaded) assert.ok(m.reason, `${m.id} thiếu reason`);
});

test('bất biến 3: thiếu token / sai token / sai kiểu ⇒ 401 unauthorized', async () => {
  const body = wav(16000, 1);
  for (const headers of [{}, { authorization: 'Bearer ' + '0'.repeat(64) }, { authorization: token }, { authorization: `Basic ${token}` }]) {
    const r = await request(port, { method: 'POST', path: '/v1/transcribe', headers: { 'content-type': 'audio/wav', ...headers }, body });
    assert.equal(r.status, 401);
    assert.equal(r.json.error.code, 'unauthorized');
  }
  for (const p of ['/v1/dictionary', '/v1/corrections']) {
    const r = await request(port, { path: p });
    assert.equal(r.status, 401);
  }
  assert.equal(fakes.calls.length, 0, 'không được gọi STT khi chưa xác thực');
});

test('bất biến 3: Host lạ bị từ chối (cả /healthz và khi có token đúng), Origin bị từ chối', async () => {
  for (const host of ['evil.example:' + port, `127.0.0.1:${port + 1}`, '127.0.0.1', `0.0.0.0:${port}`, `localhost.evil.com:${port}`]) {
    const r = await request(port, { path: '/healthz', headers: { host } });
    assert.equal(r.status, 403, host);
    const t = await request(port, { method: 'POST', path: '/v1/transcribe', headers: { host, ...auth(), 'content-type': 'audio/wav' }, body: wav(16000, 1) });
    assert.equal(t.status, 403, host);
  }
  const ok = await request(port, { path: '/healthz', headers: { host: `localhost:${port}` } });
  assert.equal(ok.status, 200);
  const o = await request(port, { path: '/healthz', headers: { origin: 'http://evil.example' } });
  assert.equal(o.status, 403);
  assert.equal(fakes.calls.length, 0);
});

test('không gửi header CORS, kể cả với OPTIONS', async () => {
  const r = await request(port, { method: 'OPTIONS', path: '/v1/transcribe', headers: auth() });
  assert.notEqual(r.status, 200);
  const h = await request(port, { path: '/healthz' });
  for (const res of [r, h]) {
    assert.ok(!Object.keys(res.headers).some((k) => k.startsWith('access-control-')), JSON.stringify(res.headers));
  }
});

test('audio/wav 44,1 kHz stereo: đúng schema, text_raw là chữ STT gốc, text từ hậu xử lý', async () => {
  const before = fakes.calls.length;
  const r = await request(port, { method: 'POST', path: '/v1/transcribe?mode=clean', headers: { ...auth(), 'content-type': 'audio/wav' }, body: wav(44100, 2, 2) });
  assert.equal(r.status, 200, r.text);
  const b = r.json;
  assert.match(b.id, /^tr_/);
  assert.equal(b.model, 'fake');
  assert.equal(b.mode, 'clean');
  assert.equal(b.language, 'vi');
  assert.equal(b.text_raw, SPOKEN);
  assert.equal(b.text, 'anh deploy bản mới nhé');
  assert.equal(b.audio_ms, 2000);
  assert.equal(b.timings_ms.stt, 12);
  assert.equal(typeof b.timings_ms.post, 'number');
  assert.equal(typeof b.timings_ms.total, 'number');
  assert.equal(b.rtf, 0.006);
  assert.deepEqual(b.post.applied, [{ type: 'dictionary', from: 'đi plôi', to: 'deploy' }]);
  assert.deepEqual(b.post.rewrite, { used: false, error: null });
  assert.equal(b.silence, undefined);
  const call = fakes.calls[before];
  assert.equal(call.sampleRate, 44100);
  assert.equal(call.n, 88200, 'stereo đã trộn về mono, độ dài theo khung');
});

test('audio/L16 16 kHz mono dùng được', async () => {
  const pcm = toInt16(sine(16000, 1.5));
  const r = await request(port, {
    method: 'POST', path: '/v1/transcribe',
    headers: { ...auth(), 'content-type': 'audio/L16; rate=16000; channels=1' },
    body: new Uint8Array(pcm.buffer),
  });
  assert.equal(r.status, 200, r.text);
  assert.equal(r.json.audio_ms, 1500);
  assert.equal(r.json.text_raw, SPOKEN);
});

test('bất biến 2 (qua server): viết lại lỗi ⇒ text là bản đã qua từ điển, text_raw giữ chữ STT gốc, rewrite.error có giá trị', async () => {
  const r = await request(port, { method: 'POST', path: '/v1/transcribe?mode=email', headers: { ...auth(), 'content-type': 'audio/wav' }, body: wav(16000, 1) });
  assert.equal(r.status, 200);
  assert.equal(r.json.text_raw, SPOKEN);
  assert.equal(r.json.text, 'anh deploy bản mới nhé');
  assert.deepEqual(r.json.post.rewrite, { used: false, error: 'timeout' });
});

test('im lặng ⇒ 200, text "", silence:true, không gọi STT; STT trả rỗng cũng ⇒ silence:true', async () => {
  const before = fakes.calls.length;
  const r = await request(port, { method: 'POST', path: '/v1/transcribe', headers: { ...auth(), 'content-type': 'audio/wav' }, body: encodeWav(new Float32Array(16000), 16000) });
  assert.equal(r.status, 200, r.text);
  assert.equal(r.json.text, '');
  assert.equal(r.json.text_raw, '');
  assert.equal(r.json.silence, true);
  assert.equal(fakes.calls.length, before);
  const empty = await request(port, { method: 'POST', path: '/v1/transcribe', headers: { ...auth(), 'content-type': 'audio/L16; rate=16000' }, body: new Uint8Array(0) });
  assert.equal(empty.status, 200);
  assert.equal(empty.json.silence, true);
  const mute = await request(port, { method: 'POST', path: '/v1/transcribe?model=mute', headers: { ...auth(), 'content-type': 'audio/wav' }, body: wav(16000, 1) });
  assert.equal(mute.json.silence, true);
  assert.equal(mute.json.text, '');
});

test('bất biến 4: model chưa tải ⇒ 503 model_unavailable có lý do, không rơi sang model khác', async () => {
  const r = await request(realPort, { method: 'POST', path: '/v1/transcribe', headers: { ...auth(), 'content-type': 'audio/wav' }, body: wav(16000, 1) });
  assert.equal(r.status, 503);
  assert.equal(r.json.error.code, 'model_unavailable');
  assert.match(r.json.error.message, /not_downloaded/);
  // Âm thanh im lặng cũng không được trả "im lặng" giả khi model hỏng.
  const s = await request(realPort, { method: 'POST', path: '/v1/transcribe', headers: { ...auth(), 'content-type': 'audio/wav' }, body: encodeWav(new Float32Array(8000), 16000) });
  assert.equal(s.status, 503);
  // Model hỏng ở server giả: dù model mặc định chạy tốt, không được trả kết quả của nó.
  const before = fakes.calls.length;
  const b = await request(port, { method: 'POST', path: '/v1/transcribe?model=broken', headers: { ...auth(), 'content-type': 'audio/wav' }, body: wav(16000, 1) });
  assert.equal(b.status, 503);
  assert.equal(b.json.error.code, 'model_unavailable');
  assert.match(b.json.error.message, /files_missing/);
  assert.equal(fakes.calls.length, before);
  // Từ xa không có token ⇒ lý do missing_token.
  const rem = await request(realPort, { method: 'POST', path: '/v1/transcribe?model=phowhisper-large', headers: { ...auth(), 'content-type': 'audio/wav' }, body: wav(16000, 1) });
  assert.equal(rem.status, 503);
  assert.match(rem.json.error.message, /VFLOW_REMOTE_TOKEN/);
});

test('mã lỗi: bad_audio, bad_request, payload_too_large (> 120 s)', async () => {
  const bad = await request(port, { method: 'POST', path: '/v1/transcribe', headers: { ...auth(), 'content-type': 'audio/wav' }, body: 'không phải wav' });
  assert.equal(bad.status, 400);
  assert.equal(bad.json.error.code, 'bad_audio');
  const mp3 = await request(port, { method: 'POST', path: '/v1/transcribe', headers: { ...auth(), 'content-type': 'audio/mpeg' }, body: 'ID3' });
  assert.equal(mp3.json.error.code, 'bad_audio');
  for (const q of ['mode=poem', 'lang=en', 'model=khong-co']) {
    const r = await request(port, { method: 'POST', path: `/v1/transcribe?${q}`, headers: { ...auth(), 'content-type': 'audio/wav' }, body: wav(16000, 1) });
    assert.equal(r.status, 400, q);
    assert.equal(r.json.error.code, 'bad_request', q);
  }
  // 121 s ở 8 kHz (≈1,9 MB) vượt giới hạn thời lượng; 120 s thì được.
  const long = await request(port, { method: 'POST', path: '/v1/transcribe', headers: { ...auth(), 'content-type': 'audio/L16; rate=8000' }, body: new Uint8Array(8000 * 2 * 121) });
  assert.equal(long.status, 413);
  assert.equal(long.json.error.code, 'payload_too_large');
  const ok = await request(port, { method: 'POST', path: '/v1/transcribe', headers: { ...auth(), 'content-type': 'audio/L16; rate=8000' }, body: new Uint8Array(8000 * 2 * 120) });
  assert.equal(ok.status, 200);
  const huge = await request(port, { method: 'POST', path: '/v1/transcribe', headers: { ...auth(), 'content-type': 'audio/wav', 'content-length': String(200 * 1024 * 1024) } });
  assert.equal(huge.status, 413);
  const nf = await request(port, { path: '/v1/khong-co', headers: auth() });
  assert.equal(nf.status, 404);
  assert.equal(nf.json.error.code, 'bad_request');
});

test('bất biến 1: không tạo tệp mới trong thư mục tạm hay VFLOW_HOME khi nhận dạng; log không chứa văn bản', async () => {
  // Trỏ thư mục tạm của tiến trình (os.tmpdir() đọc TMPDIR/TEMP/TMP mỗi lần gọi) vào một thư mục
  // riêng, rỗng: mọi tệp tạm do server tạo ra sẽ rơi vào đây. Mỗi tệp test chạy ở tiến trình riêng.
  const isolated = fs.mkdtempSync(path.join(tmp, 'tmpdir-'));
  const saved = { TMPDIR: process.env.TMPDIR, TEMP: process.env.TEMP, TMP: process.env.TMP };
  Object.assign(process.env, { TMPDIR: isolated, TEMP: isolated, TMP: isolated });
  try {
    assert.equal(os.tmpdir(), isolated);
    const beforeFiles = listFiles(tmp);
    logs.length = 0;
    for (const [ct, body] of [['audio/wav', wav(48000, 1)], ['audio/L16; rate=16000; channels=1', new Uint8Array(toInt16(sine(16000, 1)).buffer)]]) {
      for (const mode of ['normal', 'email']) {
        const r = await request(port, { method: 'POST', path: `/v1/transcribe?mode=${mode}`, headers: { ...auth(), 'content-type': ct }, body });
        assert.equal(r.status, 200);
      }
    }
    assert.deepEqual(fs.readdirSync(isolated), []);
    assert.deepEqual(listFiles(tmp), beforeFiles);
  } finally {
    for (const [k, v] of Object.entries(saved)) { if (v === undefined) delete process.env[k]; else process.env[k] = v; }
  }
  assert.ok(logs.length >= 4);
  const all = logs.join('\n');
  for (const word of ['plôi', 'deploy', 'bản mới', token]) assert.ok(!all.includes(word), `log lộ "${word}"`);
  const e = JSON.parse(logs[0]);
  assert.match(e.id, /^tr_/);
  assert.equal(e.audio_ms, 1000);
  assert.equal(typeof e.stt_ms, 'number');
  assert.equal(typeof e.total_ms, 'number');
});

test('/v1/dictionary và /v1/corrections chuyển tiếp sang post.dictionary; lỗi kiểm dữ liệu ⇒ bad_request, lỗi khác ⇒ internal không lộ chi tiết', async () => {
  const g = await request(port, { path: '/v1/dictionary', headers: auth() });
  assert.equal(g.status, 200);
  assert.equal(g.json.entries[0].term, 'deploy');
  const entries = [{ term: 'commit', spoken: ['cơ mít'] }];
  const p = await request(port, { method: 'PUT', path: '/v1/dictionary', headers: { ...auth(), 'content-type': 'application/json' }, body: JSON.stringify({ entries }) });
  assert.equal(p.status, 200);
  assert.deepEqual(p.json.entries, entries);
  const bad = await request(port, { method: 'PUT', path: '/v1/dictionary', headers: auth(), body: JSON.stringify({ entries: [{ term: 1 }] }) });
  assert.equal(bad.status, 400);
  assert.equal(bad.json.error.code, 'bad_request');
  const disk = await request(port, { method: 'PUT', path: '/v1/dictionary', headers: auth(), body: JSON.stringify({ entries: [{ term: 'disk', spoken: ['x'] }] }) });
  assert.equal(disk.status, 500);
  assert.equal(disk.json.error.code, 'internal');
  assert.ok(!disk.text.includes('/secret/path'));
  const tooMany = await request(port, { method: 'PUT', path: '/v1/dictionary', headers: auth(), body: JSON.stringify({ entries: new Array(5001).fill({ term: 'a', spoken: ['a'] }) }) });
  assert.equal(tooMany.status, 400);
  const notJson = await request(port, { method: 'PUT', path: '/v1/dictionary', headers: auth(), body: '{' });
  assert.equal(notJson.json.error.code, 'bad_request');
  const c = await request(port, { method: 'POST', path: '/v1/corrections', headers: auth(), body: JSON.stringify({ before: 'đi plôi', after: 'deploy' }) });
  assert.equal(c.status, 200);
  assert.deepEqual(c.json, { suggestions: [{ term: 'deploy', spoken: ['đi plôi'] }] });
  const cBad = await request(port, { method: 'POST', path: '/v1/corrections', headers: auth(), body: JSON.stringify({ before: 1 }) });
  assert.equal(cBad.status, 400);
});
