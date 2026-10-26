import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdtempSync, rmSync, writeFileSync, readFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { createPostProcessor } from './index.js';

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
