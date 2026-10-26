// command.js: máy chủ HTTP THẬT dựng trong test (không mock fetch).
import test from 'node:test';
import assert from 'node:assert/strict';
import { createServer } from 'node:http';
import { mkdtempSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { randomBytes } from 'node:crypto';
import { runCommand, CommandError, MAX_FIELD_CHARS } from './command.js';

const CANARY = `vflow-canary-cmd-${randomBytes(8).toString('hex')}`;

const SCENARIOS = {
  edit_ok: (res) => reply(res, 200, { choices: [{ message: { content: 'Chào anh Nam, em gửi báo cáo tuần này.' } }] }),
  draft_ok: (res) => reply(res, 200, { choices: [{ message: { content: 'Xin chào,\n\nĐây là nội dung soạn mới.' } }] }),
  empty: (res) => reply(res, 200, { choices: [{ message: { content: '' } }] }),
  slow: (res) => setTimeout(() => reply(res, 200, { choices: [{ message: { content: 'muộn' } }] }), 3000),
  http500: (res) => reply(res, 500, { error: `lỗi key=${CANARY}` }),
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
      (SCENARIOS[json.model] ?? SCENARIOS.edit_ok)(res);
    });
  });
  await new Promise((r) => server.listen(0, '127.0.0.1', r));
  t.after(() => {
    server.closeAllConnections();
    server.close();
  });
  return { url: `http://127.0.0.1:${server.address().port}/v1`, requests };
}

function setup(t) {
  const dir = mkdtempSync(join(tmpdir(), 'vflow-post-command-'));
  t.after(() => rmSync(dir, { recursive: true, force: true }));
  const keyFile = join(dir, 'k');
  writeFileSync(keyFile, `${CANARY}\n`);
  return keyFile;
}

test('có selection ⇒ kind=edit, chỉ gửi đúng 1 phần đoạn thay thế', async (t) => {
  const srv = await startServer(t);
  const keyFile = setup(t);
  const r = await runCommand({
    instruction: 'sửa lại cho lịch sự hơn',
    selection: 'Nam ơi gửi báo cáo tuần này',
    rewrite: { url: srv.url, model: 'edit_ok', timeout_ms: 500, key_file: keyFile },
  });
  assert.equal(r.kind, 'edit');
  assert.equal(r.text, 'Chào anh Nam, em gửi báo cáo tuần này.');
  assert.ok(Number.isFinite(r.timings_ms.llm));
  assert.equal(srv.requests[0].json.messages.length, 2);
  assert.match(srv.requests[0].json.messages[0].content, /Chỉ trả về ĐÚNG/);
});

test('không có selection ⇒ kind=draft', async (t) => {
  const srv = await startServer(t);
  const keyFile = setup(t);
  const r = await runCommand({
    instruction: 'soạn một đoạn chào hỏi ngắn',
    selection: '',
    rewrite: { url: srv.url, model: 'draft_ok', timeout_ms: 500, key_file: keyFile },
  });
  assert.equal(r.kind, 'draft');
  assert.equal(r.text, 'Xin chào,\n\nĐây là nội dung soạn mới.');
});

test('selection chỉ có khoảng trắng ⇒ coi như không có, kind=draft', async (t) => {
  const srv = await startServer(t);
  const keyFile = setup(t);
  const r = await runCommand({
    instruction: 'soạn một đoạn chào hỏi ngắn',
    selection: '   \n  ',
    rewrite: { url: srv.url, model: 'draft_ok', timeout_ms: 500, key_file: keyFile },
  });
  assert.equal(r.kind, 'draft');
});

test('thiếu instruction ⇒ bad_request, không gọi mạng', async (t) => {
  const srv = await startServer(t);
  const keyFile = setup(t);
  await assert.rejects(
    () => runCommand({ instruction: '', selection: '', rewrite: { url: srv.url, model: 'edit_ok', timeout_ms: 500, key_file: keyFile } }),
    (err) => err instanceof CommandError && err.code === 'bad_request',
  );
  assert.equal(srv.requests.length, 0);
});

test('vượt quá 20.000 ký tự mỗi trường ⇒ bad_request, không gọi mạng', async (t) => {
  const srv = await startServer(t);
  const keyFile = setup(t);
  const huge = 'a'.repeat(MAX_FIELD_CHARS + 1);
  for (const fields of [{ instruction: huge, selection: '' }, { instruction: 'x', selection: huge }, { instruction: 'x', selection: '', context: huge }]) {
    await assert.rejects(
      () => runCommand({ ...fields, rewrite: { url: srv.url, model: 'edit_ok', timeout_ms: 500, key_file: keyFile } }),
      (err) => err instanceof CommandError && err.code === 'bad_request',
    );
  }
  assert.equal(srv.requests.length, 0);
});

test('cloud_llm=false ⇒ cloud_disabled, KHÔNG gọi mạng, KHÔNG trả văn bản giả', async (t) => {
  const srv = await startServer(t);
  const keyFile = setup(t);
  await assert.rejects(
    () =>
      runCommand({
        instruction: 'sửa lại',
        selection: 'abc',
        rewrite: { url: srv.url, model: 'edit_ok', timeout_ms: 500, key_file: keyFile },
        settings: { cloud_llm: false },
      }),
    (err) => err instanceof CommandError && err.code === 'cloud_disabled',
  );
  assert.equal(srv.requests.length, 0);
});

test('timeout ⇒ CommandError code=timeout, không trả văn bản giả', async (t) => {
  const srv = await startServer(t);
  const keyFile = setup(t);
  await assert.rejects(
    () => runCommand({ instruction: 'sửa lại', selection: 'abc', rewrite: { url: srv.url, model: 'slow', timeout_ms: 300, key_file: keyFile } }),
    (err) => err instanceof CommandError && err.code === 'timeout',
  );
});

test('lỗi mạng/rỗng/HTTP ⇒ rewrite_unavailable, khoá canh gác không lộ', async (t) => {
  const srv = await startServer(t);
  const keyFile = setup(t);
  for (const model of ['empty', 'http500']) {
    const err = await runCommand({ instruction: 'sửa lại', selection: 'abc', rewrite: { url: srv.url, model, timeout_ms: 500, key_file: keyFile } }).catch(
      (e) => e,
    );
    assert.ok(err instanceof CommandError, model);
    assert.equal(err.code, 'rewrite_unavailable', model);
    assert.ok(!err.message.includes(CANARY));
  }
});
