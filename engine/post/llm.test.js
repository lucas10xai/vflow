// Client LLM dùng chung: máy chủ HTTP THẬT dựng trong test (không mock fetch).
import test from 'node:test';
import assert from 'node:assert/strict';
import { createServer } from 'node:http';
import { mkdtempSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { randomBytes } from 'node:crypto';
import { callLlm } from './llm.js';

const CANARY = `vflow-canary-llm-${randomBytes(8).toString('hex')}`;

const SCENARIOS = {
  json_ok: (res) => reply(res, 200, { choices: [{ message: { content: 'xin chào' } }] }),
  sse_ok: (res) => {
    res.writeHead(200, { 'content-type': 'text/event-stream' });
    res.write('data: {"choices":[{"delta":{"content":"xin "}}]}\n\n');
    res.write('data: {"choices":[{"delta":{"content":"chào"}}]}\n\n');
    res.write('data: [DONE]\n\n');
    res.end();
  },
  sse_with_role_chunk: (res) => {
    res.writeHead(200, { 'content-type': 'text/event-stream' });
    res.write('data: {"choices":[{"delta":{"role":"assistant"}}]}\n\n');
    res.write('data: {"choices":[{"delta":{"content":"ok"}}]}\n\n');
    res.write('data: [DONE]\n\n');
    res.end();
  },
  sse_garbage: (res) => {
    res.writeHead(200, { 'content-type': 'text/event-stream' });
    res.write('data: {bad json\n\n');
    res.end();
  },
  empty_body: (res) => {
    res.writeHead(200, { 'content-type': 'application/json' });
    res.end();
  },
  garbage: (res) => {
    res.writeHead(200, { 'content-type': 'text/html' });
    res.end(`<html>bad gateway ${CANARY}</html>`);
  },
  http500: (res) => reply(res, 500, { error: `lỗi, key=${CANARY}` }),
  slow: (res) => setTimeout(() => reply(res, 200, { choices: [{ message: { content: 'muộn' } }] }), 3000),
  huge: (res) => reply(res, 200, { choices: [{ message: { content: 'a'.repeat(5000) } }] }),
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
      requests.push({ headers: req.headers, json });
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

function setup(t, { withKey = true } = {}) {
  const dir = mkdtempSync(join(tmpdir(), 'vflow-post-llm-'));
  t.after(() => rmSync(dir, { recursive: true, force: true }));
  const keyFile = join(dir, 'k');
  if (withKey) writeFileSync(keyFile, `${CANARY}\n`, { mode: 0o600 });
  return keyFile;
}

const MSGS = [{ role: 'user', content: 'nội dung thử' }];

test('JSON thường: đọc được choices[0].message.content', async (t) => {
  const srv = await startServer(t);
  const keyFile = setup(t);
  const r = await callLlm({ messages: MSGS, rewrite: { url: srv.url, model: 'json_ok', timeout_ms: 500, key_file: keyFile } });
  assert.deepEqual(r, { text: 'xin chào', error: null });
  assert.equal(srv.requests[0].json.stream, false);
});

test('SSE: ghép các dòng data: choices[0].delta.content, bỏ [DONE]', async (t) => {
  const srv = await startServer(t);
  const keyFile = setup(t);
  const r = await callLlm({ messages: MSGS, rewrite: { url: srv.url, model: 'sse_ok', timeout_ms: 500, key_file: keyFile } });
  assert.deepEqual(r, { text: 'xin chào', error: null });
});

test('SSE: khúc chỉ có role (không content) vẫn được bỏ qua, không lỗi', async (t) => {
  const srv = await startServer(t);
  const keyFile = setup(t);
  const r = await callLlm({ messages: MSGS, rewrite: { url: srv.url, model: 'sse_with_role_chunk', timeout_ms: 500, key_file: keyFile } });
  assert.deepEqual(r, { text: 'ok', error: null });
});

test('SSE hỏng (JSON lỗi trong khúc data:) ⇒ bad_response', async (t) => {
  const srv = await startServer(t);
  const keyFile = setup(t);
  const r = await callLlm({ messages: MSGS, rewrite: { url: srv.url, model: 'sse_garbage', timeout_ms: 500, key_file: keyFile } });
  assert.deepEqual(r, { text: null, error: 'bad_response' });
});

const FAILURES = [
  ['empty_body', 'empty'],
  ['garbage', 'bad_response'],
  ['http500', 'http_500'],
  ['hangup', 'network'],
];
for (const [model, code] of FAILURES) {
  test(`lỗi "${model}" ⇒ ${code}`, async (t) => {
    const srv = await startServer(t);
    const keyFile = setup(t);
    const r = await callLlm({ messages: MSGS, rewrite: { url: srv.url, model, timeout_ms: 400, key_file: keyFile } });
    assert.deepEqual(r, { text: null, error: code });
  });
}

test('timeout: dùng settings.llm_timeout_ms ưu tiên hơn rewrite.timeout_ms', async (t) => {
  const srv = await startServer(t);
  const keyFile = setup(t);
  const started = Date.now();
  const r = await callLlm({
    messages: MSGS,
    rewrite: { url: srv.url, model: 'slow', timeout_ms: 8000, key_file: keyFile },
    settings: { llm_timeout_ms: 300 },
  });
  assert.deepEqual(r, { text: null, error: 'timeout' });
  assert.ok(Date.now() - started < 2000, 'phải dùng ngưỡng từ settings, không phải rewrite.timeout_ms');
});

test('maxOutputChars: phản hồi quá dài so với giới hạn ⇒ bad_response', async (t) => {
  const srv = await startServer(t);
  const keyFile = setup(t);
  const r = await callLlm({
    messages: MSGS,
    rewrite: { url: srv.url, model: 'huge', timeout_ms: 500, key_file: keyFile },
    maxOutputChars: 100,
  });
  assert.deepEqual(r, { text: null, error: 'bad_response' });
});

test('cloud_llm=false ⇒ cloud_disabled, KHÔNG gọi mạng', async (t) => {
  const srv = await startServer(t);
  const keyFile = setup(t);
  const r = await callLlm({
    messages: MSGS,
    rewrite: { url: srv.url, model: 'json_ok', timeout_ms: 500, key_file: keyFile },
    settings: { cloud_llm: false },
  });
  assert.deepEqual(r, { text: null, error: 'cloud_disabled' });
  assert.equal(srv.requests.length, 0);
});

test('maxTokens: chỉ gửi max_tokens khi được truyền, không có mặc định ép buộc', async (t) => {
  const srv = await startServer(t);
  const keyFile = setup(t);
  await callLlm({ messages: MSGS, rewrite: { url: srv.url, model: 'json_ok', timeout_ms: 500, key_file: keyFile } });
  assert.equal('max_tokens' in srv.requests[0].json, false);
  await callLlm({ messages: MSGS, rewrite: { url: srv.url, model: 'json_ok', timeout_ms: 500, key_file: keyFile }, maxTokens: 123 });
  assert.equal(srv.requests[1].json.max_tokens, 123);
});

test('settings.llm_model ưu tiên hơn rewrite.model', async (t) => {
  const srv = await startServer(t);
  const keyFile = setup(t);
  const r = await callLlm({
    messages: MSGS,
    rewrite: { url: srv.url, model: 'garbage', timeout_ms: 500, key_file: keyFile },
    settings: { llm_model: 'json_ok' },
  });
  assert.deepEqual(r, { text: 'xin chào', error: null });
  assert.equal(srv.requests[0].json.model, 'json_ok');
});

test('chưa đặt model (rewrite.model=null, không có settings.llm_model) ⇒ no_model, không gọi mạng', async (t) => {
  const srv = await startServer(t);
  const keyFile = setup(t);
  const r = await callLlm({ messages: MSGS, rewrite: { url: srv.url, model: null, timeout_ms: 500, key_file: keyFile } });
  assert.deepEqual(r, { text: null, error: 'no_model' });
  assert.equal(srv.requests.length, 0);
});

test('thiếu tệp khoá ⇒ no_key, không gọi mạng', async (t) => {
  const srv = await startServer(t);
  const keyFile = setup(t, { withKey: false });
  const r = await callLlm({ messages: MSGS, rewrite: { url: srv.url, model: 'json_ok', timeout_ms: 500, key_file: keyFile } });
  assert.deepEqual(r, { text: null, error: 'no_key' });
  assert.equal(srv.requests.length, 0);
});

test('khoá canh gác KHÔNG xuất hiện trong kết quả ở mọi tình huống lỗi', async (t) => {
  const srv = await startServer(t);
  const keyFile = setup(t);
  const seen = [];
  for (const model of ['json_ok', 'sse_ok', ...FAILURES.map(([m]) => m)]) {
    const r = await callLlm({ messages: MSGS, rewrite: { url: srv.url, model, timeout_ms: 400, key_file: keyFile } });
    seen.push(JSON.stringify(r));
  }
  assert.ok(!seen.join('\n').includes(CANARY));
  assert.ok(srv.requests.some((r) => r.headers.authorization === `Bearer ${CANARY}`), 'đối chứng: khoá có được gửi thật');
});
