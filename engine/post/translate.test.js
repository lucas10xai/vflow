import test from 'node:test';
import assert from 'node:assert/strict';
import { checkTranslateGuard } from './translate.js';

test('guard dịch chặn lời dẫn, nguyên văn tiếng Việt và câu trả lời rỗng', () => {
  assert.equal(checkTranslateGuard('xin chào bạn hôm nay', 'Here is the translation: Hello', 'en'), false);
  assert.equal(checkTranslateGuard('xin chào bạn hôm nay', 'Xin chào bạn hôm nay', 'en'), false);
  assert.equal(checkTranslateGuard('xin chào bạn hôm nay', '', 'en'), false);
});

test('guard dịch nhận bản dịch hợp lý, gồm cả ngôn ngữ CJK ngắn hơn', () => {
  assert.equal(checkTranslateGuard('xin chào bạn hôm nay', 'Hello my friend today', 'en'), true);
  assert.equal(checkTranslateGuard('xin chào bạn hôm nay', '你好朋友', 'zh'), true);
});
