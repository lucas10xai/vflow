import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdtempSync, rmSync, readFileSync, writeFileSync, statSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { createPostProcessor, DEFAULT_SEED_PATH } from './index.js';
import { validateEntries, MAX_ENTRIES } from './dictionary.js';
import { fold, tokenize } from './text.js';

const quiet = () => {};

/** Bộ xử lý với từ điển riêng trong thư mục tạm. */
function setup(t, entries, extra = {}) {
  const dir = mkdtempSync(join(tmpdir(), 'vflow-post-dict-'));
  t.after(() => rmSync(dir, { recursive: true, force: true }));
  const dictionaryPath = join(dir, 'dictionary.json');
  if (entries) writeFileSync(dictionaryPath, JSON.stringify({ entries }));
  const p = createPostProcessor({ dictionaryPath, log: quiet, ...extra });
  return { p, dir, dictionaryPath };
}

const ENTRIES = [
  { term: 'deploy', spoken: ['đi plôi', 'đì ploi'] },
  { term: 'API', spoken: ['ây pi ai'] },
  { term: 'API key', spoken: ['ây pi ai ki'] },
  { term: 'push', spoken: ['pút'] },
  { term: 'npm', spoken: ['en pi em'], case: 'exact' },
];

test('chỉ thay theo ranh giới từ, không thay chuỗi con trong từ khác', async (t) => {
  const { p } = setup(t, ENTRIES);
  // "pút" là một từ: thay. "púts", "xpút" là từ khác: giữ. Định danh/URL dính liền: giữ.
  const r = await p.process({ textRaw: 'pút đi, đừng púts hay xpút, giữ api.pút và x_pút và pút.js' });
  assert.equal(r.text, 'push đi, đừng púts hay xpút, giữ api.pút và x_pút và pút.js');
  assert.deepEqual(r.applied, [{ type: 'dictionary', from: 'pút', to: 'push' }]);
});

test('các từ của biến thể phải liền nhau (chỉ cách bằng khoảng trắng/gạch nối), không vượt dấu câu', async (t) => {
  const { p } = setup(t, ENTRIES);
  assert.equal((await p.process({ textRaw: 'đi-plôi xong' })).text, 'deploy xong');
  assert.equal((await p.process({ textRaw: 'đi, plôi xong' })).text, 'đi, plôi xong');
  assert.equal((await p.process({ textRaw: 'đi. Plôi xong' })).text, 'đi. Plôi xong');
});

test('ưu tiên cụm dài nhất', async (t) => {
  const { p } = setup(t, ENTRIES);
  const r = await p.process({ textRaw: 'lấy ây pi ai ki rồi gọi ây pi ai' });
  assert.equal(r.text, 'lấy API key rồi gọi API');
  assert.deepEqual(r.applied.map((a) => a.to), ['API key', 'API']);
});

test('không phân biệt hoa/thường và dấu thanh khi khớp, nhưng giữ dấu mũ/móc', async (t) => {
  const { p } = setup(t, ENTRIES);
  assert.equal((await p.process({ textRaw: 'ĐI PLỐI ngay' })).text, 'Deploy ngay');
  assert.equal((await p.process({ textRaw: 'nhớ đi plối nhé' })).text, 'nhớ deploy nhé');
  assert.equal((await p.process({ textRaw: 'nhớ đi ploi nhé' })).text, 'nhớ deploy nhé'); // biến thể "đì ploi"
  // "plơi" khác "plôi" ở dấu mũ (không phải dấu thanh): không khớp.
  assert.equal((await p.process({ textRaw: 'nhớ đi plơi nhé' })).text, 'nhớ đi plơi nhé');
  // Văn bản NFD (dấu tách rời) vẫn khớp.
  assert.equal((await p.process({ textRaw: 'nhớ đi plôi nhé'.normalize('NFD') })).text, 'nhớ deploy nhé');
});

test('đầu câu viết hoa thì thuật ngữ viết hoa; thuật ngữ case=exact giữ nguyên', async (t) => {
  const { p } = setup(t, ENTRIES);
  assert.equal((await p.process({ textRaw: 'Đi plôi xong. Pút lên.' })).text, 'Deploy xong. Push lên.');
  assert.equal((await p.process({ textRaw: 'En pi em cài xong' })).text, 'npm cài xong');
  assert.equal((await p.process({ textRaw: 'gọi ây pi ai' })).text, 'gọi API');
});

test('uses/last_used tăng và được lưu bền, tệp quyền 0600', async (t) => {
  let tick = 0;
  const { p, dictionaryPath } = setup(t, ENTRIES, { now: () => new Date(Date.UTC(2026, 9, 26, ++tick)) });
  await p.process({ textRaw: 'đi plôi' });
  await p.process({ textRaw: 'đi plôi rồi pút' });
  const stored = JSON.parse(readFileSync(dictionaryPath, 'utf8')).entries;
  const deploy = stored.find((e) => e.term === 'deploy');
  assert.equal(deploy.uses, 2);
  assert.equal(deploy.last_used, '2026-10-26T02:00:00.000Z'); // lần dùng thứ 2 (giờ thứ 2)
  assert.equal(stored.find((e) => e.term === 'push').uses, 1);
  assert.equal(stored.find((e) => e.term === 'API').uses, 0);
  // Mở lại từ tệp: số liệu còn.
  const again = createPostProcessor({ dictionaryPath, log: quiet });
  assert.equal(again.dictionary.list().entries.find((e) => e.term === 'deploy').uses, 2);
  if (process.platform !== 'win32') assert.equal(statSync(dictionaryPath).mode & 0o777, 0o600);
});

test('chưa có tệp từ điển thì dùng hạt giống, không ghi gì cho tới khi có thay đổi', async (t) => {
  const { p, dictionaryPath } = setup(t, null);
  assert.ok(p.dictionary.list().entries.length >= 80);
  assert.throws(() => statSync(dictionaryPath), { code: 'ENOENT' });
  assert.equal((await p.process({ textRaw: 'đốc cơ chạy rồi' })).text, 'Docker chạy rồi');
  assert.ok(statSync(dictionaryPath).isFile());
});

test('tệp từ điển hỏng ⇒ lỗi rõ ràng, không âm thầm dùng hạt giống', (t) => {
  const dir = mkdtempSync(join(tmpdir(), 'vflow-post-dict-'));
  t.after(() => rmSync(dir, { recursive: true, force: true }));
  const dictionaryPath = join(dir, 'dictionary.json');
  writeFileSync(dictionaryPath, '{"entries": [ {"term": "x", ');
  assert.throws(() => createPostProcessor({ dictionaryPath, log: quiet }), { code: 'bad_request', message: /tệp từ điển hỏng/ });
});

test('replaceAll từ chối schema sai và không đổi từ điển cũ', (t) => {
  const { p, dictionaryPath } = setup(t, ENTRIES);
  const before = readFileSync(dictionaryPath, 'utf8');
  const bad = [
    'không phải mảng',
    { entries: [] },
    [{ term: '', spoken: ['a'] }],
    [{ term: 'x', spoken: [] }],
    [{ term: 'x', spoken: 'a' }],
    [{ term: 'x', spoken: ['...'] }],
    [{ term: 'x', spoken: ['a'], kind: 'other' }],
    [{ term: 'x', spoken: ['a'], uses: -1 }],
    [{ term: 'x', spoken: ['a'], last_used: 'hôm qua' }],
    [{ term: 'x', spoken: ['a'], extra: 1 }],
    [{ term: 'x', spoken: ['a'] }, { term: 'x', spoken: ['b'] }],
    [{ term: 'x'.repeat(101), spoken: ['a'] }],
  ];
  for (const entries of bad) {
    assert.throws(() => p.dictionary.replaceAll(entries), { code: 'bad_request' }, JSON.stringify(entries).slice(0, 60));
  }
  assert.equal(readFileSync(dictionaryPath, 'utf8'), before);
  assert.equal(p.dictionary.list().entries.length, ENTRIES.length);
});

test('replaceAll nhận tối đa 5000 mục, 5001 bị từ chối', (t) => {
  const { p } = setup(t, ENTRIES);
  const make = (n) => Array.from({ length: n }, (_, i) => ({ term: `t${i}`, spoken: [`từ ${i}`] }));
  assert.throws(() => p.dictionary.replaceAll(make(MAX_ENTRIES + 1)), { code: 'bad_request', message: /5000/ });
  const r = p.dictionary.replaceAll(make(MAX_ENTRIES));
  assert.equal(r.count, MAX_ENTRIES);
  assert.equal(r.permissions, process.platform === 'win32' ? 'not_applied_windows' : '0600');
});

test('replaceAll áp dụng ngay cho lần xử lý sau', async (t) => {
  const { p, dictionaryPath } = setup(t, ENTRIES);
  p.dictionary.replaceAll([{ term: 'Supabase', spoken: ['xu pa bết'], kind: 'term' }]);
  assert.equal((await p.process({ textRaw: 'đi plôi lên xu pa bết' })).text, 'đi plôi lên Supabase');
  const stored = JSON.parse(readFileSync(dictionaryPath, 'utf8'));
  assert.deepEqual(stored.entries, [{ term: 'Supabase', spoken: ['xu pa bết'], kind: 'term', uses: 1, last_used: stored.entries[0].last_used }]);
});

// --- Hạt giống ---

const seed = JSON.parse(readFileSync(DEFAULT_SEED_PATH, 'utf8'));

test('hạt giống: hợp schema, 80–150 mục, không có IP/khoá/email', () => {
  const entries = validateEntries(seed.entries);
  assert.ok(entries.length >= 80 && entries.length <= 150, `số mục: ${entries.length}`);
  const raw = readFileSync(DEFAULT_SEED_PATH, 'utf8');
  assert.doesNotMatch(raw, /\b\d{1,3}(\.\d{1,3}){3}\b/, 'có địa chỉ IP');
  assert.doesNotMatch(raw, /sk-[A-Za-z0-9]{8,}|@[a-z0-9-]+\.[a-z]/i, 'có thứ giống khoá/email');
});

test('hạt giống: một biến thể nói không trỏ tới hai thuật ngữ khác nhau', () => {
  const owner = new Map();
  for (const e of seed.entries) {
    for (const s of e.spoken) {
      const key = tokenize(s).map((t) => fold(t.word)).join(' ');
      if (owner.has(key)) assert.equal(owner.get(key), e.term, `"${s}" trùng giữa ${owner.get(key)} và ${e.term}`);
      owner.set(key, e.term);
    }
  }
});

test('hạt giống: biến thể một âm tiết không trùng từ tiếng Việt thông dụng (khi bỏ dấu thanh)', () => {
  // Danh sách chặn đã bỏ dấu thanh: các âm tiết hay gặp mà khớp không dấu sẽ thay nhầm.
  const common = new Set(
    ('bac boc bâc ket tet loc lôc dep nôt nau bin suyt tô cân rac tai mau ôn lai bung bat but cut hut ' +
      'đi đên vê ra vao lên xuông lam co không đươc rôi nay đo kia minh anh em chi ông ba ban ho ta ' +
      'cai con nhưng cung đa se đang thi ma la va vơi cho cua trong ngoai trên dươi sau trươc moi ' +
      'môt hai ba bôn năm sau bay tam chin mươi tram nghin triêu tiên ngay giơ phut gio nươc an uông ' +
      'nhin nghe noi đoc viêt hoc chay dưng mơ đong xem tim sưa xoa thêm bo lây gưi nhân goi tra hoi ' +
      'biêt muôn cân phai nên hay rât qua lăm nhiêu it đu hêt xong vưa mơi chưa vân con nưa thôi').split(/\s+/),
  );
  for (const e of seed.entries) {
    for (const s of e.spoken) {
      const toks = tokenize(s);
      if (toks.length === 1) assert.ok(!common.has(fold(toks[0].word)), `"${s}" (${e.term}) trùng từ thông dụng`);
    }
  }
});

test('khớp văn bản tiếng Anh (vd STT đa ngôn ngữ như Whisper trả đúng chữ Anh), không phân biệt hoa/thường, không phá từ', async (t) => {
  const entries = [
    ...ENTRIES,
    { term: 'Kubernetes', spoken: ['kubernetes', 'k8s'] },
    { term: 'pull request', spoken: ['pull request', 'pr'] },
  ];
  const { p } = setup(t, entries);
  // Hoa toàn bộ (kiểu Whisper): vẫn khớp, đầu câu viết hoa theo thuật ngữ.
  assert.equal((await p.process({ textRaw: 'KUBERNETES cluster is ready' })).text, 'Kubernetes cluster is ready');
  // Biến thể viết tắt, hoa lẫn với số: K8s vẫn khớp.
  assert.equal((await p.process({ textRaw: 'deploy to K8s now' })).text, 'deploy to Kubernetes now');
  // Nhiều từ, chữ thường.
  assert.equal((await p.process({ textRaw: 'please review the pr' })).text, 'please review the pull request');
  // KHÔNG phá từ: "kubernetes-cli"/"pr." (dính URL) hay "pr" là một phần của từ khác không bị thay nhầm.
  assert.equal((await p.process({ textRaw: 'kubernetes-cli and reporting are different things' })).text, 'kubernetes-cli and reporting are different things');
});

test('applyPreview: thay đúng như apply() nhưng KHÔNG tăng uses/last_used, KHÔNG ghi tệp (dùng cho /v1/partial)', (t) => {
  const { p, dictionaryPath } = setup(t, ENTRIES);
  const before = readFileSync(dictionaryPath, 'utf8');
  const beforeUses = p.dictionary.list().entries.find((e) => e.term === 'deploy').uses;
  const r = p.dictionary.applyPreview('anh đi plôi bản mới');
  assert.equal(r.text, 'anh deploy bản mới');
  assert.deepEqual(r.applied, [{ type: 'dictionary', from: 'đi plôi', to: 'deploy' }]);
  assert.equal(readFileSync(dictionaryPath, 'utf8'), before, 'không ghi tệp');
  assert.equal(p.dictionary.list().entries.find((e) => e.term === 'deploy').uses, beforeUses, 'không tăng uses');
});
