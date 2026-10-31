import test from 'node:test';
import assert from 'node:assert/strict';
import { applyVoicePunctuation } from './punctuation.js';

const t = (s) => applyVoicePunctuation(s).text;

test('dấu chấm/phẩy: dính vào từ trước, không dư khoảng trắng', () => {
  assert.equal(t('anh deploy xong rồi dấu chấm'), 'anh deploy xong rồi.');
  assert.equal(t('một dấu phẩy hai dấu phẩy ba'), 'một, hai, ba');
});

test('viết hoa chữ sau . ? ! và xuống dòng; KHÔNG viết hoa sau , : ;', () => {
  assert.equal(t('việc một dấu chấm việc hai dấu chấm'), 'việc một. Việc hai.');
  assert.equal(t('xong chưa dấu hỏi chấm rồi'), 'xong chưa? Rồi');
  assert.equal(t('một dấu phẩy hai'), 'một, hai'); // không viết hoa sau phẩy
  assert.equal(t('ghi chú dấu hai chấm xong việc'), 'ghi chú: xong việc'); // không viết hoa sau hai chấm
});

test('xuống dòng / đoạn mới: chèn \\n hoặc \\n\\n, viết hoa chữ tiếp theo', () => {
  assert.equal(t('dòng một xuống dòng dòng hai'), 'dòng một\nDòng hai');
  assert.equal(t('đoạn một đoạn mới đoạn hai'), 'đoạn một\n\nĐoạn hai');
  assert.equal(t('a xuống hai dòng b'), 'a\n\nB');
});

test('cụm dài ưu tiên hơn cụm ngắn: "mở ngoặc kép" không bị khớp nhầm thành "mở ngoặc"', () => {
  assert.equal(t('nó nói mở ngoặc kép xin chào đóng ngoặc kép xong'), 'nó nói “xin chào” xong');
  assert.equal(t('mở ngoặc một hai ba đóng ngoặc'), '(một hai ba)');
});

test('chấm than / chấm hỏi / ba chấm / gạch ngang', () => {
  assert.equal(t('tuyệt vời chấm than'), 'tuyệt vời!');
  assert.equal(t('thật sao chấm hỏi'), 'thật sao?');
  assert.equal(t('rồi thì sao ba chấm'), 'rồi thì sao…');
  assert.equal(t('một gạch ngang hai'), 'một – hai'); // "–" không ở trong danh sách dính liền của contract: giữ khoảng trắng tự nhiên hai bên
  assert.equal(t('việc này dấu chấm phẩy câu khác'), 'việc này; câu khác');
});

test('KHÔNG đổi "chấm"/"hỏi" đứng một mình — câu mơ hồ giữ nguyên nguyên văn', () => {
  assert.equal(t('cô giáo chấm điểm bài kiểm tra'), 'cô giáo chấm điểm bài kiểm tra');
  assert.equal(t('em có một câu hỏi'), 'em có một câu hỏi');
  assert.equal(t('dấu hỏi trong tiếng việt rất đa dạng'), 'dấu hỏi trong tiếng việt rất đa dạng');
  assert.equal(t('anh ơi câu hỏi này khó chấm điểm lắm'), 'anh ơi câu hỏi này khó chấm điểm lắm');
});

test('nhiều lệnh liên tiếp: giữ viết hoa xuyên qua một lệnh không phải chữ (vd xuống dòng)', () => {
  assert.equal(t('xong việc một dấu chấm xuống dòng tiếp theo'), 'xong việc một.\nTiếp theo');
});

test('không có lệnh nào ⇒ trả nguyên văn, applied rỗng', () => {
  const r = applyVoicePunctuation('anh đi plôi bản mới nhé');
  assert.equal(r.text, 'anh đi plôi bản mới nhé');
  assert.deepEqual(r.applied, []);
});

test('applied ghi lại from/to cho mỗi lệnh (không rò nội dung ngoài phạm vi lệnh)', () => {
  const r = applyVoicePunctuation('tốt lắm dấu chấm than');
  assert.deepEqual(r.applied, [{ type: 'voice_punctuation', from: 'dấu chấm than', to: '!' }]);
});

test('văn bản đã có dấu câu sẵn (kiểu Whisper): lệnh dấu câu bằng giọng vẫn chạy, không nhân đôi đúng dấu đã có', () => {
  // Người nói vẫn đọc lệnh dù Whisper đã tự chấm câu ⇒ không ra "PR.." (hai dấu chấm).
  assert.equal(t('Please review the PR. dấu chấm'), 'Please review the PR.');
  // Dấu khác với dấu vừa đọc thì KHÔNG bị coi là trùng, vẫn thêm (ví dụ đã có "," thêm ".").
  assert.equal(t('Đã xong việc, dấu chấm'), 'Đã xong việc,.');
  // Lệnh vẫn hoạt động bình thường trên câu đã có dấu câu khi không trùng dấu ngay trước.
  assert.equal(t('Anh đã deploy xong dấu chấm than'), 'Anh đã deploy xong!');
});

test('văn bản kiểu Whisper: dấu câu Whisper tự thêm NGAY SAU cụm lệnh (cuối lời nói) không bị nhân đôi', () => {
  // Bug đã gặp: test ở trên (dòng 60-67) chỉ kiểm dấu đã có TRƯỚC cụm lệnh; nếu Whisper tự chấm
  // câu ngay SAU từ cuối của lệnh (phổ biến khi lệnh đứng cuối câu, vì Whisper luôn kết câu), bản cũ
  // ra "…không?." (hai dấu, một do lệnh một do Whisper) — SAI, phải gộp thành một "?".
  assert.equal(t('Xin chào Dấu phẩy anh khỏe không Dấu hỏi chấm?'), 'Xin chào, anh khỏe không?');
  assert.equal(t('ok Dấu phẩy, tiếp theo'), 'ok, tiếp theo');
  // Dấu KHÁC với dấu lệnh vừa tạo thì KHÔNG coi là trùng, vẫn giữ cả hai (như test dòng 64) — ở đây
  // là trường hợp đối xứng: dấu lạ nằm SAU lệnh (Whisper tự chấm câu bằng dấu khác lệnh).
  assert.equal(t('Anh đã deploy xong Dấu chấm than.'), 'Anh đã deploy xong!.');
});

test('câu tiếng Anh thuần (không có từ khoá lệnh tiếng Việt) ⇒ giữ nguyên hoàn toàn, applied rỗng', () => {
  const sentences = [
    'Please review the pull request before you merge it into main.',
    'The deploy finished at 10:32 PM, and all tests passed.',
    'Is this ready to ship?',
  ];
  for (const s of sentences) {
    const r = applyVoicePunctuation(s);
    assert.equal(r.text, s, s);
    assert.deepEqual(r.applied, [], s);
  }
});
