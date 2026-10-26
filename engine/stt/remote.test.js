import { test } from 'node:test';
import assert from 'node:assert/strict';
import { createRemoteProvider } from './remote.js';

const TOKEN = 'remote-secret-token-123';

/** fetch giả: ghi lại yêu cầu, trả phản hồi theo hàm `reply`. */
function fakeFetch(reply) {
  const calls = [];
  const f = async (url, init = {}) => {
    calls.push({ url, init });
    return reply(url, init);
  };
  return { calls, f };
}

const json = (status, body) => new Response(JSON.stringify(body), { status, headers: { 'content-type': 'application/json' } });

test('không có token ⇒ model_unavailable/missing_token, không gửi yêu cầu nào', async () => {
  const { calls, f } = fakeFetch(() => json(200, {}));
  const p = createRemoteProvider({ id: 'phowhisper-large', url: 'http://127.0.0.1:7612', token: null, fetchImpl: f });
  await assert.rejects(p.loadModel(), { code: 'model_unavailable', reason: 'missing_token' });
  await assert.rejects(p.transcribe({ pcm: new Float32Array(16000), sampleRate: 16000 }), { reason: 'missing_token' });
  assert.equal(calls.length, 0);
});

test('tunnel chưa mở ⇒ model_unavailable/tunnel_down; healthz chưa sẵn sàng ⇒ lý do từ máy chủ', async () => {
  const down = createRemoteProvider({ id: 'pw', url: 'http://127.0.0.1:1', token: TOKEN, fetchImpl: async () => { throw new TypeError('fetch failed'); } });
  await assert.rejects(down.loadModel('pw'), { code: 'model_unavailable', reason: 'tunnel_down' });
  const { f } = fakeFetch(() => json(200, { ok: false, reason: 'loading' }));
  const loading = createRemoteProvider({ id: 'pw', url: 'http://x', token: TOKEN, fetchImpl: f });
  await assert.rejects(loading.loadModel('pw'), { reason: 'loading' });
  assert.equal(loading.loaded, false);
});

test('transcribe: gửi L16 16 kHz mono (đã lấy mẫu lại), Bearer token; nhận text', async () => {
  const { calls, f } = fakeFetch(() => json(200, { text: '  xin   chào ', audio_ms: 1000, stt_ms: 50, model: 'phowhisper-large' }));
  const p = createRemoteProvider({ id: 'pw', url: 'http://127.0.0.1:7612/', token: TOKEN, fetchImpl: f });
  const r = await p.transcribe({ pcm: new Int16Array(44100), sampleRate: 44100 });
  assert.equal(r.text, 'xin chào');
  assert.equal(r.audio_ms, 1000);
  const { url, init } = calls[0];
  assert.equal(url, 'http://127.0.0.1:7612/v1/transcribe?lang=vi');
  assert.equal(init.method, 'POST');
  assert.equal(init.headers.authorization, `Bearer ${TOKEN}`);
  assert.equal(init.headers['content-type'], 'audio/L16; rate=16000; channels=1');
  assert.equal(init.body.byteLength, 16000 * 2);
});

test('lỗi từ xa: unauthorized ⇒ model_unavailable (không thành 401 cho client), bad_audio/timeout giữ mã, phản hồi hỏng ⇒ internal; token không lộ trong lỗi', async () => {
  const cases = [
    [json(401, { error: { code: 'unauthorized', message: 'sai token' } }), { code: 'model_unavailable', reason: 'remote_unauthorized' }],
    [json(400, { error: { code: 'bad_audio', message: 'hỏng' } }), { code: 'bad_audio' }],
    [json(504, { error: { code: 'timeout', message: 'lâu' } }), { code: 'timeout' }],
    [json(500, { error: { code: 'internal', message: 'x' } }), { code: 'internal' }],
    [json(200, { nope: true }), { code: 'internal' }],
    [new Response('<html>', { status: 502 }), { code: 'internal' }],
  ];
  for (const [res, expected] of cases) {
    const p = createRemoteProvider({ id: 'pw', url: 'http://x', token: TOKEN, fetchImpl: async () => res });
    const err = await p.transcribe({ pcm: new Float32Array(1600), sampleRate: 16000 }).then(() => null, (e) => e);
    assert.ok(err, 'phải lỗi');
    for (const [k, v] of Object.entries(expected)) assert.equal(err[k], v);
    assert.ok(!String(err.message).includes(TOKEN));
  }
});

test('quá thời gian ⇒ timeout', async () => {
  const slow = (url, init) => new Promise((_, reject) => {
    init.signal.addEventListener('abort', () => reject(init.signal.reason));
  });
  const p = createRemoteProvider({ id: 'pw', url: 'http://x', token: TOKEN, fetchImpl: slow, timeoutMs: 50 });
  // AbortSignal.timeout không giữ event loop; giữ tạm như một server đang chạy.
  const keepAlive = setTimeout(() => {}, 5000);
  try {
    await assert.rejects(p.transcribe({ pcm: new Float32Array(1600), sampleRate: 16000 }), { code: 'timeout' });
  } finally {
    clearTimeout(keepAlive);
  }
});
