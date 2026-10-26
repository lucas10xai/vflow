import { test } from 'node:test';
import assert from 'node:assert/strict';
import { aggregate, containsTerm, editDistance, normalizeText, percentile, score, scoreBoth, termRecall } from './metrics.js';

test('normalizeText: NFC, chữ thường, bỏ dấu câu/ký hiệu/ký tự vô hình, gộp khoảng trắng', () => {
  const nfd = 'Tiếng Việt'.normalize('NFD');
  assert.equal(normalizeText(`  ${nfd},  CHÀO!!\tbạn​… "ok"  `), 'tiếng việt chào bạn ok');
  assert.equal(normalizeText('Đà Nẵng'), 'đà nẵng');
  assert.equal(normalizeText('a b\nc'), 'a b c');
  assert.equal(normalizeText(''), '');
  assert.equal(normalizeText(null), '');
});

test('normalizeText tones=false: bỏ đúng 5 dấu thanh, giữ dấu mũ/trăng/móc và đ', () => {
  assert.equal(normalizeText('Người ở đây rất đẹp, ổn chứ?', { tones: false }), 'ngươi ơ đây rât đep ôn chư');
  assert.equal(normalizeText('ả ã ạ á à ă â ư ơ đ', { tones: false }), 'a a a a a ă â ư ơ đ');
});

test('editDistance cơ bản và đối xứng', () => {
  assert.equal(editDistance([], []), 0);
  assert.equal(editDistance(['a'], []), 1);
  assert.equal(editDistance([], ['a', 'b']), 2);
  assert.equal(editDistance([...'kitten'], [...'sitting']), 3);
  assert.equal(editDistance([...'sitting'], [...'kitten']), 3);
});

test('score: khớp hoàn toàn sau chuẩn hoá ⇒ 0 dù khác hoa/thường, dấu câu, khoảng trắng', () => {
  const s = score('Xin chào, các bạn!', '  xin   CHÀO các bạn ');
  assert.equal(s.wer.rate, 0);
  assert.equal(s.cer.rate, 0);
});

test('score: thay/xoá/chèn từ tính đúng WER, CER không tính khoảng trắng', () => {
  const s = score('tôi đi học', 'tôi đi chơi về');
  assert.deepEqual(s.wer, { errors: 2, ref_len: 3, rate: 2 / 3 });
  // ký tự: "tôiđihọc"(8) vs "tôiđichơivề"(11): học→chơi + "về"
  assert.equal(s.cer.ref_len, 8);
  assert.equal(s.cer.errors, editDistance([...'tôiđihọc'], [...'tôiđichơivề']));
});

test('score: sai dấu thanh là lỗi khi nhạy dấu, không phải lỗi khi không nhạy dấu', () => {
  const b = scoreBoth('má tôi đi chợ', 'mà tối đi chợ');
  assert.equal(b.tone.wer.errors, 2);
  assert.equal(b.no_tone.wer.errors, 0);
  assert.equal(b.no_tone.cer.rate, 0);
  // Khác dấu mũ (ô ↔ o) vẫn là lỗi ở cả hai biến thể.
  assert.equal(scoreBoth('tôi', 'toi').no_tone.wer.errors, 1);
});

test('score: NFC/NFD cùng một chữ không bị tính lỗi', () => {
  const s = score('Nguyễn'.normalize('NFC'), 'Nguyễn'.normalize('NFD'));
  assert.equal(s.wer.errors, 0);
  assert.equal(s.cer.errors, 0);
});

test('score ca biên: kết quả rỗng ⇒ WER 100%; tham chiếu rỗng ⇒ rate null (không xác định) trừ khi cả hai rỗng', () => {
  assert.equal(score('xin chào', '').wer.rate, 1);
  assert.equal(score('xin chào', '').cer.rate, 1);
  const refEmpty = score('', 'có tiếng');
  assert.equal(refEmpty.wer.rate, null);
  assert.equal(refEmpty.wer.errors, 2);
  assert.equal(refEmpty.cer.rate, null);
  assert.equal(score('', '').wer.rate, 0);
  // Chỉ có dấu câu/ký tự lạ ⇒ coi như rỗng.
  assert.equal(score('...!?', '​ ').wer.rate, 0);
  assert.equal(score('🙂 ###', 'xin').wer.rate, null);
});

test('aggregate: tổng lỗi / tổng độ dài (không phải trung bình tỉ lệ từng câu)', () => {
  const a = aggregate([score('a b c d', 'a b c x'), score('e', 'f')]);
  assert.deepEqual(a.wer, { errors: 2, ref_len: 5, rate: 0.4 });
  assert.equal(aggregate([]).wer.rate, 0);
  assert.equal(aggregate([score('', 'x')]).wer.rate, null);
});

test('containsTerm: nguyên văn, không phân biệt hoa/thường, đúng ranh giới từ (kể cả chữ có dấu)', () => {
  assert.ok(containsTerm('anh deploy lên server', 'deploy'));
  assert.ok(containsTerm('Deploy xong rồi', 'deploy'));
  assert.ok(containsTerm('mở worktree.', 'worktree'));
  assert.ok(!containsTerm('redeployed', 'deploy'));
  assert.ok(!containsTerm('đi plôi', 'deploy'));
  assert.ok(!containsTerm('commitễ', 'commit'), 'chữ có dấu liền sau không phải ranh giới');
  assert.ok(containsTerm('dùng C++ nhé', 'C++'), 'ký tự đặc biệt trong thuật ngữ được thoát');
  assert.ok(!containsTerm('abc', ''));
});

test('termRecall: chỉ tính thuật ngữ có trong tham chiếu; không có thì rate null', () => {
  const r = termRecall([
    { ref: 'commit rồi deploy', hyp: 'com mít rồi deploy' },
    { ref: 'mở Orca', hyp: 'mở orca' },
    { ref: 'không có gì', hyp: 'deploy' },
  ], ['deploy', 'commit', 'orca', 'worktree']);
  assert.equal(r.expected, 3);
  assert.equal(r.hit, 2);
  assert.equal(r.rate, 2 / 3);
  assert.deepEqual(r.per_term.commit, { expected: 1, hit: 0 });
  assert.equal(termRecall([{ ref: 'xin chào', hyp: 'xin chào' }], ['deploy']).rate, null);
});

test('percentile: trung vị/p95 nội suy, mảng rỗng ⇒ null', () => {
  assert.equal(percentile([3, 1, 2], 0.5), 2);
  assert.equal(percentile([1, 2, 3, 4], 0.5), 2.5);
  assert.ok(Math.abs(percentile(Array.from({ length: 10 }, (_, i) => i + 1), 0.95) - 9.55) < 1e-9);
  assert.equal(percentile([], 0.5), null);
});
