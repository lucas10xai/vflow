import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdtempSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { createPostProcessor } from './index.js';

function setup(t, config = {}) {
  const dir = mkdtempSync(join(tmpdir(), 'vflow-post-clean-'));
  t.after(() => rmSync(dir, { recursive: true, force: true }));
  const dictionaryPath = join(dir, 'dictionary.json');
  writeFileSync(
    dictionaryPath,
    JSON.stringify({ entries: [{ term: 'deploy', spoken: ['đi plôi'] }, { term: 'npm', spoken: ['en pi em'], case: 'exact' }] }),
  );
  return createPostProcessor({ dictionaryPath, config, log: () => {} });
}

const clean = async (p, textRaw) => (await p.process({ textRaw, mode: 'clean' })).text;

test('clean bỏ từ đệm thuần (ừm, uh, hmm…) kèm dấu phẩy đi theo', async (t) => {
  const p = setup(t);
  assert.equal(await clean(p, 'Ừm, mình cần đi plôi lại.'), 'Mình cần deploy lại.');
  assert.equal(await clean(p, 'mình uh cần hmmm kiểm tra'), 'mình cần kiểm tra');
  assert.equal(await clean(p, 'cần, ừm, deploy lại'), 'cần deploy lại');
  const r = await p.process({ textRaw: 'ừm à mình cần à kiểm tra', mode: 'clean' });
  assert.equal(r.text, 'mình cần kiểm tra');
  assert.deepEqual(r.applied.map((a) => [a.type, a.from]), [
    ['filler_removed', 'ừm'],
    ['filler_removed', 'à'],
    ['filler_removed', 'à'],
  ]);
});

test('clean chỉ bỏ từ đệm đứng riêng, không đụng từ chứa nó', async (t) => {
  const p = setup(t);
  assert.equal(await clean(p, 'umbrella và hmmer và ừa và ơi'), 'umbrella và hmmer và ừa và ơi');
  assert.equal(await clean(p, 'anh ơi em ê'), 'anh ơi em ê'); // "ê" cuối câu: giữ
});

test('clean giữ từ đệm có nghĩa ở các ca nhập nhằng', async (t) => {
  const p = setup(t);
  const keep = [
    'À ra thế.', // à + ra: nhận ra
    'À quên, mai họp nhé.', // à + quên
    'Anh đi rồi à?', // tiểu từ hỏi cuối câu
    'thế à', // cuối văn bản không dấu câu
    'Anh làm xong rồi à em kiểm tra đi', // à sau "rồi": tiểu từ hỏi
    'Ừ, được.', // ừ đầu câu = đồng ý
    'Ừ.', // đứng một mình
    'Ờ thì cũng được.', // ờ + thì
    'Ơ kìa, lỗi rồi.', // ơ + kìa
    'Ê này, xem log đi.', // ê đầu câu = gọi
    'gõ chữ ê có mũ', // tên chữ cái
    'âm à trong tiếng Việt', // tên âm
    'nó nói ừ rồi', // nói ừ = đồng ý
  ];
  for (const s of keep) assert.equal(await clean(p, s), s, s);
});

test('clean bỏ từ đệm ngữ cảnh khi đứng giữa câu và không có ngữ cảnh giữ', async (t) => {
  const p = setup(t);
  assert.equal(await clean(p, 'mình cần ờ chạy lại cái này'), 'mình cần chạy lại cái này');
  assert.equal(await clean(p, 'mở cái ơ terminal'), 'mở cái terminal');
  assert.equal(await clean(p, 'À, mở terminal lên.'), 'Mở terminal lên.');
});

test('clean sửa khoảng trắng/dấu câu nhưng không thêm dấu câu', async (t) => {
  const p = setup(t);
  assert.equal(await clean(p, '  mình   cần ,  kiểm tra  lại !  ok  '), 'Mình cần, kiểm tra lại! Ok');
  // STT không có dấu câu: không thêm, không viết hoa.
  assert.equal(await clean(p, 'mình cần kiểm tra lại  rồi đi plôi'), 'mình cần kiểm tra lại rồi deploy');
  // Không chèn khoảng trắng phá tên miền, phiên bản, số thập phân.
  assert.equal(await clean(p, 'mở next.js bản 15.2 trên api.example.com, giá 3,5 đô.'), 'Mở next.js bản 15.2 trên api.example.com, giá 3,5 đô.');
  // Thuật ngữ case=exact không bị viết hoa đầu câu.
  assert.equal(await clean(p, 'xong rồi. en pi em chạy lại.'), 'Xong rồi. npm chạy lại.');
});

test('clean: chỉ có từ đệm ⇒ chuỗi rỗng; văn bản rỗng ⇒ rỗng', async (t) => {
  const p = setup(t);
  assert.equal(await clean(p, 'ừm, hmm.'), '');
  assert.equal(await clean(p, '   '), '');
});

test('normal không bỏ từ đệm, không sửa dấu câu', async (t) => {
  const p = setup(t);
  const r = await p.process({ textRaw: 'ừm  đi plôi ,  nhé', mode: 'normal' });
  assert.equal(r.text, 'ừm  deploy ,  nhé');
});

test('auto chọn chế độ theo bundle id; không biết ⇒ normal; bảng sửa được qua cấu hình', async (t) => {
  const p = setup(t, { auto: { apps: { 'com.example.Notes': 'clean', 'com.apple.Terminal': 'normal' } } });
  const run = (app) => p.process({ textRaw: 'ừm đi plôi', mode: 'auto', app });
  assert.equal((await run('com.googlecode.iterm2')).mode, 'dev');
  assert.equal((await run('com.googlecode.iterm2')).text, 'deploy');
  assert.equal((await run('com.tinyspeck.slackmacgap')).mode, 'tidy');
  // chưa đặt rewrite.model ⇒ tidy không gọi được LLM, dùng văn bản dự phòng (dict+clean).
  const slack = await run('com.tinyspeck.slackmacgap');
  assert.equal(slack.text, 'deploy');
  assert.equal(slack.rewrite.error, 'no_model');
  assert.equal((await run('com.google.Chrome')).mode, 'normal');
  assert.equal((await run(undefined)).mode, 'normal');
  assert.equal((await run('com.example.Notes')).mode, 'clean');
  assert.equal((await run('com.apple.Terminal')).mode, 'normal'); // ghi đè mặc định
  assert.equal((await run('toString')).mode, 'normal'); // không lọt thuộc tính prototype
});

test('chế độ lạ hoặc textRaw không phải chuỗi ⇒ lỗi bad_request', async (t) => {
  const p = setup(t);
  await assert.rejects(p.process({ textRaw: 'x', mode: 'loud' }), { code: 'bad_request' });
  await assert.rejects(p.process({ textRaw: null }), { code: 'bad_request' });
});
