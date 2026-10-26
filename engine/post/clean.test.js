import test from 'node:test';
import assert from 'node:assert/strict';
import { createServer } from 'node:http';
import { mkdtempSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { createPostProcessor } from './index.js';
import { DEFAULT_CONFIG } from './config.js';

/** Máy chủ LLM giả: đếm yêu cầu, lúc được gọi thì vọng lại nguyên văn người dùng gửi (qua guard tidy dễ dàng). */
async function startFakeLlmServer(t) {
  const requests = [];
  const server = createServer((req, res) => {
    let body = '';
    req.setEncoding('utf8');
    req.on('data', (c) => (body += c));
    req.on('end', () => {
      requests.push(JSON.parse(body));
      const userText = JSON.parse(body).messages.at(-1).content;
      res.writeHead(200, { 'content-type': 'application/json' });
      res.end(JSON.stringify({ choices: [{ message: { content: userText } }] }));
    });
  });
  await new Promise((r) => server.listen(0, '127.0.0.1', r));
  t.after(() => {
    server.closeAllConnections();
    server.close();
  });
  return { url: `http://127.0.0.1:${server.address().port}/v1`, requests };
}

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
  // 'com.tinyspeck.slackmacgap': 'tidy' ở đây là NGƯỜI DÙNG tự ghi đè (mặc định của Slack là 'clean').
  const p = setup(t, { auto: { apps: { 'com.example.Notes': 'clean', 'com.apple.Terminal': 'normal', 'com.tinyspeck.slackmacgap': 'tidy' } } });
  const run = (app) => p.process({ textRaw: 'ừm đi plôi', mode: 'auto', app });
  assert.equal((await run('com.googlecode.iterm2')).mode, 'dev');
  assert.equal((await run('com.googlecode.iterm2')).text, 'deploy');
  assert.equal((await run('com.tinyspeck.slackmacgap')).mode, 'tidy'); // ghi đè mặc định ('clean') sang 'tidy'
  // chưa đặt rewrite.model ⇒ tidy không gọi được LLM, dùng văn bản dự phòng (dict+clean).
  const slack = await run('com.tinyspeck.slackmacgap');
  assert.equal(slack.text, 'deploy');
  assert.equal(slack.rewrite.error, 'no_model');
  assert.equal((await run('com.google.Chrome')).mode, 'normal');
  assert.equal((await run(undefined)).mode, 'normal');
  assert.equal((await run('com.example.Notes')).mode, 'clean');
  assert.equal((await run('com.apple.Terminal')).mode, 'normal'); // ghi đè mặc định
  assert.equal((await run('toString')).mode, 'normal'); // không lọt thuộc tính prototype
  assert.equal((await run('com.apple.mail')).mode, 'clean'); // mặc định mới (bất biến 10): thư → clean, không email
});

test('chế độ lạ hoặc textRaw không phải chuỗi ⇒ lỗi bad_request', async (t) => {
  const p = setup(t);
  await assert.rejects(p.process({ textRaw: 'x', mode: 'loud' }), { code: 'bad_request' });
  await assert.rejects(p.process({ textRaw: null }), { code: 'bad_request' });
});

test('bất biến 10: cấu hình mặc định ⇒ mode=auto KHÔNG BAO GIỜ gọi LLM, với mọi app trong auto.apps mặc định và vài app lạ', async (t) => {
  const srv = await startFakeLlmServer(t);
  const dir = mkdtempSync(join(tmpdir(), 'vflow-post-clean-'));
  t.after(() => rmSync(dir, { recursive: true, force: true }));
  const keyFile = join(dir, 'rewrite.key');
  writeFileSync(keyFile, 'khoa-gia-khong-bao-gio-duoc-dung\n');
  // rewrite.model/key_file được ĐẶT ĐẦY ĐỦ: nếu auto lỡ phân giải sang tidy/email thì sẽ THỰC SỰ gọi srv,
  // nên "0 yêu cầu" dưới đây là bằng chứng thật, không phải vì thiếu model/khoá mà engine tự bỏ qua.
  const config = { rewrite: { url: srv.url, model: 'model-giả', timeout_ms: 2000, key_file: keyFile } };
  const dictionaryPath = join(dir, 'dictionary.json');
  writeFileSync(dictionaryPath, JSON.stringify({ entries: [] }));
  const p = createPostProcessor({ dictionaryPath, config, log: () => {} });

  const apps = [...Object.keys(DEFAULT_CONFIG.auto.apps), 'com.unknown.lạ', 'org.example.KhongTonTai', undefined];
  for (const app of apps) {
    const r = await p.process({ textRaw: 'ừm mình cần kiểm tra lại', mode: 'auto', app });
    assert.ok(['normal', 'clean', 'dev'].includes(r.mode), `app ${app} phải phân giải sang chế độ trong máy, nhận "${r.mode}"`);
    assert.equal(r.rewrite.used, false, `app ${app}: rewrite.used phải false`);
    assert.equal(r.rewrite.error, null, `app ${app}: rewrite.error phải null`);
  }
  assert.equal(srv.requests.length, 0, 'máy chủ LLM giả không được nhận yêu cầu nào');
});

test('ngược với bất biến 10: tự ánh xạ một app tới tidy trong auto.apps ⇒ CÓ gọi LLM', async (t) => {
  const srv = await startFakeLlmServer(t);
  const dir = mkdtempSync(join(tmpdir(), 'vflow-post-clean-'));
  t.after(() => rmSync(dir, { recursive: true, force: true }));
  const keyFile = join(dir, 'rewrite.key');
  writeFileSync(keyFile, 'khoa-gia\n');
  const config = {
    rewrite: { url: srv.url, model: 'model-giả', timeout_ms: 2000, key_file: keyFile },
    auto: { apps: { 'com.example.TuChon': 'tidy' } },
  };
  const dictionaryPath = join(dir, 'dictionary.json');
  writeFileSync(dictionaryPath, JSON.stringify({ entries: [] }));
  const p = createPostProcessor({ dictionaryPath, config, log: () => {} });

  const r = await p.process({ textRaw: 'mình cần kiểm tra lại', mode: 'auto', app: 'com.example.TuChon' });
  assert.equal(r.mode, 'tidy');
  assert.equal(r.rewrite.used, true, JSON.stringify(r));
  assert.equal(srv.requests.length, 1, 'tự ánh xạ sang tidy thì phải thấy đúng 1 yêu cầu LLM');
});
