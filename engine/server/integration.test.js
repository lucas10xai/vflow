/**
 * Tích hợp thật (không phải fake của server.test.js): createPostProcessor (engine/post, E1a)
 * + createSnippetStore/createSettingsStore (engine/post, E1b) + createServer ghép như bin/vflow.js
 * làm thật ở `serve`. Kiểm bất biến 7 (snippet không qua từ điển/làm gọn) và bất biến 9
 * (cloud_llm=false ⇒ không có yêu cầu mạng) qua đường nối dây thật, không qua fake tự viết.
 * /v1/transcribe cần model/audio thật nên không kiểm expand qua đó; expand kiểm trực tiếp qua
 * post.process() thật (post wiring thật, không phải HTTP STT) như acceptance #2 yêu cầu.
 */
import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdtempSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { createPostProcessor } from '../post/index.js';
import { createSnippetStore } from '../post/snippets.js';
import { createSettingsStore } from '../post/settings.js';
import { createServer, listen } from './index.js';
import { ensureToken } from './token.js';
import { createStt } from '../stt/index.js';

function setup(t) {
  const home = mkdtempSync(join(tmpdir(), 'vflow-integration-'));
  t.after(() => rmSync(home, { recursive: true, force: true }));
  const snippets = createSnippetStore({ path: join(home, 'snippets.json') });
  const settings = createSettingsStore({ configPath: join(home, 'config.json') });
  let fetchCalls = 0;
  const fetchImpl = async () => { fetchCalls++; throw new Error('không được gọi mạng khi cloud_llm=false'); };
  const post = createPostProcessor({ dictionaryPath: join(home, 'dictionary.json'), snippets, settings, fetchImpl, log: () => {} });
  return { home, snippets, settings, post, getFetchCalls: () => fetchCalls };
}

async function request(port, token, { method = 'GET', path, body }) {
  const http = await import('node:http');
  return new Promise((resolve, reject) => {
    const req = http.request({ host: '127.0.0.1', port, method, path, headers: { host: `127.0.0.1:${port}`, authorization: `Bearer ${token}`, 'content-type': 'application/json' } }, (res) => {
      const chunks = [];
      res.on('data', (c) => chunks.push(c));
      res.on('end', () => {
        const text = Buffer.concat(chunks).toString('utf8');
        resolve({ status: res.statusCode, json: text ? JSON.parse(text) : null });
      });
    });
    req.on('error', reject);
    if (body !== undefined) req.write(body);
    req.end();
  });
}

test('tích hợp thật: PUT /v1/snippets rồi post.process() thật mở rộng cả câu và "chèn <trigger>" (bất biến 7: không qua từ điển/clean)', async (t) => {
  const { snippets, post } = setup(t);
  snippets.replaceAll([
    { trigger: 'link lịch hẹn', text: 'https://cal.example/demo' },
    { trigger: 'đi plôi xong chưa', text: 'KHÔNG được qua từ điển' }, // chứa cụm giống biến thể từ điển nhưng là snippet
  ]);
  const whole = await post.process({ textRaw: 'Link, lịch hẹn!', mode: 'clean' });
  assert.equal(whole.text, 'https://cal.example/demo');
  assert.deepEqual(whole.applied, [{ type: 'snippet', from: 'link lịch hẹn', to: 'snippet' }]);

  const insert = await post.process({ textRaw: 'anh gửi chèn link lịch hẹn cho em', mode: 'normal' });
  assert.equal(insert.text, 'anh gửi https://cal.example/demo cho em');

  // Bất biến 7: snippet trùng văn bản với một mẫu từ điển vẫn không bị "clean"/dictionary sửa.
  const guarded = await post.process({ textRaw: 'đi plôi xong chưa', mode: 'clean' });
  assert.equal(guarded.text, 'KHÔNG được qua từ điển');
});

/** STT giả trả đúng một câu cố định, dùng để kiểm /v1/transcribe qua HTTP với post thật. */
async function fakeSttFor(home, spoken) {
  const { createStt: createSttReal } = await import('../stt/index.js');
  return createSttReal({
    home: join(home, 'stt-home'),
    providerFactory: (id) => (id === 'fake' ? {
      loaded: false,
      async loadModel() { this.loaded = true; },
      async transcribe() { return { text: spoken, audio_ms: 1000, stt_ms: 1 }; },
    } : null),
    config: { default_model: 'fake' },
  });
}

/** Gửi một WAV giả (có năng lượng, không bị coi là im lặng) tới /v1/transcribe. */
async function transcribeOnce(port, token, qs) {
  const http = await import('node:http');
  const { encodeWav } = await import('../stt/audio.js');
  const wav = encodeWav(new Float32Array(16000).fill(0.2), 16000);
  return new Promise((resolve, reject) => {
    const req = http.request({ host: '127.0.0.1', port, method: 'POST', path: `/v1/transcribe?${qs}`, headers: { host: `127.0.0.1:${port}`, authorization: `Bearer ${token}`, 'content-type': 'audio/wav' } }, (r) => {
      const chunks = [];
      r.on('data', (c) => chunks.push(c));
      r.on('end', () => resolve({ status: r.statusCode, json: JSON.parse(Buffer.concat(chunks).toString('utf8')) }));
    });
    req.on('error', reject);
    req.write(wav);
    req.end();
  });
}

test('tích hợp thật qua HTTP: /v1/transcribe?mode=auto với app Terminal phải trả mode "dev" đã phân giải, không rơi lại "auto"', async (t) => {
  const { home, post, settings, snippets } = setup(t);
  const { token } = await ensureToken(join(home, 'token'));
  const server = createServer({ stt: await fakeSttFor(home, 'gạch dưới a b c'), post, token, snippets, settings, log: () => {} });
  const port = await listen(server, 0);
  t.after(async () => new Promise((r) => server.close(r)));
  const res = await transcribeOnce(port, token, 'mode=auto&app=com.apple.Terminal');
  assert.equal(res.status, 200, JSON.stringify(res));
  assert.equal(res.json.mode, 'dev', 'mode đã phân giải (dev) phải được trả, không phải "auto" ban đầu');
  assert.equal(res.json.text, '_a b c');
});

test('tích hợp thật qua HTTP: /v1/transcribe?mode=dev (trực tiếp, không qua auto) ⇒ 200, mode="dev", quy tắc đọc kiểu lập trình áp dụng', async (t) => {
  const { home, post, settings, snippets } = setup(t);
  const { token } = await ensureToken(join(home, 'token'));
  const server = createServer({ stt: await fakeSttFor(home, 'gạch dưới a b c'), post, token, snippets, settings, log: () => {} });
  const port = await listen(server, 0);
  t.after(async () => new Promise((r) => server.close(r)));
  const res = await transcribeOnce(port, token, 'mode=dev');
  assert.equal(res.status, 200, JSON.stringify(res));
  assert.equal(res.json.mode, 'dev');
  assert.equal(res.json.text, '_a b c');
});

test('tích hợp thật qua HTTP: /v1/transcribe?mode=tidy (trực tiếp, không qua auto), cloud_llm=false ⇒ 200, mode="tidy", rewrite.error=cloud_disabled, KHÔNG gọi mạng', async (t) => {
  const { home, post, settings, snippets, getFetchCalls } = setup(t);
  settings.update({ cloud_llm: false });
  const { token } = await ensureToken(join(home, 'token'));
  const server = createServer({ stt: await fakeSttFor(home, 'ừm chào anh'), post, token, snippets, settings, log: () => {} });
  const port = await listen(server, 0);
  t.after(async () => new Promise((r) => server.close(r)));
  const res = await transcribeOnce(port, token, 'mode=tidy');
  assert.equal(res.status, 200, JSON.stringify(res));
  assert.equal(res.json.mode, 'tidy');
  assert.equal(res.json.text, 'chào anh');
  assert.deepEqual(res.json.post.rewrite, { used: false, error: 'cloud_disabled' });
  assert.equal(getFetchCalls(), 0, 'bất biến 9: cloud_llm=false ⇒ không gọi mạng LLM, kể cả qua /v1/transcribe');
});

test('tích hợp thật: PUT /v1/settings cloud_llm=false ⇒ post.command() thật trả cloud_disabled, KHÔNG gọi fetch (bất biến 9)', async (t) => {
  const { settings, post, getFetchCalls } = setup(t);
  settings.update({ cloud_llm: false });
  await assert.rejects(
    post.command({ instruction: 'soạn email xin nghỉ', selection: '', context: '' }),
    (err) => err.code === 'cloud_disabled',
  );
  assert.equal(getFetchCalls(), 0, 'không được gọi mạng khi cloud_llm=false');
});

test('tích hợp thật qua HTTP: server ghép snippets+settings+post thật (như bin/vflow.js serve), GET/PUT đúng, /v1/command tôn trọng settings', async (t) => {
  const { home, settings, post, snippets } = setup(t);
  const { token } = await ensureToken(join(home, 'token'));
  const stt = createStt({ home: join(home, 'stt-home'), env: {} });
  const server = createServer({ stt, post, token, snippets, settings, log: () => {} });
  const port = await listen(server, 0);
  t.after(async () => new Promise((r) => server.close(r)));

  const put = await request(port, token, { method: 'PUT', path: '/v1/snippets', body: JSON.stringify({ entries: [{ trigger: 'chữ ký', text: 'Nguyễn Văn An' }] }) });
  assert.equal(put.status, 200, JSON.stringify(put));
  // post.process (cùng instance snippets) thấy ngay thay đổi vừa PUT qua HTTP.
  const r = await post.process({ textRaw: 'chữ ký', mode: 'normal' });
  assert.equal(r.text, 'Nguyễn Văn An');

  const offSettings = await request(port, token, { method: 'PUT', path: '/v1/settings', body: JSON.stringify({ cloud_llm: false }) });
  assert.equal(offSettings.status, 200);
  const cmd = await request(port, token, { method: 'POST', path: '/v1/command', body: JSON.stringify({ instruction: 'soạn thư' }) });
  assert.equal(cmd.status, 503);
  assert.equal(cmd.json.error.code, 'cloud_disabled');

  const getSettings = await request(port, token, { path: '/v1/settings' });
  assert.equal(getSettings.json.cloud_llm, false);
});
