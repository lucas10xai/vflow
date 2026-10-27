import { test } from 'node:test';
import assert from 'node:assert/strict';
import { applyContextSymbols, isAllowedApp } from './contextsymbols.js';

const TERM = 'com.apple.Terminal';
const SLACK = 'com.tinyspeck.slackmacgap';
const out = (text, app) => applyContextSymbols(text, { app }).text;

test('ngoài danh sách app (Notes, không có app, bundle id sai hoa/thường) lời nói thường GIỮ NGUYÊN', () => {
  for (const app of ['com.apple.Notes', undefined, '', 'com.apple.terminal', 'com.apple.Terminal2']) {
    const r = applyContextSymbols('a gạch dưới b gạch chéo c a còng nam', { app });
    assert.equal(r.text, 'a gạch dưới b gạch chéo c a còng nam', `app=${String(app)}`);
    assert.deepEqual(r.applied, []);
  }
  assert.equal(isAllowedApp('com.jetbrains.intellij'), true); // họ JetBrains theo tiền tố
  assert.equal(isAllowedApp('com.jetbrainsx.foo'), false);
});

test('terminal: gạch dưới / gạch chéo / dấu bằng / dấu thăng / dấu đô la', () => {
  assert.equal(out('mở file a gạch dưới b', TERM), 'mở file a_b');
  assert.equal(out('a dấu bằng b dấu cộng c', TERM), 'a=b+c');
  assert.equal(out('dấu thăng include', TERM), '#include');
  assert.equal(out('dấu đô la home', TERM), '$home');
  assert.equal(out('gạch chéo ngược', TERM), '\\');
  assert.equal(out('hai chấm hai gạch chéo', TERM), '://');
});

test('URL: "https hai chấm hai gạch chéo example" ⇒ https://example (không để lại "hai")', () => {
  assert.equal(out('truy cập https hai chấm hai gạch chéo example', TERM), 'truy cập https://example');
});

test('cờ dòng lệnh: "gạch nối gạch nối help" giữ khoảng trắng trước, dính vào từ sau; "gạch nối" đơn dính hai phía', () => {
  assert.equal(out('git gạch nối gạch nối help', TERM), 'git --help');
  assert.equal(out('tên gạch nối lửa', TERM), 'tên-lửa');
});

test('mention: terminal/IDE dính liền (email), chat nhóm GIỮ khoảng trắng trước "@"', () => {
  assert.equal(out('nam a còng gmail', TERM), 'nam@gmail');
  assert.equal(out('chào a còng nam', SLACK), 'chào @nam');
  assert.equal(out('chào a còng nam', 'com.microsoft.teams2'), 'chào @nam');
});

test('"a còng" đứng cuối câu (không có tên đi kèm) ⇒ "@" trần, không nuốt từ ngoài ý muốn', () => {
  assert.equal(out('a còng', TERM), '@');
  // dấu ngắt mệnh đề giữa hai từ ⇒ KHÔNG coi từ sau là tên
  assert.equal(out('a còng, nam', TERM), '@, nam');
});

test('lệnh slash "gạch chéo deploy" CHỈ ở đầu câu trong Slack/Discord, gắn dấu cách để gõ tiếp', () => {
  assert.equal(out('gạch chéo deploy staging', SLACK), '/deploy staging');
  assert.equal(out('gạch chéo deploy staging', 'com.hnc.Discord'), '/deploy staging');
  // giữa câu thì chỉ là ký hiệu gạch chéo thường
  assert.equal(out('chạy gạch chéo deploy', SLACK), 'chạy/deploy');
});

test('KHÔNG dư dấu cách ở cuối/trước dấu câu; chỉ có 1 dấu cách sau @tên và /lệnh khi CÒN chữ phía sau (đầu/giữa/cuối/trước dấu câu)', () => {
  const trimmedEnd = (s) => s === s.trimEnd();
  const cases = [
    // [app, vào, ra]
    [TERM, 'a còng example', '@example'], // đầu câu + cuối câu
    [TERM, 'gửi an a còng example', 'gửi an@example'], // cuối câu (ca báo lỗi: "an@example ")
    [TERM, 'a còng example rồi chạy', '@example rồi chạy'], // đầu câu, còn chữ phía sau
    [TERM, 'gửi an a còng example rồi chạy', 'gửi an@example rồi chạy'], // giữa câu
    [TERM, 'gửi an a còng example, rồi', 'gửi an@example, rồi'], // trước dấu câu
    [TERM, 'a còng example   ', '@example'], // chỉ còn khoảng trắng
    [TERM, 'a còng example\nxong', '@example\nxong'], // trước xuống dòng
    [TERM, 'a còng 123 xong', '@123 xong'], // tên là số
    [SLACK, 'chào a còng nam', 'chào @nam'],
    [SLACK, 'chào a còng nam rồi', 'chào @nam rồi'],
    [SLACK, 'chào a còng nam, họp nhé', 'chào @nam, họp nhé'],
    [SLACK, 'gạch chéo deploy', '/deploy'], // lệnh slash cuối câu
    [SLACK, 'gạch chéo deploy staging', '/deploy staging'],
    [SLACK, 'gạch chéo deploy, rồi', '/deploy, rồi'],
    [TERM, 'git gạch nối gạch nối', 'git --'], // cờ cuối câu
    [TERM, 'git gạch nối gạch nối help', 'git --help'],
    [TERM, 'mở a gạch dưới', 'mở a_'], // ký hiệu dính cuối câu
    [TERM, 'a dấu bằng', 'a='],
    [TERM, 'gạch chéo', '/'],
  ];
  for (const [app, input, want] of cases) {
    const got = out(input, app);
    assert.equal(got, want, `${app} ⇐ ${JSON.stringify(input)}`);
    assert.ok(trimmedEnd(got), `dư khoảng trắng cuối: ${JSON.stringify(got)}`);
  }
});

test('applied ghi đúng cặp from/to cho từng ký hiệu', () => {
  const r = applyContextSymbols('a dấu bằng b', { app: TERM });
  assert.deepEqual(r.applied, [{ type: 'context_symbol', from: 'dấu bằng', to: '=' }]);
});

test('không đổi từ tiếng Việt thường chứa từ khoá một phần', () => {
  // "dấu" đứng riêng, "gạch" đứng riêng, "còng" đứng riêng: KHÔNG thành ký hiệu
  assert.equal(out('dấu hiệu gạch men còng tay', TERM), 'dấu hiệu gạch men còng tay');
});

// --- Ghép vào hậu xử lý thật (engine/post/index.js) ---
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { createPostProcessor } from './index.js';
import { createSettingsStore } from './settings.js';
import { createSnippetStore } from './snippets.js';

function makePost() {
  const home = fs.mkdtempSync(path.join(os.tmpdir(), 'vflow-cs-'));
  fs.writeFileSync(path.join(home, 'dictionary.json'), JSON.stringify({ entries: [] }));
  const settings = createSettingsStore({ configPath: path.join(home, 'config.json') });
  const snippets = createSnippetStore({ path: path.join(home, 'snippets.json') });
  const post = createPostProcessor({ dictionaryPath: path.join(home, 'dictionary.json'), snippets, settings, log: () => {} });
  return { home, settings, post };
}

test('hậu xử lý: Terminal ở auto ⇒ dev VẪN áp ký hiệu (URL, cờ), Notes thì không; context_symbols=false tắt hẳn', async () => {
  const { home, settings, post } = makePost();
  try {
    const url = await post.process({ textRaw: 'truy cập https hai chấm hai gạch chéo example', mode: 'auto', app: TERM });
    assert.equal(url.mode, 'dev');
    assert.equal(url.text, 'truy cập https://example');
    const flag = await post.process({ textRaw: 'git gạch nối gạch nối help', mode: 'auto', app: TERM });
    assert.equal(flag.text, 'git --help');
    const notes = await post.process({ textRaw: 'a gạch dưới b', mode: 'auto', app: 'com.apple.Notes' });
    assert.equal(notes.text, 'a gạch dưới b');
    settings.update({ context_symbols: false });
    const off = await post.process({ textRaw: 'truy cập https hai chấm hai gạch chéo example', mode: 'auto', app: TERM });
    assert.ok(!off.text.includes('://'), off.text);
  } finally {
    fs.rmSync(home, { recursive: true, force: true });
  }
});

test('hậu xử lý: "clean" trong Slack ⇒ nhắc tên giữ khoảng trắng và cuối câu không dư dấu cách', async () => {
  const { home, post } = makePost();
  try {
    const r = await post.process({ textRaw: 'chào a còng nam dấu phẩy họp nhé', mode: 'clean', app: SLACK });
    assert.equal(r.text, 'chào @nam, họp nhé');
  } finally {
    fs.rmSync(home, { recursive: true, force: true });
  }
});
