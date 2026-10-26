import test from 'node:test';
import assert from 'node:assert/strict';
import { applyDevspeech } from './devspeech.js';

test('ký hiệu đơn: gạch dưới/ngang/chéo, hai chấm, dấu bằng, ngoặc, nháy', () => {
  const CASES = [
    ['a gạch dưới b', 'a_b'],
    ['a gạch ngang b', 'a-b'],
    ['a gạch chéo b', 'a/b'],
    ['a sờ lát b', 'a/b'],
    ['a dấu bằng b', 'a=b'],
    ['hàm foo mở ngoặc a đóng ngoặc', 'hàm foo(a)'],
    ['foo mở ngoặc vuông a đóng ngoặc vuông', 'foo[a]'],
    ['foo mở ngoặc nhọn a đóng ngoặc nhọn', 'foo{a}'],
    ['dấu nháy đơn a dấu nháy đơn', "'a'"],
    ['dấu nháy kép a dấu nháy kép', '"a"'],
    ['dấu nháy a dấu nháy', "'a'"],
  ];
  for (const [input, expected] of CASES) {
    assert.equal(applyDevspeech(input).text, expected, input);
  }
});

test('chấm → "." giữa hai định danh hoặc trước đuôi tệp biết trước', () => {
  assert.equal(applyDevspeech('src gạch chéo app chấm ts').text, 'src/app.ts');
  assert.equal(applyDevspeech('app chấm js').text, 'app.js');
  assert.equal(applyDevspeech('x chấm y').text, 'x.y');
});

test('ca nhập nhằng: "chấm điểm", "chấm công", "gạch chân" KHÔNG bị đổi', () => {
  for (const input of ['chấm điểm', 'chấm công', 'gạch chân', 'tôi sẽ chấm điểm học sinh', 'em chấm công rồi về']) {
    assert.equal(applyDevspeech(input).text, input, input);
  }
});

test('ca nhập nhằng: số đếm/đại từ không dấu trùng hình Latin (ba, nam, anh, em) KHÔNG bị đổi thành "."', () => {
  // Lưu ý: "hai chấm" tự nó là cụm ký hiệu (→ ":"), không dùng trong ca này để tránh nhầm với test đó.
  for (const input of ['ba chấm nam', 'anh chấm em đi chơi']) {
    assert.equal(applyDevspeech(input).text, input, input);
  }
});

test('đặt tên biến: snake_case, camelCase, PascalCase, kebab-case', () => {
  assert.equal(applyDevspeech('viết thường nối gạch dưới a b c').text, 'a_b_c');
  assert.equal(applyDevspeech('viết hoa nối a b c').text, 'aBC');
  assert.equal(applyDevspeech('camel case a b c').text, 'aBC');
  assert.equal(applyDevspeech('pascal case a b c').text, 'ABC');
  assert.equal(applyDevspeech('kebab case a b c').text, 'a-b-c');
});

test('đặt tên biến chèn giữa câu: dừng ở dấu câu, phần trước/sau giữ nguyên', () => {
  const r = applyDevspeech('tạo biến viết thường nối gạch dưới a b c, rồi dùng nó');
  assert.equal(r.text, 'tạo biến a_b_c, rồi dùng nó');
});

test('đặt tên biến không có dấu câu phân tách: nuốt luôn phần còn lại của câu (giới hạn đã biết)', () => {
  const r = applyDevspeech('viết thường nối gạch dưới a b c rồi dùng nó');
  assert.equal(r.text, 'a_b_c_rôi_dung_no');
});

test('applied ghi type devspeech', () => {
  const r = applyDevspeech('a gạch dưới b');
  assert.deepEqual(r.applied, [{ type: 'devspeech', from: 'gạch dưới', to: '_' }]);
});

test('không có cụm devspeech nào ⇒ giữ nguyên, applied rỗng', () => {
  const r = applyDevspeech('đây là một câu tiếng việt bình thường');
  assert.equal(r.text, 'đây là một câu tiếng việt bình thường');
  assert.deepEqual(r.applied, []);
});
