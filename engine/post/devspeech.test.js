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

test('đặt tên biến không có dấu câu phân tách: dừng ở từ nối "rồi", giữ nguyên phần sau', () => {
  const r = applyDevspeech('viết thường nối gạch dưới a b c rồi dùng nó');
  assert.equal(r.text, 'a_b_c rồi dùng nó');
});

test('bug thật: "sửa cái biến viết thường nối gạch dưới user name rồi commit lại" không nuốt "rồi commit lại"', () => {
  const r = applyDevspeech('sửa cái biến viết thường nối gạch dưới user name rồi commit lại');
  assert.equal(r.text, 'sửa cái biến user_name rồi commit lại');
});

test('đặt tên biến dừng ở các từ nối/chuyển ý thông dụng khác (và, thì, xong, để, cho, nhé, nữa, hay, hoặc, là, mà, nhưng, sau đó)', () => {
  const CASES = [
    ['viết thường nối gạch dưới a b và c đi', 'a_b và c đi'],
    ['viết thường nối gạch dưới a b thì sao', 'a_b thì sao'],
    ['viết thường nối gạch dưới a b xong rồi', 'a_b xong rồi'],
    ['viết thường nối gạch dưới a b để dùng', 'a_b để dùng'],
    ['viết thường nối gạch dưới a b cho tôi', 'a_b cho tôi'],
    ['viết thường nối gạch dưới a b nhé anh', 'a_b nhé anh'],
    ['viết thường nối gạch dưới a b nữa thôi', 'a_b nữa thôi'],
    ['viết thường nối gạch dưới a b hay là', 'a_b hay là'],
    ['viết thường nối gạch dưới a b hoặc c', 'a_b hoặc c'],
    ['viết thường nối gạch dưới a b là xong', 'a_b là xong'],
    ['viết thường nối gạch dưới a b mà thôi', 'a_b mà thôi'],
    ['viết thường nối gạch dưới a b nhưng thôi', 'a_b nhưng thôi'],
    ['viết thường nối gạch dưới a b sau đó dùng', 'a_b sau đó dùng'],
  ];
  for (const [input, expected] of CASES) assert.equal(applyDevspeech(input).text, expected, input);
});

test('đặt tên biến: chỉ nuốt tối đa 6 từ, từ thứ 7 trở đi giữ nguyên dù không gặp từ nối/dấu câu', () => {
  const r = applyDevspeech('viết thường nối gạch dưới a b c d e f g h i');
  assert.equal(r.text, 'a_b_c_d_e_f g h i');
});

test('đặt tên biến: đúng 6 từ không có phần dư vẫn ra tên đủ 6 từ', () => {
  const r = applyDevspeech('viết thường nối gạch dưới a b c d e f');
  assert.equal(r.text, 'a_b_c_d_e_f');
});

test('ca nhập nhằng: từ nối xuất hiện ngay sau cụm trigger (không có đối số nào trước nó) ⇒ không áp quy tắc, giữ nguyên văn', () => {
  for (const input of ['camel case rồi thôi', 'pascal case là xong']) {
    assert.equal(applyDevspeech(input).text, input, input);
  }
});

test('ca nhập nhằng: từ nối đứng xa sau nhiều từ khác không bị hiểu lầm là một phần tên biến ở câu không có cụm trigger', () => {
  for (const input of ['anh làm xong rồi báo em nhé', 'cái này để tôi làm cho']) {
    assert.equal(applyDevspeech(input).text, input, input);
  }
});

test('câu tiếng Anh dùng "camel case"/"pascal case" như danh từ mô tả (không phải lệnh) ⇒ không nuốt hết câu, từ nối tiếng Anh cũng là điểm dừng', () => {
  // Bug đã gặp: compound_stop_words chỉ có từ nối tiếng Việt, nên "camel case for props" trong câu
  // tiếng Anh thuần bị nuốt luôn "for props" và biến câu thành "...uses forProps" (sai hoàn toàn).
  assert.equal(applyDevspeech('This component uses camel case for props').text, 'This component uses camel case for props');
  assert.equal(applyDevspeech('We use kebab case in file names').text, 'We use kebab case in file names');
  // Lệnh thật vẫn hoạt động: dừng đúng tại từ nối tiếng Anh, phần còn lại giữ nguyên văn.
  const r = applyDevspeech('camel case get set is the style we use here');
  assert.equal(r.text, 'getSet is the style we use here');
  assert.deepEqual(r.applied, [{ type: 'devspeech', from: 'camel case get set', to: 'getSet' }]);
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
