// Viết lại email qua máy chủ HTTP THẬT dựng trong test (không mock fetch).
import test from 'node:test';
import assert from 'node:assert/strict';
import { createServer } from 'node:http';
import { mkdtempSync, rmSync, writeFileSync, readFileSync, readdirSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { randomBytes } from 'node:crypto';
import { createPostProcessor } from './index.js';
import { loadConfig } from './config.js';

// Khoá canh gác: giá trị nhận diện được, sinh mới mỗi lần chạy, chỉ sống trong thư mục tạm.
const CANARY = `vflow-canary-${randomBytes(8).toString('hex')}`;

/** Kịch bản theo tên model trong yêu cầu. */
const SCENARIOS = {
  ok: (res) => reply(res, 200, { choices: [{ message: { role: 'assistant', content: '  Kính gửi anh,\n\nEm đã deploy xong.  ' } }] }),
  think: (res) => reply(res, 200, { choices: [{ message: { content: '<think>nghĩ…</think>Em đã deploy xong.' } }] }),
  slow: (res) => setTimeout(() => reply(res, 200, { choices: [{ message: { content: 'muộn' } }] }), 3000),
  slow_body: (res) => {
    res.writeHead(200, { 'content-type': 'application/json' });
    res.write('{"choices":[');
    setTimeout(() => res.end('{"message":{"content":"muộn"}}]}'), 3000);
  },
  http500: (res) => reply(res, 500, { error: { message: `upstream lỗi, key=${CANARY}` } }),
  http401: (res) => reply(res, 401, { error: { message: `invalid key ${CANARY}` } }),
  http429: (res) => reply(res, 429, { error: 'rate limit' }),
  empty_body: (res) => {
    res.writeHead(200, { 'content-type': 'application/json' });
    res.end();
  },
  empty_content: (res) => reply(res, 200, { choices: [{ message: { content: '   ' } }] }),
  null_content: (res) => reply(res, 200, { choices: [{ message: { content: null } }] }),
  think_only: (res) => reply(res, 200, { choices: [{ message: { content: '<think>chỉ nghĩ</think>' } }] }),
  garbage: (res) => {
    res.writeHead(200, { 'content-type': 'text/html' });
    res.end(`<html>bad gateway ${CANARY}</html>`);
  },
  no_choices: (res) => reply(res, 200, { object: 'chat.completion', choices: [] }),
  wrong_type: (res) => reply(res, 200, { choices: [{ message: { content: [{ type: 'text', text: 'x' }] } }] }),
  huge: (res) => reply(res, 200, { choices: [{ message: { content: 'a'.repeat(50000) } }] }),
  hangup: (res) => res.socket.destroy(),
};

function reply(res, status, body) {
  res.writeHead(status, { 'content-type': 'application/json' });
  res.end(JSON.stringify(body));
}

async function startServer(t) {
  const requests = [];
  const server = createServer((req, res) => {
    let body = '';
    req.setEncoding('utf8');
    req.on('data', (c) => (body += c));
    req.on('end', () => {
      const json = JSON.parse(body);
      requests.push({ method: req.method, url: req.url, headers: req.headers, json });
      (SCENARIOS[json.model] ?? SCENARIOS.garbage)(res);
    });
  });
  await new Promise((r) => server.listen(0, '127.0.0.1', r));
  t.after(() => {
    server.closeAllConnections();
    server.close();
  });
  return { url: `http://127.0.0.1:${server.address().port}/v1`, requests };
}

/** Bắt mọi thứ ghi ra stderr/stdout trong lúc chạy fn (log mặc định đi stderr). */
async function captureOutput(fn) {
  const chunks = [];
  const orig = { out: process.stdout.write, err: process.stderr.write };
  process.stdout.write = (c, ...a) => (chunks.push(String(c)), orig.out.call(process.stdout, c, ...a));
  process.stderr.write = (c, ...a) => (chunks.push(String(c)), orig.err.call(process.stderr, c, ...a));
  try {
    return { value: await fn(), output: () => chunks.join('') };
  } finally {
    process.stdout.write = orig.out;
    process.stderr.write = orig.err;
  }
}

function setup(t, url, { model = 'ok', timeout_ms = 500, withKey = true } = {}) {
  const dir = mkdtempSync(join(tmpdir(), 'vflow-post-rewrite-'));
  t.after(() => rmSync(dir, { recursive: true, force: true }));
  const keyFile = join(dir, 'rewrite.key');
  if (withKey) writeFileSync(keyFile, `${CANARY}\n`, { mode: 0o600 });
  const dictionaryPath = join(dir, 'dictionary.json');
  writeFileSync(dictionaryPath, JSON.stringify({ entries: [{ term: 'deploy', spoken: ['đi plôi'] }] }));
  const configPath = join(dir, 'config.json');
  writeFileSync(configPath, JSON.stringify({ rewrite: { url, model, timeout_ms, key_file: keyFile } }));
  const logs = [];
  const p = createPostProcessor({ dictionaryPath, config: loadConfig(configPath), log: (e) => logs.push(e) });
  return { p, logs, dir };
}

const RAW = 'ừm anh ơi em đã đi plôi xong bản 2.3 lên production';
const DICT_TEXT = 'ừm anh ơi em đã deploy xong bản 2.3 lên production';

test('email thành công: chỉ gửi văn bản đã qua từ điển, kèm system prompt tiếng Việt, khoá ở header', async (t) => {
  const srv = await startServer(t);
  const { p } = setup(t, srv.url);
  const r = await p.process({ textRaw: RAW, mode: 'email' });
  assert.deepEqual(r.rewrite, { used: true, error: null });
  assert.equal(r.text, 'Kính gửi anh,\n\nEm đã deploy xong.');
  assert.deepEqual(r.applied, [{ type: 'dictionary', from: 'đi plôi', to: 'deploy' }]);
  assert.equal(srv.requests.length, 1);
  const req = srv.requests[0];
  assert.equal(req.method, 'POST');
  assert.equal(req.url, '/v1/chat/completions');
  assert.equal(req.headers.authorization, `Bearer ${CANARY}`);
  assert.equal(req.json.messages.length, 2);
  assert.equal(req.json.messages[0].role, 'system');
  assert.match(req.json.messages[0].content, /GIỮ NGUYÊN/);
  assert.match(req.json.messages[0].content, /KHÔNG thêm thông tin/);
  assert.deepEqual(req.json.messages[1], { role: 'user', content: DICT_TEXT });
});

test('email bỏ khối <think> của model', async (t) => {
  const srv = await startServer(t);
  const { p } = setup(t, srv.url, { model: 'think' });
  assert.equal((await p.process({ textRaw: RAW, mode: 'email' })).text, 'Em đã deploy xong.');
});

const FAILURES = [
  ['slow', 'timeout'],
  ['slow_body', 'timeout'],
  ['http500', 'http_500'],
  ['http401', 'http_401'],
  ['http429', 'http_429'],
  ['empty_body', 'empty'],
  ['empty_content', 'empty'],
  ['null_content', 'empty'],
  ['think_only', 'empty'],
  ['garbage', 'bad_response'],
  ['no_choices', 'bad_response'],
  ['wrong_type', 'bad_response'],
  ['huge', 'bad_response'],
  ['hangup', 'network'],
];

for (const [model, code] of FAILURES) {
  test(`email lỗi "${model}" ⇒ text = văn bản đã qua từ điển, rewrite.error = ${code}`, async (t) => {
    const srv = await startServer(t);
    const { p, logs } = setup(t, srv.url, { model, timeout_ms: 400 });
    const started = Date.now();
    const r = await p.process({ textRaw: RAW, mode: 'email' });
    assert.equal(r.text, DICT_TEXT);
    assert.deepEqual(r.rewrite, { used: false, error: code });
    assert.deepEqual(logs, [{ event: 'rewrite_failed', code }]);
    if (code === 'timeout') assert.ok(Date.now() - started < 2000, 'timeout phải theo rewrite.timeout_ms');
  });
}

test('email: máy chủ không chạy ⇒ network', async (t) => {
  const srv = await startServer(t);
  const deadUrl = srv.url.replace(/:\d+\//, ':1/');
  const { p } = setup(t, deadUrl);
  const r = await p.process({ textRaw: RAW, mode: 'email' });
  assert.deepEqual([r.text, r.rewrite], [DICT_TEXT, { used: false, error: 'network' }]);
});

test('email: thiếu tệp khoá ⇒ no_key, không gọi mạng', async (t) => {
  const srv = await startServer(t);
  const { p } = setup(t, srv.url, { withKey: false });
  const r = await p.process({ textRaw: RAW, mode: 'email' });
  assert.deepEqual([r.text, r.rewrite], [DICT_TEXT, { used: false, error: 'no_key' }]);
  assert.equal(srv.requests.length, 0);
});

test('email: chưa đặt rewrite.model ⇒ no_model, không gọi mạng', async (t) => {
  const srv = await startServer(t);
  const { p } = setup(t, srv.url, { model: null });
  const r = await p.process({ textRaw: RAW, mode: 'email' });
  assert.deepEqual([r.text, r.rewrite], [DICT_TEXT, { used: false, error: 'no_model' }]);
  assert.equal(srv.requests.length, 0);
});

test('auto với ứng dụng thư ⇒ email', async (t) => {
  const srv = await startServer(t);
  const { p } = setup(t, srv.url);
  const r = await p.process({ textRaw: RAW, mode: 'auto', app: 'com.apple.mail' });
  assert.equal(r.mode, 'email');
  assert.equal(r.rewrite.used, true);
});

test('khoá canh gác KHÔNG xuất hiện trong kết quả, log, stdout/stderr hay tệp ghi ra ở mọi tình huống', async (t) => {
  const srv = await startServer(t);
  const seen = [];
  const cap = await captureOutput(async () => {
    for (const model of ['ok', ...FAILURES.map(([m]) => m)]) {
      // Log mặc định (stderr) để quét đúng đường log thật.
      const dir = mkdtempSync(join(tmpdir(), 'vflow-post-canary-'));
      try {
        const keyFile = join(dir, 'k');
        writeFileSync(keyFile, CANARY);
        const dictionaryPath = join(dir, 'dictionary.json');
        writeFileSync(dictionaryPath, JSON.stringify({ entries: [{ term: 'deploy', spoken: ['đi plôi'] }] }));
        const p = createPostProcessor({ dictionaryPath, config: { rewrite: { url: srv.url, model, timeout_ms: 300, key_file: keyFile } } });
        const r = await p.process({ textRaw: RAW, mode: 'email' });
        seen.push(JSON.stringify(r), JSON.stringify(p.dictionary.list()));
        seen.push(readFileSync(dictionaryPath, 'utf8'));
        for (const f of readdirSync(dir)) if (f !== 'k') seen.push(readFileSync(join(dir, f), 'utf8'));
      } finally {
        rmSync(dir, { recursive: true, force: true });
      }
    }
    // Lỗi cấu hình có khoá dán thẳng hoặc tệp cấu hình hỏng chứa khoá: thông báo không trích khoá.
    for (const bad of [{ rewrite: { api_key: CANARY } }, { rewrite: { key: CANARY } }, { rewrite: { url: CANARY } }]) {
      try {
        createPostProcessor({ dictionaryPath: join(tmpdir(), 'không-dùng.json'), config: bad });
        assert.fail('phải ném lỗi');
      } catch (err) {
        seen.push(String(err.message), String(err.stack));
      }
    }
    const dir = mkdtempSync(join(tmpdir(), 'vflow-post-canary-'));
    try {
      writeFileSync(join(dir, 'config.json'), `{"rewrite": {"key": "${CANARY}" `);
      assert.throws(() => loadConfig(join(dir, 'config.json')), (err) => (seen.push(err.message, err.stack), true));
    } finally {
      rmSync(dir, { recursive: true, force: true });
    }
  });
  const everything = seen.join('\n') + cap.output();
  assert.ok(seen.length > 30, 'đã thu đủ đầu ra');
  assert.ok(!everything.includes(CANARY), 'khoá bị lộ');
  // Đối chứng: máy chủ thật sự nhận khoá (chứng minh khoá được dùng, nên phép quét có ý nghĩa).
  assert.ok(srv.requests.some((r) => r.headers.authorization === `Bearer ${CANARY}`));
  // Log mặc định có chạy và chỉ chứa mã lỗi.
  assert.match(cap.output(), /"event":"rewrite_failed","code":"http_500"/);
  assert.ok(!cap.output().includes('deploy xong'), 'log chứa văn bản giọng nói');
});
