// Kiểm bộ câu thoại mẫu: đúng 40 câu đánh số liên tục, mọi thuật ngữ trong terms.json có mặt,
// không có địa chỉ IP/khoá/email (bộ câu sẽ được đọc và ghi âm, phải sạch thông tin riêng).
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';

const read = (name) => readFileSync(new URL(name, import.meta.url), 'utf8');
const lines = read('./vi-en-40.txt').split('\n').filter((l) => l !== '');
const terms = JSON.parse(read('./terms.json'));

test('40 câu, đánh số 01–40 theo thứ tự, mỗi dòng một câu không rỗng', () => {
  assert.equal(lines.length, 40);
  lines.forEach((l, i) => {
    const m = /^(\d{2})\. (\S.*)$/.exec(l);
    assert.ok(m, `dòng ${i + 1} sai định dạng`);
    assert.equal(Number(m[1]), i + 1);
  });
});

test('mọi thuật ngữ trong terms.json xuất hiện (nguyên từ) trong ít nhất một câu, không trùng', () => {
  const text = lines.join('\n').toLowerCase();
  assert.equal(new Set(terms.map((t) => t.toLowerCase())).size, terms.length);
  for (const term of terms) {
    const esc = term.toLowerCase().replace(/[.*+?^${}()|[\]\\/]/g, '\\$&');
    assert.match(text, new RegExp(`(^|[^\\p{L}\\p{N}])${esc}($|[^\\p{L}\\p{N}])`, 'u'), term);
  }
});

test('không có IP, khoá, email hay mật khẩu', () => {
  const all = read('./vi-en-40.txt') + read('./terms.json');
  assert.doesNotMatch(all, /\b\d{1,3}(\.\d{1,3}){3}\b/);
  assert.doesNotMatch(all, /sk-[A-Za-z0-9]|[\w.-]+@[\w-]+\.\w|password|mật khẩu/i);
});
