// tidy.js: máy chủ HTTP THẬT dựng trong test (không mock fetch), kịch bản định sẵn theo model.
import test from 'node:test';
import assert from 'node:assert/strict';
import { createServer } from 'node:http';
import { mkdtempSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { randomBytes } from 'node:crypto';
import { tidyText, checkGuard, vietnameseNumberValues } from './tidy.js';

const CANARY = `vflow-canary-tidy-${randomBytes(8).toString('hex')}`;
const GUARD = { min_token_overlap: 0.85, min_length_ratio: 0.3, max_length_ratio: 1.4 };

const SCENARIOS = {
  ok: (res) => reply(res, 200, { choices: [{ message: { content: 'Em sẽ deploy bản 2.3 hôm nay.' } }] }),
  // SSE dù không yêu cầu stream (quan sát thật với 9Router).
  sse: (res) => {
    res.writeHead(200, { 'content-type': 'text/event-stream' });
    res.write('data: {"choices":[{"delta":{"content":"Em sẽ deploy "}}]}\n\n');
    res.write('data: {"choices":[{"delta":{"content":"bản 2.3 hôm nay."}}]}\n\n');
    res.write('data: [DONE]\n\n');
    res.end();
  },
  list: (res) => reply(res, 200, { choices: [{ message: { content: 'Có hai việc:\n1. Deploy\n2. Review' } }] }),
  hallucinate: (res) => reply(res, 200, { choices: [{ message: { content: 'Em sẽ deploy bản 9.9 vào thứ Ba cho sếp Nam.' } }] }),
  empty: (res) => reply(res, 200, { choices: [{ message: { content: '   ' } }] }),
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
      (SCENARIOS[json.model] ?? SCENARIOS.ok)(res);
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
  const dir = mkdtempSync(join(tmpdir(), 'vflow-post-tidy-'));
  t.after(() => rmSync(dir, { recursive: true, force: true }));
  const keyFile = join(dir, 'k');
  writeFileSync(keyFile, `${CANARY}\n`);
  return keyFile;
}

const RAW = 'em sẽ deploy bản 2.3 hôm nay';

test('tidy thành công qua JSON thường', async (t) => {
  const srv = await startServer(t);
  const keyFile = setup(t);
  const r = await tidyText({ text: RAW, rewrite: { url: srv.url, model: 'ok', timeout_ms: 500, key_file: keyFile }, guard: GUARD });
  assert.deepEqual(r, { text: 'Em sẽ deploy bản 2.3 hôm nay.', error: null });
});

test('tidy thành công qua SSE (9Router có thể trả luồng dù stream:false)', async (t) => {
  const srv = await startServer(t);
  const keyFile = setup(t);
  const r = await tidyText({ text: RAW, rewrite: { url: srv.url, model: 'sse', timeout_ms: 500, key_file: keyFile }, guard: GUARD });
  assert.deepEqual(r, { text: 'Em sẽ deploy bản 2.3 hôm nay.', error: null });
});

test('danh sách đánh số: dấu đánh số không bị tính vào tỉ lệ token lạ', async (t) => {
  const srv = await startServer(t);
  const keyFile = setup(t);
  const r = await tidyText({
    text: 'có hai việc một là deploy hai là review',
    rewrite: { url: srv.url, model: 'list', timeout_ms: 500, key_file: keyFile },
    guard: GUARD,
  });
  assert.deepEqual(r, { text: 'Có hai việc:\n1. Deploy\n2. Review', error: null });
});

test('guard_rejected: model thêm số/tên không có trong lời nói', async (t) => {
  const srv = await startServer(t);
  const keyFile = setup(t);
  const r = await tidyText({
    text: RAW,
    rewrite: { url: srv.url, model: 'hallucinate', timeout_ms: 500, key_file: keyFile },
    guard: GUARD,
  });
  assert.deepEqual(r, { text: null, error: 'guard_rejected' });
});

test('guard_rejected: phản hồi rỗng sau khi trim', async (t) => {
  const srv = await startServer(t);
  const keyFile = setup(t);
  const r = await tidyText({ text: RAW, rewrite: { url: srv.url, model: 'empty', timeout_ms: 500, key_file: keyFile }, guard: GUARD });
  assert.deepEqual(r, { text: null, error: 'empty' });
});

test('timeout: model quá chậm', async (t) => {
  const srv = await startServer(t);
  const keyFile = setup(t);
  const started = Date.now();
  const r = await tidyText({ text: RAW, rewrite: { url: srv.url, model: 'slow', timeout_ms: 300, key_file: keyFile }, guard: GUARD });
  assert.deepEqual(r, { text: null, error: 'timeout' });
  assert.ok(Date.now() - started < 2000);
});

test('tone: formal/casual thêm một dòng hướng dẫn phong cách vào system prompt, neutral không thêm gì', async (t) => {
  const srv = await startServer(t);
  const keyFile = setup(t);
  for (const tone of [undefined, 'neutral', 'formal', 'casual']) {
    await tidyText({
      text: RAW, rewrite: { url: srv.url, model: 'ok', timeout_ms: 500, key_file: keyFile },
      settings: tone ? { tone } : undefined, guard: GUARD,
    });
  }
  const systems = srv.requests.map((r) => r.json.messages[0].content);
  assert.equal(systems[0], systems[1], 'không truyền tone và tone="neutral" phải giống nhau (không thêm dòng)');
  assert.ok(systems[0].startsWith('Bạn làm gọn lại'), 'prompt gốc không đổi');
  assert.ok(!systems[0].includes('trang trọng') && !systems[0].includes('gần gũi'));
  assert.ok(systems[2].includes('trang trọng'), 'formal phải thêm dòng trang trọng');
  assert.ok(systems[3].includes('gần gũi'), 'casual phải thêm dòng gần gũi');
  // Phần còn lại của prompt (quy tắc KHÔNG được làm, bao gồm guard) không đổi theo tone.
  for (const s of systems) assert.ok(s.includes('KHÔNG đổi, dịch hay diễn giải'));
});

test('tone KHÔNG ảnh hưởng guard: đầu ra thêm nội dung vẫn bị guard_rejected dù đặt formal/casual', async (t) => {
  const srv = await startServer(t);
  const keyFile = setup(t);
  for (const tone of ['formal', 'casual']) {
    const r = await tidyText({
      text: RAW, rewrite: { url: srv.url, model: 'hallucinate', timeout_ms: 500, key_file: keyFile },
      settings: { tone }, guard: GUARD,
    });
    assert.deepEqual(r, { text: null, error: 'guard_rejected' }, tone);
  }
});

test('cloud_llm=false ⇒ cloud_disabled, không gọi mạng', async (t) => {
  const srv = await startServer(t);
  const keyFile = setup(t);
  const r = await tidyText({
    text: RAW,
    rewrite: { url: srv.url, model: 'ok', timeout_ms: 500, key_file: keyFile },
    settings: { cloud_llm: false },
    guard: GUARD,
  });
  assert.deepEqual(r, { text: null, error: 'cloud_disabled' });
  assert.equal(srv.requests.length, 0);
});

test('lỗi HTTP ⇒ http_<status>, khoá canh gác không lộ', async (t) => {
  const srv = await startServer(t);
  const keyFile = setup(t);
  const r = await tidyText({ text: RAW, rewrite: { url: srv.url, model: 'http500', timeout_ms: 500, key_file: keyFile }, guard: GUARD });
  assert.deepEqual(r, { text: null, error: 'http_500' });
  assert.ok(!JSON.stringify(r).includes(CANARY));
});

test('checkGuard: phá nhánh (c) — thuật ngữ Latin lạ bị từ chối dù tỉ lệ overlap cao', () => {
  const input = 'em sẽ họp với anh vào chiều nay';
  const output = 'Em sẽ họp với anh vào chiều nay deadline.'; // "deadline" không có trong input
  assert.equal(checkGuard(input, output, GUARD), false);
});

test('checkGuard: phá nhánh (d) — đầu ra quá ngắn so với đầu vào', () => {
  const input = 'em sẽ gửi báo cáo chi tiết cho anh vào chiều nay trước năm giờ';
  const output = 'Ok.';
  assert.equal(checkGuard(input, output, GUARD), false);
});

test('checkGuard: backtrack hợp lệ (bỏ phần nói nhầm) KHÔNG bị từ chối', () => {
  const input = 'em sẽ gửi báo cáo vào thứ sáu à nhầm thứ năm cho anh';
  const output = 'Em sẽ gửi báo cáo vào thứ Năm cho anh.';
  assert.equal(checkGuard(input, output, GUARD), true);
});

test('vietnameseNumberValues: số đếm, hàng chục, trăm, nghìn, thập phân tách bởi "chấm"', () => {
  assert.deepEqual([...vietnameseNumberValues('mười')].sort((a, b) => a - b), [10]);
  assert.ok(vietnameseNumberValues('hai mươi lăm').has(25));
  assert.ok(vietnameseNumberValues('ba mươi').has(30));
  assert.ok(vietnameseNumberValues('một trăm').has(100));
  assert.ok(vietnameseNumberValues('một trăm linh năm').has(105));
  assert.ok(vietnameseNumberValues('hai nghìn không trăm hai mươi sáu').has(2026));
  const hcb = vietnameseNumberValues('hai chấm ba');
  assert.ok(hcb.has(2) && hcb.has(3), '"chấm" không thuộc số nào ⇒ tách "hai"=2 và "ba"=3 riêng');
  assert.deepEqual([...vietnameseNumberValues('deploy production')], []);
});

test('checkGuard: cho phép LLM chuyển số-chữ hợp lệ sang số-số (hàng chục, trăm, thập phân)', () => {
  const CASES = [
    ['tôi có hai mươi lăm con gà', 'Tôi có 25 con gà.'],
    ['phiên bản hai chấm ba vừa ra mắt', 'Phiên bản 2.3 vừa ra mắt.'],
    ['deploy xong lúc ba mươi phút', 'Deploy xong lúc 30 phút.'],
    ['năm nay là hai nghìn không trăm hai mươi sáu', 'Năm nay là 2026.'],
  ];
  for (const [input, output] of CASES) assert.equal(checkGuard(input, output, GUARD), true, input);
});

test('checkGuard: vẫn chặn số KHÔNG có nguồn trong lời nói dù tỉ lệ overlap cao (cả khi gần một số-chữ có thật)', () => {
  const CASES = [
    ['tôi có hai mươi lăm con gà', 'Tôi có 26 con gà.'], // gần 25 nhưng không phải 25
    ['tôi có hai mươi lăm con gà', 'Tôi có 999 con gà.'],
    ['deploy bản mới hôm nay', 'Deploy bản 2.3 hôm nay.'], // input không nói số nào cả
    ['phiên bản ba', 'Phiên bản 30.'], // "ba"=3 có nguồn nhưng "30" (ba mươi) thì không
  ];
  for (const [input, output] of CASES) assert.equal(checkGuard(input, output, GUARD), false, input);
});
