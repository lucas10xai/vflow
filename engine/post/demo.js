// Demo: một đoạn văn bản thô (giả lập đầu ra STT) đi qua 4 chế độ.
// Chế độ email dùng MÁY CHỦ GIẢ dựng ngay trong demo (không gọi 9Router thật); khoá là chuỗi giả.
// Chạy: node engine/post/demo.js
import { createServer } from 'node:http';
import { mkdtempSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { createPostProcessor } from './index.js';

const RAW = 'ừm anh ơi em đã đi plôi bản mới lên sờ tây dinh rồi , à mai em com mít nốt cái hót phích và mở pun ri quét trên ghít hấp nhé';

// Máy chủ giả: trả một "email" dựng bằng quy tắc từ chính văn bản nhận được, để thấy rõ luồng.
const fake = createServer((req, res) => {
  let body = '';
  req.on('data', (c) => (body += c));
  req.on('end', () => {
    const text = JSON.parse(body).messages.at(-1).content;
    res.writeHead(200, { 'content-type': 'application/json' });
    res.end(JSON.stringify({ choices: [{ message: { content: `[MÁY CHỦ GIẢ] Kính gửi anh,\n\nEm xin báo: ${text}.\n\nTrân trọng.` } }] }));
  });
});
await new Promise((r) => fake.listen(0, '127.0.0.1', r));

const dir = mkdtempSync(join(tmpdir(), 'vflow-post-demo-'));
try {
  writeFileSync(join(dir, 'fake.key'), 'khoa-gia-cho-demo');
  const post = createPostProcessor({
    dictionaryPath: join(dir, 'dictionary.json'), // chưa có ⇒ dùng hạt giống
    config: {
      rewrite: { url: `http://127.0.0.1:${fake.address().port}/v1`, model: 'demo-fake', key_file: join(dir, 'fake.key') },
    },
  });
  console.log(`ĐẦU VÀO (text_raw):\n  ${RAW}\n`);
  for (const [mode, app] of [['normal'], ['clean'], ['email'], ['auto', 'com.googlecode.iterm2'], ['auto', 'com.google.Chrome']]) {
    const r = await post.process({ textRaw: RAW, mode, app });
    console.log(`── mode=${mode}${app ? ` app=${app} ⇒ ${r.mode}` : ''}`);
    console.log(`  text: ${r.text.replace(/\n/g, '\n        ')}`);
    console.log(`  applied: ${r.applied.map((a) => `${a.type}:"${a.from}"→"${a.to}"`).join(', ')}`);
    console.log(`  rewrite: ${JSON.stringify(r.rewrite)}\n`);
  }
  // Email khi máy chủ viết lại không chạy.
  fake.close();
  fake.closeAllConnections();
  const r = await post.process({ textRaw: RAW, mode: 'email' });
  console.log(`── mode=email (máy chủ giả đã tắt)\n  text: ${r.text}\n  rewrite: ${JSON.stringify(r.rewrite)}`);
} finally {
  rmSync(dir, { recursive: true, force: true });
  fake.close();
}
