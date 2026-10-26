import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdtempSync, rmSync, readFileSync, writeFileSync, statSync, chmodSync, readdirSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { createSnippetStore, validateEntries, MAX_ENTRIES } from './snippets.js';

function setup(t, entries) {
  const dir = mkdtempSync(join(tmpdir(), 'vflow-post-snippets-'));
  t.after(() => {
    try { chmodSync(dir, 0o700); } catch { /* đã xoá hoặc không cần */ }
    rmSync(dir, { recursive: true, force: true });
  });
  const path = join(dir, 'snippets.json');
  if (entries) writeFileSync(path, JSON.stringify({ entries }));
  return { dir, path };
}

const LINK = { trigger: 'link lịch hẹn', text: 'https://cal.example/demo' };
const LINK_X = { trigger: 'link lịch', text: 'https://cal.example/khac' };
const SIG = { trigger: 'chữ ký', text: 'Nguyễn Văn An\nAIOS' };

test('khớp cả câu (chuẩn hoá dấu/hoa thường/dấu câu/khoảng trắng) ⇒ thay toàn bộ bằng text', (t) => {
  const { path } = setup(t, [LINK]);
  const store = createSnippetStore({ path });
  for (const spoken of ['link lịch hẹn', 'Link Lịch Hẹn', 'LINK LICH HEN', '  link   lịch hẹn  ', 'link, lịch hẹn!']) {
    const r = store.expand(spoken);
    assert.equal(r.text, LINK.text, spoken);
    assert.equal(r.matched, true, spoken);
    assert.deepEqual(r.applied, [{ type: 'snippet', from: 'link lịch hẹn', to: 'snippet' }]);
  }
});

test('"chèn <trigger>" ở đầu/giữa/cuối câu ⇒ thay đúng cụm, phần còn lại giữ nguyên', (t) => {
  const { path } = setup(t, [LINK]);
  const store = createSnippetStore({ path });
  assert.equal(store.expand('chèn link lịch hẹn vào đây').text, `${LINK.text} vào đây`);
  assert.equal(store.expand('anh gửi chèn link lịch hẹn cho em').text, `anh gửi ${LINK.text} cho em`);
  assert.equal(store.expand('đây là chèn link lịch hẹn').text, `đây là ${LINK.text}`);
  assert.equal(store.expand('Chèn Link Lịch Hẹn nhé').text, `${LINK.text} nhé`);
});

test('cụm trigger dài nhất thắng khi có nhiều trigger là tiền tố của nhau', (t) => {
  const { path } = setup(t, [LINK, LINK_X]);
  const store = createSnippetStore({ path });
  const r = store.expand('chèn link lịch hẹn nhé');
  assert.equal(r.text, `${LINK.text} nhé`);
  assert.deepEqual(r.applied, [{ type: 'snippet', from: LINK.trigger, to: 'snippet' }]);
  const r2 = store.expand('chèn link lịch nhé');
  assert.equal(r2.text, `${LINK_X.text} nhé`);
});

test('không mở rộng ở dạng khác: trigger là một phần câu (không "chèn", không trùng cả câu), hoặc dính liền chữ khác', (t) => {
  const { path } = setup(t, [LINK]);
  const store = createSnippetStore({ path });
  const noMatch = [
    'cho tôi link lịch hẹn với',       // có trigger nhưng không "chèn", không phải cả câu
    'chènlink lịch hẹn',               // dính liền "chèn", không phải một từ riêng
    'chèn link lịch hẹnx',             // từ cuối dính thêm ký tự, token khác
    'không liên quan gì cả',
  ];
  for (const s of noMatch) {
    const r = store.expand(s);
    assert.equal(r.matched, false, s);
    assert.equal(r.text, s, s);
    assert.deepEqual(r.applied, [], s);
  }
});

test('snippet nhiều dòng giữ nguyên văn, không qua từ điển/làm gọn', (t) => {
  const { path } = setup(t, [SIG]);
  const store = createSnippetStore({ path });
  assert.equal(store.expand('chữ ký').text, SIG.text);
  assert.ok(store.expand('chữ ký').text.includes('\n'));
});

test('validateEntries: schema, trùng trigger sau chuẩn hoá, khoá lạ, độ dài, tối đa 500 mục', () => {
  const bad = [
    'không phải mảng',
    [{ trigger: '', text: 'x' }],
    [{ trigger: 'a', text: '' }],
    [{ trigger: '!!!', text: 'x' }],
    [{ trigger: 'a'.repeat(61), text: 'x' }],
    [{ trigger: 'a', text: 'x'.repeat(5001) }],
    [{ trigger: 'a', text: 'x', extra: 1 }],
    [{ trigger: 'a', text: 'x', uses: -1 }],
    [{ trigger: 'a', text: 'x', last_used: 'hôm qua' }],
    [{ trigger: 'Link Hẹn', text: 'x' }, { trigger: 'link, hẹn!', text: 'y' }],
    Array.from({ length: 501 }, (_, i) => ({ trigger: `t${i}`, text: 'x' })),
  ];
  for (const entries of bad) assert.throws(() => validateEntries(entries), { code: 'bad_request' }, JSON.stringify(entries).slice(0, 60));
  const ok = validateEntries(Array.from({ length: MAX_ENTRIES }, (_, i) => ({ trigger: `t${i}`, text: 'x' })));
  assert.equal(ok.length, MAX_ENTRIES);
});

test('replaceAll từ chối schema sai và không đổi gì (tệp + bộ nhớ)', (t) => {
  const { path } = setup(t, [LINK]);
  const store = createSnippetStore({ path });
  const before = readFileSync(path, 'utf8');
  assert.throws(() => store.replaceAll([{ trigger: 'a', text: '' }]), { code: 'bad_request' });
  assert.equal(readFileSync(path, 'utf8'), before);
  assert.equal(store.list().entries.length, 1);
  // sau một lần thất bại, mở rộng vẫn hoạt động đúng với dữ liệu cũ
  assert.equal(store.expand('link lịch hẹn').text, LINK.text);
});

test('tệp 0600, ghi nguyên tử (không còn tệp .tmp- rơi lại)', (t) => {
  const { path, dir } = setup(t, [LINK]);
  const store = createSnippetStore({ path });
  store.replaceAll([SIG]);
  if (process.platform !== 'win32') assert.equal(statSync(path).mode & 0o777, 0o600);
  const leftover = readdirSync(dir).filter((f) => f.includes('.tmp-'));
  assert.deepEqual(leftover, []);
});

test('tệp snippets hỏng ⇒ lỗi rõ ràng, không âm thầm coi là rỗng', (t) => {
  const dir = mkdtempSync(join(tmpdir(), 'vflow-post-snippets-'));
  t.after(() => rmSync(dir, { recursive: true, force: true }));
  const path = join(dir, 'snippets.json');
  writeFileSync(path, '{"entries": [ {"trigger": "x", ');
  assert.throws(() => createSnippetStore({ path }), { code: 'bad_request', message: /tệp snippets hỏng/ });
});

test('uses/last_used tăng và lưu bền qua cả hai dạng mở rộng; mở lại tệp còn số liệu', (t) => {
  let tick = 0;
  const { path } = setup(t, [LINK]);
  const store = createSnippetStore({ path, now: () => new Date(Date.UTC(2026, 9, 26, ++tick)) });
  store.expand('link lịch hẹn');
  store.expand('chèn link lịch hẹn vào đây');
  const stored = JSON.parse(readFileSync(path, 'utf8')).entries;
  assert.equal(stored[0].uses, 2);
  assert.equal(stored[0].last_used, '2026-10-26T02:00:00.000Z');
  const again = createSnippetStore({ path });
  assert.equal(again.list().entries[0].uses, 2);
});

test('chưa khớp ⇒ không ghi tệp, không tăng uses', (t) => {
  const { path } = setup(t, [LINK]);
  const store = createSnippetStore({ path });
  const before = readFileSync(path, 'utf8');
  store.expand('không liên quan');
  assert.equal(readFileSync(path, 'utf8'), before);
});

test('danh sách rỗng (chưa có tệp) ⇒ expand không đổi gì, không lỗi', (t) => {
  const { path } = setup(t, null);
  const store = createSnippetStore({ path });
  assert.deepEqual(store.list(), { entries: [] });
  assert.deepEqual(store.expand('chèn gì đó'), { text: 'chèn gì đó', applied: [], matched: false });
});

test('lưu lỗi khi mở rộng (vd. EACCES) ⇒ vẫn trả text đúng, log chỉ có mã lỗi, không có nội dung snippet', { skip: process.platform === 'win32' ? 'POSIX permissions only' : false }, (t) => {
  const { path, dir } = setup(t, [LINK]);
  const logs = [];
  const store = createSnippetStore({ path, log: (e) => logs.push(e) });
  chmodSync(dir, 0o500); // thư mục chỉ đọc: ghi tệp tạm sẽ lỗi EACCES
  try {
    const r = store.expand('link lịch hẹn');
    assert.equal(r.text, LINK.text);
    assert.equal(logs.length, 1);
    assert.equal(logs[0].event, 'snippet_save_failed');
    assert.ok(logs[0].code);
    const dump = JSON.stringify(logs);
    assert.ok(!dump.includes(LINK.text));
    assert.ok(!dump.includes(LINK.trigger));
  } finally {
    chmodSync(dir, 0o700); // cho phép setup() dọn thư mục tạm
  }
});
