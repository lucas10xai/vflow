/** Test thuần (không cần sherpa-onnx/model thật) cho các hàm hỗ trợ của provider cục bộ. */
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { normalizeModelText } from './local.js';

test('normalizeModelText: engine transducer thô (zipformer) ⇒ đổi về chữ thường', () => {
  assert.equal(normalizeModelText('ANH ĐI DEPLOY', true), 'anh đi deploy');
  assert.equal(normalizeModelText('  nhiều   khoảng   trắng  ', true), 'nhiều khoảng trắng');
});

test('normalizeModelText: Whisper/SenseVoice đã tự viết hoa/dấu câu ⇒ GIỮ NGUYÊN, cả với câu tiếng Việt', () => {
  // Bug đã gặp: hàm cũ khoá theo "language" yêu cầu (vi/en/…) thay vì theo loại engine, nên một
  // câu tiếng Việt do Whisper trả về (đã viết hoa, có dấu câu đúng) bị ép về chữ thường mất hết.
  assert.equal(normalizeModelText('Anh đi deploy bản mới nhé.', false), 'Anh đi deploy bản mới nhé.');
  assert.equal(normalizeModelText('Please review the PR.', false), 'Please review the PR.');
  // Vẫn gọn khoảng trắng dù giữ hoa/thường.
  assert.equal(normalizeModelText('  Hello   World.  ', false), 'Hello World.');
});

test('normalizeModelText: mặc định (không truyền cờ) là transducer thô, dùng cho đường streaming', () => {
  assert.equal(normalizeModelText('XIN CHÀO'), 'xin chào');
});
