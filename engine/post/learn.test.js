import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdtempSync, rmSync, writeFileSync, readFileSync, statSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { createPostProcessor } from './index.js';
import { createCorrectionsStore } from './learn.js';

function setup(t) {
  const dir = mkdtempSync(join(tmpdir(), 'vflow-post-learn-'));
  t.after(() => rmSync(dir, { recursive: true, force: true }));
  const dictionaryPath = join(dir, 'dictionary.json');
  writeFileSync(dictionaryPath, JSON.stringify({ entries: [{ term: 'Docker', spoken: ['đốc cơ'] }] }));
  return { p: createPostProcessor({ dictionaryPath, log: () => {} }), dictionaryPath };
}

test('learnCorrection gợi ý khi sửa một cụm thành từ khác (kể cả tiếng Anh), không ghi gì', (t) => {
  const { p, dictionaryPath } = setup(t);
  const before = readFileSync(dictionaryPath, 'utf8');
  const r = p.dictionary.learnCorrection({
    before: 'kiểm tra lại xu pa bết rồi mở tên sờ cây nhé',
    after: 'kiểm tra lại Supabase rồi mở Tailscale nhé',
  });
  assert.deepEqual(r, {
    suggestions: [
      { term: 'Supabase', spoken: ['xu pa bết'] },
      { term: 'Tailscale', spoken: ['tên sờ cây'] },
    ],
  });
  // Thuật ngữ có dấu chấm và tiếng Việt → tiếng Việt cũng được.
  assert.deepEqual(p.dictionary.learnCorrection({ before: 'chạy nếch giây ét đi', after: 'chạy Next.js đi' }).suggestions, [
    { term: 'Next.js', spoken: ['nếch giây ét'] },
  ]);
  assert.deepEqual(p.dictionary.learnCorrection({ before: 'gửi cho bên ây tê', after: 'gửi cho bên IT' }).suggestions, [
    { term: 'IT', spoken: ['ây tê'] },
  ]);
  assert.equal(readFileSync(dictionaryPath, 'utf8'), before);
  assert.equal(p.dictionary.list().entries.length, 1);
});

test('learnCorrection lọc nhiễu', (t) => {
  const { p } = setup(t);
  const none = (before, after, why) => assert.deepEqual(p.dictionary.learnCorrection({ before, after }), { suggestions: [] }, why);
  none('chạy đốc cơ đi', 'chạy đốc cơ đi', 'giống hệt');
  none('chạy đốc cơ đi', 'Chạy đốc cơ đi.', 'chỉ đổi dấu câu/hoa thường');
  none('chạy đốc cơ, đi', 'chạy đốc cơ đi!', 'chỉ đổi dấu câu');
  none('ma nhà mình', 'má nhà mình', 'chỉ đổi dấu thanh');
  none('chạy đốc cờ đi', 'chạy Docker đi', 'đã có trong từ điển (khác dấu thanh)');
  none('em gửi bản số một trăm', 'em gửi bản số 100', 'sửa số liệu');
  none('mở cái này ra rồi đóng cái kia lại luôn nhé', 'tắt hết mọi thứ và nghỉ ngơi đi thôi', 'viết lại cả câu');
  none('a b c d e f g', 'a x b y c z d w e', 'quá nhiều chỗ sửa');
  none(
    'sáng nay mình cần chạy lại cái lệnh dài dài này trên máy chủ chính rồi báo cáo kết quả cho cả nhóm nhé',
    'sáng nay mình cần Kubernetes trên máy chủ chính rồi báo cáo kết quả cho cả nhóm nhé',
    'cụm bị sửa quá dài (7 từ) trong câu dài',
  );
  none('chạy lại', 'chạy lại ngay bây giờ', 'chỉ thêm từ');
  none('chạy lại ngay bây giờ', 'chạy lại', 'chỉ xoá từ');
  none('', 'Docker', 'rỗng');
  none(null, 'Docker', 'không phải chuỗi');
  none('x '.repeat(400), 'y '.repeat(400), 'quá dài');
});

test('learnCorrection gộp biến thể trùng và bỏ biến thể đã có', (t) => {
  const { p } = setup(t);
  const r = p.dictionary.learnCorrection({ before: 'pun ri quét và pun ri quét', after: 'pull request và pull request' });
  assert.deepEqual(r.suggestions, []); // sửa hai chỗ chiếm quá nửa câu ⇒ coi là viết lại
  const r2 = p.dictionary.learnCorrection({ before: 'mở lại cái pun ri quét số năm hôm qua cho anh', after: 'mở lại cái pull request số năm hôm qua cho anh' });
  assert.deepEqual(r2.suggestions, [{ term: 'pull request', spoken: ['pun ri quét'] }]);
});

function corrTmp(t) {
  const dir = mkdtempSync(join(tmpdir(), 'vflow-post-corrections-'));
  t.after(() => rmSync(dir, { recursive: true, force: true }));
  return join(dir, 'corrections.json');
}

test('corrections store: record() lưu cặp term/spoken ngắn, suggestions() chỉ trả khi xuất hiện ≥ 2 lần', (t) => {
  const path = corrTmp(t);
  const store = createCorrectionsStore({ path });
  store.record('xu pa bết', 'Supabase');
  assert.deepEqual(store.suggestions([]).suggestions, [], 'mới 1 lần, chưa đủ ngưỡng');
  store.record('xu pa bết', 'Supabase');
  const s = store.suggestions([]);
  assert.deepEqual(s.suggestions, [{ term: 'Supabase', variants: ['xu pa bết'], count: 2, last_seen: s.suggestions[0].last_seen }]);
  assert.ok(typeof s.suggestions[0].last_seen === 'string' && !Number.isNaN(Date.parse(s.suggestions[0].last_seen)));
});

test('corrections store: không lưu gì khi before/after là viết lại cả câu (dùng cùng bộ lọc suggestCorrections)', (t) => {
  const store = createCorrectionsStore({ path: corrTmp(t) });
  store.record('mở cái này ra rồi đóng cái kia lại luôn nhé', 'tắt hết mọi thứ và nghỉ ngơi đi thôi');
  store.record('mở cái này ra rồi đóng cái kia lại luôn nhé', 'tắt hết mọi thứ và nghỉ ngơi đi thôi');
  assert.deepEqual(store.suggestions([]).suggestions, []);
});

test('corrections store: bỏ gợi ý đã có trong từ điển (so theo term+spoken đã fold)', (t) => {
  const store = createCorrectionsStore({ path: corrTmp(t) });
  for (let i = 0; i < 3; i++) store.record('đi plôi', 'deploy');
  assert.deepEqual(store.suggestions([{ term: 'deploy', spoken: ['đi plôi', 'đì ploi'] }]).suggestions, []);
  assert.equal(store.suggestions([]).suggestions.length, 1, 'không có trong từ điển khác thì vẫn gợi ý');
});

test('corrections store: dismiss(term) ⇒ không hiện lại gợi ý của term đó nữa', (t) => {
  const store = createCorrectionsStore({ path: corrTmp(t) });
  for (let i = 0; i < 2; i++) store.record('xu pa bết', 'Supabase');
  assert.equal(store.suggestions([]).suggestions.length, 1);
  assert.deepEqual(store.dismiss('Supabase'), { ok: true });
  assert.deepEqual(store.suggestions([]).suggestions, []);
  // ghi thêm nữa sau khi dismiss vẫn không hiện lại.
  store.record('xu pa bết', 'Supabase');
  assert.deepEqual(store.suggestions([]).suggestions, []);
});

test('corrections store: tối đa 500 mục gần nhất, ghi 0600, không chứa cả câu gốc', (t) => {
  const dir = mkdtempSync(join(tmpdir(), 'vflow-post-corrections-cap-'));
  t.after(() => rmSync(dir, { recursive: true, force: true }));
  const path = join(dir, 'corrections.json');
  const store = createCorrectionsStore({ path });
  for (let i = 0; i < 600; i++) store.record(`từ số ${i} lạ`, `TermNo${i}`);
  const raw = JSON.parse(readFileSync(path, 'utf8'));
  assert.ok(raw.entries.length <= 500, `phải <= 500 mục, được ${raw.entries.length}`);
  if (process.platform !== 'win32') assert.equal(statSync(path).mode & 0o777, 0o600);
});

test('corrections store: tệp hỏng ⇒ lỗi rõ ràng, không âm thầm coi là rỗng', (t) => {
  const path = corrTmp(t);
  writeFileSync(path, '{ bad json');
  assert.throws(() => createCorrectionsStore({ path }), { code: 'internal' });
});

test('createPostProcessor + corrections: learnCorrection ghi vào corrections (khi learn_from_edits bật) rồi suggestions()/dismissSuggestion() hoạt động qua post.dictionary', (t) => {
  const dir = mkdtempSync(join(tmpdir(), 'vflow-post-learn-wired-'));
  t.after(() => rmSync(dir, { recursive: true, force: true }));
  const dictionaryPath = join(dir, 'dictionary.json');
  writeFileSync(dictionaryPath, JSON.stringify({ entries: [] }));
  const correctionsPath = join(dir, 'corrections.json');
  const corrections = createCorrectionsStore({ path: correctionsPath });
  const p = createPostProcessor({ dictionaryPath, corrections, log: () => {} });
  p.dictionary.learnCorrection({ before: 'xu pa bết', after: 'Supabase' });
  p.dictionary.learnCorrection({ before: 'xu pa bết', after: 'Supabase' });
  assert.deepEqual(p.dictionary.suggestions(), { suggestions: [{ term: 'Supabase', variants: ['xu pa bết'], count: 2, last_seen: p.dictionary.suggestions().suggestions[0].last_seen }] });
  assert.deepEqual(p.dictionary.dismissSuggestion('Supabase'), { ok: true });
  assert.deepEqual(p.dictionary.suggestions(), { suggestions: [] });
});

test('createPostProcessor + corrections: learn_from_edits=false (qua settings) ⇒ learnCorrection KHÔNG ghi vào corrections', (t) => {
  const dir = mkdtempSync(join(tmpdir(), 'vflow-post-learn-off-'));
  t.after(() => rmSync(dir, { recursive: true, force: true }));
  const dictionaryPath = join(dir, 'dictionary.json');
  writeFileSync(dictionaryPath, JSON.stringify({ entries: [] }));
  const corrections = createCorrectionsStore({ path: join(dir, 'corrections.json') });
  const settings = { get: () => ({ learn_from_edits: false }) };
  const p = createPostProcessor({ dictionaryPath, corrections, settings, log: () => {} });
  for (let i = 0; i < 3; i++) p.dictionary.learnCorrection({ before: 'xu pa bết', after: 'Supabase' });
  assert.deepEqual(p.dictionary.suggestions(), { suggestions: [] });
});
