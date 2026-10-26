import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdtempSync, rmSync, readFileSync, writeFileSync, statSync, existsSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { createStatsStore, countWords, dayKey } from './stats.js';

function tmp(t) {
  const dir = mkdtempSync(join(tmpdir(), 'vflow-post-stats-'));
  t.after(() => rmSync(dir, { recursive: true, force: true }));
  return dir;
}

test('countWords: đếm theo khoảng trắng, loại token chỉ có dấu câu', () => {
  assert.equal(countWords(''), 0);
  assert.equal(countWords('   '), 0);
  assert.equal(countWords('anh đi plôi bản mới'), 5);
  assert.equal(countWords('Xin chào, thế giới!'), 4); // "chào," và "giới!" vẫn tính (có chữ)
  assert.equal(countWords('...'), 0); // chỉ dấu câu, không chữ/số
  assert.equal(countWords('deploy 123 ...'), 2);
  assert.equal(countWords(null), 0);
});

test('chưa có history/stats ⇒ rỗng, backfilled:true ngay (không có gì để backfill)', (t) => {
  const dir = tmp(t);
  const store = createStatsStore({ path: join(dir, 'stats.json'), historyPath: join(dir, 'history.jsonl') });
  const s = store.summary({ weeks: 1 });
  assert.equal(s.since, null);
  assert.equal(s.total_words, 0);
  assert.equal(s.avg_wpm, null);
  assert.equal(s.current_streak, 0);
  assert.equal(s.best_streak, 0);
  assert.deepEqual(s.top_apps, []);
  const raw = JSON.parse(readFileSync(join(dir, 'stats.json'), 'utf8'));
  assert.equal(raw.backfilled, true);
});

test('summary(): luôn trả week_start:"monday" (contract/engine-api.md mục Thống kê)', (t) => {
  const dir = tmp(t);
  const store = createStatsStore({ path: join(dir, 'stats.json'), historyPath: join(dir, 'history.jsonl') });
  assert.equal(store.summary({ weeks: 1 }).week_start, 'monday');
  assert.equal(store.summary({ weeks: 16 }).week_start, 'monday');
});

test('record(): cộng words/audio_ms/count đúng ngày hôm nay, theo app; không chứa văn bản', (t) => {
  const dir = tmp(t);
  const path = join(dir, 'stats.json');
  const fixedNow = new Date(2026, 9, 27, 10, 0, 0); // 2026-10-27 local
  const store = createStatsStore({ path, historyPath: join(dir, 'history.jsonl'), now: () => fixedNow });
  store.record({ text: 'xin chào thế giới', audioMs: 2000, app: 'com.apple.Terminal' });
  store.record({ text: 'một câu nữa', audioMs: 1500, app: 'com.apple.Terminal' });
  store.record({ text: 'không app', audioMs: 500 }); // thiếu app ⇒ "unknown"
  const s = store.summary({ weeks: 1 });
  const today = s.days.find((d) => d.date === dayKey(fixedNow));
  assert.equal(today.words, 4 + 3 + 2);
  assert.equal(today.count, 3);
  assert.equal(today.audio_ms, 4000);
  assert.ok(s.top_apps.some((a) => a.app === 'com.apple.Terminal' && a.words === 7));
  assert.ok(s.top_apps.some((a) => a.app === 'unknown' && a.words === 2));
  // Không ghi văn bản/âm thanh ra tệp, chỉ bộ đếm.
  const raw = readFileSync(path, 'utf8');
  assert.ok(!raw.includes('xin chào'));
  assert.ok(!raw.includes('câu nữa'));
  if (process.platform !== 'win32') assert.equal(statSync(path).mode & 0o777, 0o600);
});

test('backfill từ history.jsonl: đếm giống record(), bỏ Command Mode, bỏ dòng hỏng (đếm, không crash)', (t) => {
  const dir = tmp(t);
  const historyPath = join(dir, 'history.jsonl');
  const lines = [
    JSON.stringify({ id: 'h_1', at: '2026-10-20T03:00:00.000Z', mode: 'normal', model: 'zipformer-vi-30m', text_raw: 'r', text: 'hai từ đây', audio_ms: 1000, app: 'com.apple.Terminal' }),
    JSON.stringify({ id: 'h_2', at: '2026-10-20T04:00:00.000Z', mode: 'clean', model: 'zipformer-vi-30m', text_raw: 'r', text: 'một', audio_ms: 500 }),
    JSON.stringify({ id: 'h_3', at: '2026-10-20T05:00:00.000Z', mode: 'command:edit', model: '', text_raw: 'sửa lại', text: 'đã sửa', audio_ms: 300 }), // bỏ: Command Mode
    JSON.stringify({ id: 'h_4', at: '2026-10-20T06:00:00.000Z', mode: 'normal', model: 'zipformer-vi-30m', text_raw: 'r', text: '', audio_ms: 100 }), // bỏ: rỗng
    '{ broken json', // hỏng
    JSON.stringify({ id: 'h_5', mode: 'normal', model: 'm', text_raw: 'r', text: 'thiếu at' }), // hỏng: thiếu "at"
    '',
  ].join('\n');
  writeFileSync(historyPath, lines + '\n');

  const logs = [];
  const store = createStatsStore({ path: join(dir, 'stats.json'), historyPath, log: (e) => logs.push(e) });
  const s = store.summary({ weeks: 260 });
  assert.equal(s.total_words, 3 + 1); // "hai từ đây"=3, "một"=1
  assert.equal(s.total_count, 2);
  assert.ok(s.top_apps.some((a) => a.app === 'com.apple.Terminal'));
  assert.ok(s.top_apps.some((a) => a.app === 'unknown'));
  assert.ok(logs.some((e) => e.event === 'stats_backfill_corrupt_lines' && e.count === 2));
});

test('backfill chỉ chạy MỘT LẦN: có stats.json rồi thì không đọc lại history dù history đổi', (t) => {
  const dir = tmp(t);
  const historyPath = join(dir, 'history.jsonl');
  const path = join(dir, 'stats.json');
  writeFileSync(historyPath, JSON.stringify({ id: 'h_1', at: '2026-10-20T03:00:00.000Z', mode: 'normal', model: 'm', text_raw: 'r', text: 'một hai ba', audio_ms: 1000 }) + '\n');
  const store1 = createStatsStore({ path, historyPath });
  assert.equal(store1.summary({ weeks: 260 }).total_words, 3);

  writeFileSync(historyPath, JSON.stringify({ id: 'h_2', at: '2026-10-21T03:00:00.000Z', mode: 'normal', model: 'm', text_raw: 'r', text: 'bốn năm sáu bảy', audio_ms: 1000 }) + '\n');
  const store2 = createStatsStore({ path, historyPath });
  assert.equal(store2.summary({ weeks: 260 }).total_words, 3, 'không backfill lại — stats.json đã có rồi');
});

test('avg_wpm: null khi audio dưới 60s, có giá trị đúng khi đủ', (t) => {
  const dir = tmp(t);
  const now = new Date(2026, 9, 27);
  const store = createStatsStore({ path: join(dir, 'stats.json'), historyPath: join(dir, 'history.jsonl'), now: () => now });
  store.record({ text: 'một hai ba bốn năm', audioMs: 59999, app: 'a' });
  assert.equal(store.summary().avg_wpm, null);
  // Thêm 1 phút nữa ⇒ đủ 60s+; tổng words=10, audio=119999ms≈2 phút ⇒ wpm = 10/(119999/60000) ≈ 5.
  store.record({ text: 'sáu bảy tám chín mười', audioMs: 60000, app: 'a' });
  const s = store.summary();
  assert.equal(s.avg_wpm, Math.round(10 / (119999 / 60000)));
});

test('current_streak: chưa mất chuỗi trong ngày hôm nay nếu hôm nay chưa có dữ liệu', (t) => {
  const dir = tmp(t);
  const path = join(dir, 'stats.json');
  let now = new Date(2026, 9, 25); // 25/10
  const store = createStatsStore({ path, historyPath: join(dir, 'history.jsonl'), now: () => now });
  store.record({ text: 'a b', app: 'x' });
  now = new Date(2026, 9, 26); // 26/10
  store.record({ text: 'c d', app: 'x' });
  now = new Date(2026, 9, 27); // 27/10 — hôm nay, CHƯA record gì
  const s = store.summary({ weeks: 2 });
  assert.equal(s.current_streak, 2, 'hôm nay chưa có dữ liệu nhưng chuỗi hôm qua vẫn được tính là đang chạy');

  // Nếu hôm qua (26/10) cũng trống thì chuỗi phải là 0.
  now = new Date(2026, 9, 29); // 29/10 — cách ngày có dữ liệu cuối (26/10) hơn 1 ngày
  assert.equal(store.summary({ weeks: 2 }).current_streak, 0);
});

test('best_streak: chuỗi dài nhất mọi thời, không bị current_streak ngắn hơn che mất; qua ranh giới tháng', (t) => {
  const dir = tmp(t);
  const path = join(dir, 'stats.json');
  let now = new Date(2026, 9, 29); // 29/10
  const store = createStatsStore({ path, historyPath: join(dir, 'history.jsonl'), now: () => now });
  const days = [29, 30, 31]; // tháng 10 (31 ngày) rồi qua tháng 11
  for (const d of days) { now = new Date(2026, 9, d); store.record({ text: 'a', app: 'x' }); }
  now = new Date(2026, 10, 1); store.record({ text: 'a', app: 'x' }); // 1/11
  now = new Date(2026, 10, 2); store.record({ text: 'a', app: 'x' }); // 2/11 — chuỗi 5 ngày liên tiếp qua ranh giới tháng
  now = new Date(2026, 10, 10); // hôm nay xa, chuỗi hiện tại = 0
  const s = store.summary({ weeks: 10 });
  assert.equal(s.best_streak, 5);
  assert.equal(s.current_streak, 0);
});

test('days[] đủ mọi ngày trong cửa sổ (kể cả không có dữ liệu), không có ngày tương lai', (t) => {
  const dir = tmp(t);
  const now = new Date(2026, 9, 27); // thứ Ba 27/10/2026
  const store = createStatsStore({ path: join(dir, 'stats.json'), historyPath: join(dir, 'history.jsonl'), now: () => now });
  const s = store.summary({ weeks: 1 });
  // Tuần chứa 27/10/2026 bắt đầu thứ Hai 26/10, nên weeks=1 ⇒ 26,27 (không có 28..1/11 vì là tương lai).
  assert.deepEqual(s.days.map((d) => d.date), ['2026-10-26', '2026-10-27']);
  assert.ok(s.days.every((d) => d.words === 0 && d.count === 0 && d.audio_ms === 0));
});

test('DELETE (clear): xoá hết, đặt backfilled:true để không tự backfill lại', (t) => {
  const dir = tmp(t);
  const historyPath = join(dir, 'history.jsonl');
  const path = join(dir, 'stats.json');
  writeFileSync(historyPath, JSON.stringify({ id: 'h_1', at: '2026-10-20T03:00:00.000Z', mode: 'normal', model: 'm', text_raw: 'r', text: 'một hai ba', audio_ms: 1000 }) + '\n');
  const store = createStatsStore({ path, historyPath });
  assert.equal(store.summary({ weeks: 260 }).total_words, 3);
  assert.deepEqual(store.clear(), { ok: true });
  assert.equal(store.summary({ weeks: 260 }).total_words, 0);

  const store2 = createStatsStore({ path, historyPath });
  assert.equal(store2.summary({ weeks: 260 }).total_words, 0, 'sau DELETE, không tự backfill lại dù history còn dữ liệu cũ');
});

test('tệp stats.json hỏng ⇒ lỗi rõ ràng, không âm thầm coi là rỗng', (t) => {
  const dir = tmp(t);
  const path = join(dir, 'stats.json');
  writeFileSync(path, '{ "days": not json');
  assert.throws(() => createStatsStore({ path, historyPath: join(dir, 'history.jsonl') }), { code: 'internal' });
});

test('stats_enabled không nằm trong module này (chỉ bộ đếm) — việc tắt do caller quyết định trước khi gọi record()', (t) => {
  // Bằng chứng gián tiếp: record() không nhận/đọc cờ enabled nào — caller (server) phải tự kiểm
  // settings.stats_enabled trước khi gọi. Test này chỉ xác nhận record() luôn cộng khi được gọi.
  const dir = tmp(t);
  const store = createStatsStore({ path: join(dir, 'stats.json'), historyPath: join(dir, 'history.jsonl') });
  store.record({ text: 'a b', app: 'x' });
  assert.equal(store.summary().total_words, 2);
});

test('exportDays/importDays/daysCount: xuất ra rồi nhập lại (merge) cộng dồn đúng, (replace) thay toàn bộ', (t) => {
  const dir = tmp(t);
  const now = new Date(2026, 9, 27);
  const a = createStatsStore({ path: join(dir, 'a.json'), historyPath: join(dir, 'h1.jsonl'), now: () => now });
  a.record({ text: 'một hai ba', audioMs: 1000, app: 'x' });
  assert.equal(a.daysCount(), 1);
  const dump = a.exportDays();
  assert.equal(dump.backfilled, true);
  assert.ok(dump.days[dayKey(now)]);

  const b = createStatsStore({ path: join(dir, 'b.json'), historyPath: join(dir, 'h2.jsonl'), now: () => now });
  b.record({ text: 'bốn năm', audioMs: 500, app: 'x' });
  b.importDays(dump.days, 'merge');
  const sb = b.summary({ weeks: 1 });
  const today = sb.days.find((d) => d.date === dayKey(now));
  assert.equal(today.words, 2 + 3); // "bốn năm"=2 (của b) + "một hai ba"=3 (nhập vào) cộng dồn
  assert.equal(today.count, 2);

  const c = createStatsStore({ path: join(dir, 'c.json'), historyPath: join(dir, 'h3.jsonl'), now: () => now });
  c.record({ text: 'sẽ bị thay hết', audioMs: 999, app: 'y' });
  c.importDays(dump.days, 'replace');
  const sc = c.summary({ weeks: 1 });
  assert.equal(sc.days.find((d) => d.date === dayKey(now)).words, 3, 'replace: dữ liệu cũ của c bị thay hoàn toàn bởi gói nhập');
});
