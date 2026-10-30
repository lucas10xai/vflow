// Chế độ translate qua pipeline thật của createPostProcessor (post/index.js), LLM giả qua máy chủ
// HTTP THẬT dựng trong test (giống rewrite.test.js) — không mock fetch.
import test from 'node:test';
import assert from 'node:assert/strict';
import { createServer } from 'node:http';
import { mkdtempSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { createPostProcessor } from './index.js';

/** Kịch bản theo tên model trong yêu cầu (chọn qua settings.llm_model/cfg.rewrite.model). */
const SCENARIOS = {
  ok: (res) => reply(res, 200, { choices: [{ message: { content: 'Hello my friend today' } }] }),
  lead_in: (res) => reply(res, 200, { choices: [{ message: { content: "Here's the translation: Hello" } }] }),
  vi_passthrough: (res) => reply(res, 200, { choices: [{ message: { content: 'Xin chào bạn hôm nay' } }] }),
  too_short: (res) => reply(res, 200, { choices: [{ message: { content: 'Hi' } }] }),
  too_long: (res) => reply(res, 200, { choices: [{ message: { content: 'Hello '.repeat(40) } }] }),
  slow: (res) => setTimeout(() => reply(res, 200, { choices: [{ message: { content: 'muộn' } }] }), 2000),
  http500: (res) => reply(res, 500, { error: 'lỗi' }),
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
      requests.push({ json });
      (SCENARIOS[json.model] ?? SCENARIOS.ok)(res);
    });
  });
  await new Promise((r) => server.listen(0, '127.0.0.1', r));
  t.after(() => { server.closeAllConnections(); server.close(); });
  return { url: `http://127.0.0.1:${server.address().port}/v1`, requests };
}

/** @param {{url:string}} srv @param {{model?:string, timeout_ms?:number, cloudLlm?:boolean, target?:string, formality?:string}} [o] */
function setup(t, srv, o = {}) {
  const dir = mkdtempSync(join(tmpdir(), 'vflow-post-translate-'));
  t.after(() => rmSync(dir, { recursive: true, force: true }));
  const keyFile = join(dir, 'rewrite.key');
  writeFileSync(keyFile, 'khoa-gia-khong-phai-bi-mat\n', { mode: 0o600 });
  const dictionaryPath = join(dir, 'dictionary.json');
  writeFileSync(dictionaryPath, JSON.stringify({ entries: [{ term: 'deploy', spoken: ['đi plôi'] }] }));
  const settings = { get: () => ({ cloud_llm: o.cloudLlm ?? true, translate_target: o.target ?? 'en', translate_formality: o.formality ?? 'neutral' }) };
  const config = { rewrite: { url: srv.url, model: o.model ?? 'ok', timeout_ms: o.timeout_ms ?? 500, key_file: keyFile } };
  const p = createPostProcessor({ dictionaryPath, config, settings, log: () => {} });
  return { p, dictionaryPath };
}

test('process mode=translate thành công: qua từ điển trước, chỉ gửi văn bản, system prompt nêu đích/giọng điệu', async (t) => {
  const srv = await startServer(t);
  const { p } = setup(t, srv, { target: 'en', formality: 'formal' });
  const r = await p.process({ textRaw: 'anh đi plôi xong rồi', mode: 'translate' });
  assert.equal(r.text, 'Hello my friend today');
  assert.equal(r.mode, 'translate');
  assert.deepEqual(r.rewrite, { used: true, error: null });
  assert.equal(r.degraded, false);
  assert.equal(r.degraded_reason, null);
  assert.deepEqual(r.applied.filter((a) => a.type === 'dictionary'), [{ type: 'dictionary', from: 'đi plôi', to: 'deploy' }]);
  const sent = srv.requests.at(-1).json;
  assert.equal(sent.messages[1].content, 'anh deploy xong rồi');
  assert.match(sent.messages[0].content, /\ben\b/);
  assert.match(sent.messages[0].content, /formal/);
});

test('guard dịch chặn lời dẫn/nguyên văn tiếng Việt/độ dài bất thường ⇒ text rỗng (KHÔNG chèn nguyên văn), degraded_reason=translate_guard', async (t) => {
  const srv = await startServer(t);
  for (const model of ['lead_in', 'vi_passthrough', 'too_short', 'too_long']) {
    const { p } = setup(t, srv, { model });
    const r = await p.process({ textRaw: 'xin chào bạn hôm nay', mode: 'translate' });
    assert.equal(r.text, '', model);
    assert.deepEqual(r.rewrite, { used: false, error: 'translate_guard' }, model);
    assert.equal(r.degraded, true, model);
    assert.equal(r.degraded_reason, 'translate_guard', model);
  }
});

test('cloud_llm=false ⇒ KHÔNG gọi mạng, text rỗng, degraded_reason=cloud_disabled', async (t) => {
  const srv = await startServer(t);
  const { p } = setup(t, srv, { cloudLlm: false });
  const r = await p.process({ textRaw: 'xin chào', mode: 'translate' });
  assert.deepEqual(r.rewrite, { used: false, error: 'cloud_disabled' });
  assert.equal(r.text, '');
  assert.equal(r.degraded_reason, 'cloud_disabled');
  assert.equal(srv.requests.length, 0);
});

test('quá thời gian/lỗi HTTP ⇒ degraded_reason tương ứng, không trả nguyên văn', async (t) => {
  const srv = await startServer(t);
  const timeoutCase = setup(t, srv, { model: 'slow', timeout_ms: 300 });
  const r1 = await timeoutCase.p.process({ textRaw: 'xin chào', mode: 'translate' });
  assert.deepEqual(r1.rewrite, { used: false, error: 'timeout' });
  assert.equal(r1.text, '');
  assert.equal(r1.degraded_reason, 'llm_timeout');

  const errCase = setup(t, srv, { model: 'http500' });
  const r2 = await errCase.p.process({ textRaw: 'xin chào', mode: 'translate' });
  assert.deepEqual(r2.rewrite, { used: false, error: 'http_500' });
  assert.equal(r2.text, '');
  assert.equal(r2.degraded_reason, 'llm_error');
});

test('post.translate() (dùng bởi POST /v1/translate): thành công trả {text,error:null}; guard trả {text:null,error:"translate_guard"}', async (t) => {
  const srv = await startServer(t);
  const { p: ok } = setup(t, srv, { model: 'ok' });
  assert.deepEqual(await ok.translate({ text: 'xin chào bạn', target: 'en', formality: 'neutral' }), { text: 'Hello my friend today', error: null });
  const { p: guarded } = setup(t, srv, { model: 'vi_passthrough' });
  assert.deepEqual(await guarded.translate({ text: 'xin chào bạn', target: 'en', formality: 'neutral' }), { text: null, error: 'translate_guard' });
  const { p: disabled } = setup(t, srv, { cloudLlm: false });
  assert.deepEqual(await disabled.translate({ text: 'xin chào bạn', target: 'en', formality: 'neutral' }), { text: null, error: 'cloud_disabled' });
});

test('auto KHÔNG BAO GIỜ tự chọn translate, dù app được ánh xạ tới app_rules/auto.apps lạ hoặc không có luật', async (t) => {
  const srv = await startServer(t);
  const dir = mkdtempSync(join(tmpdir(), 'vflow-post-translate-auto-'));
  t.after(() => rmSync(dir, { recursive: true, force: true }));
  const dictionaryPath = join(dir, 'dictionary.json');
  writeFileSync(dictionaryPath, JSON.stringify({ entries: [] }));
  const keyFile = join(dir, 'rewrite.key');
  writeFileSync(keyFile, 'khoa\n', { mode: 0o600 });
  // auto.apps không thể nhận giá trị "translate": kiểm ở validateConfig (config.js, AUTO_TARGET_MODES).
  assert.throws(
    () => createPostProcessor({
      dictionaryPath,
      config: { rewrite: { url: srv.url, model: 'ok', timeout_ms: 500, key_file: keyFile }, auto: { apps: { 'com.exemplo.app': 'translate' } } },
    }),
    { code: 'bad_config' },
  );
  // app không có luật nào ⇒ rơi về "normal" (mặc định an toàn), không phải "translate".
  const p = createPostProcessor({ dictionaryPath, config: { rewrite: { url: srv.url, model: 'ok', timeout_ms: 500, key_file: keyFile } }, log: () => {} });
  const r = await p.process({ textRaw: 'xin chào', mode: 'auto', app: 'com.khong.ai.biet' });
  assert.notEqual(r.mode, 'translate');
  assert.equal(r.mode, 'normal');
  assert.equal(srv.requests.length, 0);
});
