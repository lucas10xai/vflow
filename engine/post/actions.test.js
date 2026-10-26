import test from 'node:test';
import assert from 'node:assert/strict';
import { extractEnterAction } from './actions.js';

test('cụm "nhấn enter"/"bấm enter" đúng ở cuối ⇒ cắt khỏi text, actions:["enter"]', () => {
  for (const [input, expectedText] of [
    ['anh gửi email cho khách rồi nhấn enter', 'anh gửi email cho khách rồi'],
    ['tạo thư mục mới bấm enter', 'tạo thư mục mới'],
    ['NHẤN ENTER', ''],
    ['bấm Enter.', ''],
    ['chạy lệnh deploy, bấm enter!', 'chạy lệnh deploy'],
    ['Ấn thử rồi Bấm Enter', 'Ấn thử rồi'],
  ]) {
    const r = extractEnterAction(input);
    assert.equal(r.text, expectedText, input);
    assert.deepEqual(r.actions, ['enter'], input);
  }
});

test('cụm "bấm enter" KHÔNG ở cuối ⇒ không kích hoạt (giữ nguyên chữ)', () => {
  for (const input of [
    'tôi sẽ bấm enter sau',
    'bấm enter rồi gõ tiếp nội dung khác',
    'nhấn enter để xác nhận việc này',
  ]) {
    const r = extractEnterAction(input);
    assert.equal(r.text, input);
    assert.deepEqual(r.actions, []);
  }
});

test('chỉ cụm CUỐI CÙNG được xét khi lặp lại', () => {
  const r = extractEnterAction('nhấn enter rồi lại nhấn enter');
  assert.equal(r.text, 'nhấn enter rồi lại');
  assert.deepEqual(r.actions, ['enter']);
});

test('actions_enabled=false ⇒ giữ nguyên chữ, không có hành động', () => {
  const r = extractEnterAction('anh gửi email rồi nhấn enter', { actionsEnabled: false });
  assert.equal(r.text, 'anh gửi email rồi nhấn enter');
  assert.deepEqual(r.actions, []);
});

test('không có cụm enter ⇒ giữ nguyên, actions rỗng', () => {
  const r = extractEnterAction('chỉ là một câu bình thường không có gì đặc biệt');
  assert.equal(r.text, 'chỉ là một câu bình thường không có gì đặc biệt');
  assert.deepEqual(r.actions, []);
});

test('chuỗi quá ngắn (một từ, hoặc rỗng) ⇒ không kích hoạt', () => {
  assert.deepEqual(extractEnterAction('enter').actions, []);
  assert.deepEqual(extractEnterAction('').actions, []);
});
