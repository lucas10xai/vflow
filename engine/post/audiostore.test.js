import { test } from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { createAudioStore, ID_RE, parseWavHeader } from './audiostore.js';
import { encodeWav } from '../stt/audio.js';

const MB = 1024 * 1024;
const DAY = 86400000;

/** Đồng hồ chỉnh tay + cài đặt giả (ngân sách/hạn ngày đặt thẳng, không qua miền 50–2000 MB của settings). */
function setup({ mb = 1, days = 7, start = Date.parse('2026-10-20T00:00:00Z') } = {}) {
  const home = fs.mkdtempSync(path.join(os.tmpdir(), 'vflow-audiostore-'));
  const clock = { t: start };
  const cfg = { audio_history: true, audio_history_mb: mb, audio_history_days: days };
  const logs = [];
  const open = (extra = {}) => createAudioStore({
    home, settings: { get: () => cfg }, now: () => new Date(clock.t), log: (e) => logs.push(e), pruneIntervalMs: 0, ...extra,
  });
  return { home, clock, cfg, logs, open, dir: path.join(home, 'audio'), cleanup: () => fs.rmSync(home, { recursive: true, force: true }) };
}
const wavOf = (bytes) => Buffer.alloc(bytes, 7);
const files = (dir) => (fs.existsSync(dir) ? fs.readdirSync(dir).sort() : []);

test('vượt ngân sách: đuổi tệp CŨ NHẤT trước, tệp mới nhất còn, tổng ≤ ngân sách, đĩa khớp mục lục', () => {
  const s = setup({ mb: 1 });
  try {
    const store = s.open();
    for (const id of ['a1', 'b2', 'c3']) {
      s.clock.t += 1000;
      assert.equal(store.write({ id, wav: wavOf(Math.round(0.4 * MB)), audioMs: 1000 }), true);
    }
    // 3 × 0,4 MB = 1,2 MB > 1 MB ⇒ a1 (cũ nhất) bị đuổi
    const list = store.list();
    assert.deepEqual(list.items.map((i) => i.id), ['c3', 'b2']);
    assert.ok(list.bytes <= MB);
    assert.equal(list.budget_bytes, MB);
    assert.deepEqual(files(s.dir).filter((f) => f.endsWith('.wav')), ['b2.wav', 'c3.wav']);
    assert.equal(store.pathFor('a1'), null);
  } finally { s.cleanup(); }
});

test('một tệp lớn hơn cả ngân sách: write trả false và KHÔNG để lại tệp (caller không được trả audio_id mồ côi)', () => {
  const s = setup({ mb: 1 });
  try {
    const store = s.open();
    assert.equal(store.write({ id: 'big', wav: wavOf(Math.round(1.5 * MB)), audioMs: 1000 }), false);
    assert.equal(store.list().count, 0);
    assert.deepEqual(files(s.dir).filter((f) => f.endsWith('.wav')), []);
  } finally { s.cleanup(); }
});

test('quá hạn ngày: tệp cũ hơn N ngày bị xoá khi ghi tệp mới và khi list() (không đợi khởi động lại)', () => {
  const s = setup({ mb: 100, days: 7 });
  try {
    const store = s.open();
    store.write({ id: 'old', wav: wavOf(1000), audioMs: 100 });
    s.clock.t += 6 * DAY;
    store.write({ id: 'mid', wav: wavOf(1000), audioMs: 100 });
    assert.deepEqual(store.list().items.map((i) => i.id).sort(), ['mid', 'old']); // 6 ngày: còn trong hạn
    s.clock.t += 2 * DAY; // old = 8 ngày, mid = 2 ngày
    assert.deepEqual(store.list().items.map((i) => i.id), ['mid']);
    assert.deepEqual(files(s.dir).filter((f) => f.endsWith('.wav')), ['mid.wav']);
  } finally { s.cleanup(); }
});

test('quét lúc khởi động: xoá tệp quá hạn và tệp tạm *.tmp-* do ghi dở; WAV mồ côi không phân tích được ⇒ quarantine (KHÔNG xoá); giữ tệp hợp lệ; mục lục trỏ tệp mất bị loại', () => {
  const s = setup({ mb: 100, days: 7 });
  try {
    const first = s.open();
    first.write({ id: 'old', wav: wavOf(500), audioMs: 10 });
    s.clock.t += 5 * DAY;
    first.write({ id: 'keep', wav: wavOf(500), audioMs: 10 });
    first.write({ id: 'lost', wav: wavOf(500), audioMs: 10 });
    first.close();
    fs.writeFileSync(path.join(s.dir, 'orphan.wav'), wavOf(300));
    fs.writeFileSync(path.join(s.dir, 'x.wav.tmp-123-abcd'), wavOf(300)); // ghi dở do tiến trình bị ngắt
    fs.writeFileSync(path.join(s.dir, 'index.json.tmp-9-ff'), '{}');
    fs.unlinkSync(path.join(s.dir, 'lost.wav')); // mục lục còn, tệp mất
    s.clock.t += 3 * DAY; // old = 8 ngày (quá hạn), keep = 3 ngày

    const second = s.open(); // khởi động lại ⇒ quét
    assert.deepEqual(second.list().items.map((i) => i.id), ['keep']);
    assert.deepEqual(files(s.dir), ['index.json', 'keep.wav', 'quarantine']);
    assert.deepEqual(files(path.join(s.dir, 'quarantine')), ['orphan.wav']);
    assert.equal(fs.statSync(path.join(s.dir, 'quarantine', 'orphan.wav')).size, 300); // nội dung còn nguyên
    assert.equal(second.list().quarantined, 1);
    // mục lục trên đĩa phản ánh đúng sau quét (khởi động lần ba không "hồi sinh" gì)
    const third = s.open();
    assert.deepEqual(third.list().items.map((i) => i.id), ['keep']);
  } finally { s.cleanup(); }
});

test('đổi cài đặt nhỏ ngân sách: lần quét kế tiếp (list) đuổi cho vừa, kể cả khi audio_history đã tắt', () => {
  const s = setup({ mb: 10 });
  try {
    const store = s.open();
    for (const id of ['a', 'b', 'c']) { s.clock.t += 1000; store.write({ id, wav: wavOf(Math.round(0.4 * MB)), audioMs: 1 }); }
    assert.equal(store.list().count, 3);
    s.cfg.audio_history = false;
    s.cfg.audio_history_mb = 1;
    assert.deepEqual(store.list().items.map((i) => i.id), ['c', 'b']);
    assert.equal(store.list().enabled, false);
  } finally { s.cleanup(); }
});

test('cài đặt không đọc được: bỏ lần quét, KHÔNG xoá gì và ghi log mã lỗi (không đoán giá trị)', () => {
  const s = setup({ mb: 100 });
  try {
    const store = s.open();
    store.write({ id: 'a', wav: wavOf(500), audioMs: 1 });
    store.close();
    const broken = createAudioStore({
      home: s.home, settings: { get: () => { const e = new Error('hỏng'); e.code = 'bad_config'; throw e; } },
      now: () => new Date(s.clock.t + 400 * DAY), log: (e) => s.logs.push(e), pruneIntervalMs: 0,
    });
    assert.ok(s.logs.some((e) => e.event === 'audio_prune_skipped' && e.code === 'bad_config'));
    assert.deepEqual(files(s.dir).filter((f) => f.endsWith('.wav')), ['a.wav']);
    broken.close();
  } finally { s.cleanup(); }
});

test('quyền: thư mục audio 0700, tệp WAV và index.json 0600 (kể cả khi thư mục có sẵn với quyền rộng)', { skip: process.platform === 'win32' }, () => {
  const s = setup();
  try {
    fs.mkdirSync(s.dir, { mode: 0o755 });
    fs.chmodSync(s.dir, 0o755);
    const store = s.open();
    store.write({ id: 'p1', wav: wavOf(100), audioMs: 1 });
    assert.equal(fs.statSync(s.dir).mode & 0o777, 0o700);
    assert.equal(fs.statSync(path.join(s.dir, 'p1.wav')).mode & 0o777, 0o600);
    assert.equal(fs.statSync(path.join(s.dir, 'index.json')).mode & 0o777, 0o600);
  } finally { s.cleanup(); }
});

test('id độc hại (path traversal, dấu chấm, rỗng) bị từ chối ở mọi thao tác, không ghi/đọc/xoá ngoài thư mục audio', () => {
  const s = setup();
  try {
    const store = s.open();
    const outside = path.join(s.home, 'secret.wav');
    fs.writeFileSync(outside, 'x');
    for (const bad of ['../secret', '..', 'a/b', 'a\\b', 'a.b', '', 'x.wav']) {
      assert.equal(ID_RE.test(bad), false, bad);
      assert.equal(store.write({ id: bad, wav: wavOf(10), audioMs: 1 }), false, `write ${bad}`);
      assert.equal(store.pathFor(bad), null, `pathFor ${bad}`);
      assert.deepEqual(store.remove(bad), { ok: false }, `remove ${bad}`);
    }
    assert.equal(fs.readFileSync(outside, 'utf8'), 'x');
    assert.equal(store.list().count, 0);
  } finally { s.cleanup(); }
});

test('remove/removeAll xoá cả tệp lẫn mục lục; ghi đè cùng id không nhân đôi', () => {
  const s = setup({ mb: 100 });
  try {
    const store = s.open();
    store.write({ id: 'a', wav: wavOf(100), audioMs: 1 });
    store.write({ id: 'a', wav: wavOf(200), audioMs: 1 });
    store.write({ id: 'b', wav: wavOf(100), audioMs: 1 });
    assert.equal(store.list().count, 2);
    assert.equal(store.list().bytes, 300);
    assert.deepEqual(store.remove('a'), { ok: true });
    assert.deepEqual(store.remove('a'), { ok: false });
    assert.deepEqual(files(s.dir).filter((f) => f.endsWith('.wav')), ['b.wav']);
    assert.deepEqual(store.removeAll(), { ok: true, deleted: 1 });
    assert.deepEqual(files(s.dir).filter((f) => f.endsWith('.wav')), []);
    assert.equal(store.list().count, 0);
  } finally { s.cleanup(); }
});

// ------------------------------------------------------------------------------------------------
// AN TOÀN DỮ LIỆU: mục lục hỏng/thiếu KHÔNG BAO GIỜ được làm mất WAV hợp lệ (P4/P6).
// ------------------------------------------------------------------------------------------------

/** WAV hợp lệ thật (PCM 16-bit mono 16 kHz) dài `seconds` giây, nội dung khác nhau theo `seed`. */
function realWav(seconds, seed = 1) {
  const x = new Float32Array(Math.round(16000 * seconds));
  for (let i = 0; i < x.length; i++) x[i] = 0.2 * Math.sin((i * seed) / 40);
  return Buffer.from(encodeWav(x, 16000));
}
const sha = (p) => fs.readFileSync(p).toString('base64');

/** Ghi 3 WAV hợp lệ qua store, đóng store, trả về { ids, snapshot: id -> nội dung } để so sánh sau khi mục lục bị phá. */
function seed3(s) {
  const store = s.open();
  const snapshot = {};
  const ids = ['t_one', 't_two', 't_three'];
  ids.forEach((id, i) => {
    s.clock.t += 1000;
    const wav = realWav(1 + i, i + 2);
    assert.equal(store.write({ id, wav, audioMs: (1 + i) * 1000, app: 'com.apple.Terminal', mode: 'dev' }), true);
    snapshot[id] = wav.toString('base64');
  });
  store.close();
  return { ids, snapshot };
}
const assertAllIntact = (s, ids, snapshot) => {
  for (const id of ids) assert.equal(sha(path.join(s.dir, `${id}.wav`)), snapshot[id], `${id}.wav bị mất/đổi`);
};

for (const [label, content] of [
  ['JSON sai cú pháp', '{"items": [ {"id": "t_one", '],
  ['tệp rỗng 0 byte', ''],
  ['JSON hợp lệ nhưng sai hình dạng (items là chuỗi)', '{"items":"x"}'],
  ['JSON hợp lệ nhưng là mảng trần', '[]'],
  ['null', 'null'],
]) {
  test(`mục lục hỏng (${label}): KHÔNG xoá WAV nào, dựng lại mục lục từ đĩa, báo index_rebuilt, ghi lại nguyên tử 0600`, { skip: false }, () => {
    const s = setup({ mb: 100, days: 30 });
    try {
      const { ids, snapshot } = seed3(s);
      fs.writeFileSync(path.join(s.dir, 'index.json'), content);
      const store = s.open();
      const list = store.list();
      assert.deepEqual(list.items.map((i) => i.id).sort(), [...ids].sort());
      assertAllIntact(s, ids, snapshot);
      assert.equal(list.index_rebuilt, true);
      assert.equal(list.recovered, 3);
      assert.equal(list.quarantined, 0);
      // audio_ms lấy từ header (1/2/3 giây), bytes từ kích thước thật
      const by = Object.fromEntries(list.items.map((i) => [i.id, i]));
      assert.equal(by.t_one.audio_ms, 1000);
      assert.equal(by.t_two.audio_ms, 2000);
      assert.equal(by.t_three.audio_ms, 3000);
      assert.equal(by.t_two.bytes, fs.statSync(path.join(s.dir, 't_two.wav')).size);
      // `at` từ mtime của tệp
      assert.equal(by.t_one.at, new Date(fs.statSync(path.join(s.dir, 't_one.wav')).mtimeMs).toISOString());
      // log có mã lý do, KHÔNG có nội dung
      const ev = s.logs.find((e) => e.event === 'audio_index_recovered');
      assert.ok(ev && ev.recovered === 3 && typeof ev.reason === 'string');
      assert.ok(!JSON.stringify(s.logs).includes('t_one'), 'log không được chứa id/nội dung');
      // mục lục đã được GHI LẠI hợp lệ
      const onDisk = JSON.parse(fs.readFileSync(path.join(s.dir, 'index.json'), 'utf8'));
      assert.equal(onDisk.items.length, 3);
      if (process.platform !== 'win32') assert.equal(fs.statSync(path.join(s.dir, 'index.json')).mode & 0o777, 0o600);
      assert.ok(!files(s.dir).some((f) => f.includes('.tmp-')));
      // khởi động lần nữa: mục lục đã lành ⇒ không còn báo dựng lại
      store.close();
      const again = s.open().list();
      assert.equal(again.index_rebuilt, false);
      assert.equal(again.count, 3);
    } finally { s.cleanup(); }
  });
}

test('mục lục thiếu hẳn (index.json bị xoá) nhưng WAV còn: nhận lại hết, index_rebuilt=true', () => {
  const s = setup({ mb: 100, days: 30 });
  try {
    const { ids, snapshot } = seed3(s);
    fs.unlinkSync(path.join(s.dir, 'index.json'));
    const list = s.open().list();
    assert.equal(list.count, 3);
    assert.equal(list.index_rebuilt, true);
    assertAllIntact(s, ids, snapshot);
  } finally { s.cleanup(); }
});

test('mục lục thiếu MỘT mục cho tệp có thật: tệp được nhận lại (không bị coi là mồ côi và xoá); các mục khác giữ app/mode', () => {
  const s = setup({ mb: 100, days: 30 });
  try {
    const { ids, snapshot } = seed3(s);
    const p = path.join(s.dir, 'index.json');
    const idx = JSON.parse(fs.readFileSync(p, 'utf8'));
    idx.items = idx.items.filter((e) => e.id !== 't_two');
    fs.writeFileSync(p, JSON.stringify(idx));
    const store = s.open();
    const list = store.list();
    assert.deepEqual(list.items.map((i) => i.id).sort(), [...ids].sort());
    assert.equal(list.recovered, 1);
    assert.equal(list.index_rebuilt, false); // mục lục đọc được, chỉ thiếu mục
    assertAllIntact(s, ids, snapshot);
    assert.equal(store.exportEntries().find((e) => e.id === 't_one').app, 'com.apple.Terminal'); // mục còn nguyên thông tin
  } finally { s.cleanup(); }
});

test('một mục trong mục lục sai kiểu/thiếu trường: bỏ MỤC đó nhưng tệp WAV của nó được nhận lại từ đĩa', () => {
  const s = setup({ mb: 100, days: 30 });
  try {
    const { ids, snapshot } = seed3(s);
    const p = path.join(s.dir, 'index.json');
    const idx = JSON.parse(fs.readFileSync(p, 'utf8'));
    idx.items[0].bytes = 'nhiều';
    delete idx.items[1].at;
    fs.writeFileSync(p, JSON.stringify(idx));
    const list = s.open().list();
    assert.deepEqual(list.items.map((i) => i.id).sort(), [...ids].sort());
    assert.equal(list.recovered, 2);
    assertAllIntact(s, ids, snapshot);
    assert.equal(list.items.find((i) => i.id === idx.items[0].id).bytes, fs.statSync(path.join(s.dir, `${idx.items[0].id}.wav`)).size);
  } finally { s.cleanup(); }
});

test('mục lục có mục mà tệp đã mất: bỏ mục đó, các tệp còn lại giữ nguyên, mục lục được ghi lại', () => {
  const s = setup({ mb: 100, days: 30 });
  try {
    const { snapshot } = seed3(s);
    fs.unlinkSync(path.join(s.dir, 't_two.wav'));
    const list = s.open().list();
    assert.deepEqual(list.items.map((i) => i.id).sort(), ['t_one', 't_three']);
    assertAllIntact(s, ['t_one', 't_three'], snapshot);
    assert.deepEqual(JSON.parse(fs.readFileSync(path.join(s.dir, 'index.json'), 'utf8')).items.map((e) => e.id).sort(), ['t_one', 't_three']);
  } finally { s.cleanup(); }
});

test('tệp .wav rác (0 byte, byte ngẫu nhiên, RIFF cụt, sai định dạng 8 kHz/stereo): chuyển vào quarantine/ 0700, KHÔNG xoá, KHÔNG tính ngân sách/danh sách', () => {
  const s = setup({ mb: 100, days: 30 });
  try {
    const { ids, snapshot } = seed3(s);
    fs.unlinkSync(path.join(s.dir, 'index.json')); // cùng lúc mục lục mất
    const junk = {
      'rong.wav': Buffer.alloc(0),
      'ngaunhien.wav': Buffer.from(Array.from({ length: 777 }, (_, i) => (i * 131) & 0xff)),
      'cut.wav': realWav(1).subarray(0, 30),
      'khong-data.wav': realWav(1).subarray(0, 36),
      'tan-so-8k.wav': Buffer.from(encodeWav(new Float32Array(8000).fill(0.1), 8000)),
      'stereo.wav': Buffer.from(encodeWav(new Float32Array(32000).fill(0.1), 16000, 2)),
    };
    for (const [n, b] of Object.entries(junk)) fs.writeFileSync(path.join(s.dir, n), b);
    const store = s.open();
    const list = store.list();
    assert.deepEqual(list.items.map((i) => i.id).sort(), [...ids].sort());
    assert.equal(list.quarantined, Object.keys(junk).length);
    assert.equal(list.bytes, ids.reduce((sum, id) => sum + fs.statSync(path.join(s.dir, `${id}.wav`)).size, 0)); // rác không vào ngân sách
    assertAllIntact(s, ids, snapshot);
    const q = path.join(s.dir, 'quarantine');
    assert.deepEqual(files(q), Object.keys(junk).sort());
    for (const [n, b] of Object.entries(junk)) assert.ok(fs.readFileSync(path.join(q, n)).equals(b), `${n} bị đổi`); // KHÔNG xoá/sửa
    if (process.platform !== 'win32') assert.equal(fs.statSync(q).mode & 0o777, 0o700);
    for (const n of Object.keys(junk)) assert.ok(!fs.existsSync(path.join(s.dir, n)), `${n} còn ở thư mục chính`);
    assert.equal(store.pathFor('rong'), null);
    assert.ok(!store.exportEntries().some((e) => e.id in { rong: 1, ngaunhien: 1 }));
    // khởi động lại không đụng quarantine và không nhận lại rác
    store.close();
    const again = s.open().list();
    assert.equal(again.quarantined, Object.keys(junk).length);
    assert.equal(again.count, 3);
  } finally { s.cleanup(); }
});

test('sau khi dựng lại mục lục, ngân sách và hạn ngày vẫn chạy (theo mtime): chỉ tệp quá hạn/vượt ngân sách bị đuổi, không xoá lan', () => {
  const s = setup({ mb: 100, days: 7 });
  try {
    const { snapshot } = seed3(s);
    // t_one cũ 30 ngày (mtime), phần còn lại mới
    const old = new Date(s.clock.t - 30 * DAY);
    fs.utimesSync(path.join(s.dir, 't_one.wav'), old, old);
    fs.writeFileSync(path.join(s.dir, 'index.json'), '{hỏng');
    const list = s.open().list();
    assert.deepEqual(list.items.map((i) => i.id).sort(), ['t_three', 't_two']);
    assert.ok(!fs.existsSync(path.join(s.dir, 't_one.wav')));
    assertAllIntact(s, ['t_two', 't_three'], snapshot);
    assert.equal(list.index_rebuilt, true);
  } finally { s.cleanup(); }
  const s2 = setup({ mb: 1, days: 30 });
  try {
    const store = s2.open();
    for (const [i, id] of ['b1', 'b2', 'b3'].entries()) {
      s2.clock.t += 1000;
      store.write({ id, wav: realWav(14, i + 2), audioMs: 14000 }); // ~448 KB mỗi tệp, tổng > 1 MB
    }
    store.close();
    const p = path.join(s2.dir, 'index.json');
    const names = ['b1', 'b2', 'b3'].filter((id) => fs.existsSync(path.join(s2.dir, `${id}.wav`)));
    // mtime tăng dần để "cũ nhất" xác định được sau khi mất mục lục
    names.forEach((id, k) => { const t = new Date(s2.clock.t - (names.length - k) * 1000); fs.utimesSync(path.join(s2.dir, `${id}.wav`), t, t); });
    fs.writeFileSync(p, '');
    const list = s2.open().list();
    assert.ok(list.bytes <= MB);
    assert.equal(list.items[0].id, names[names.length - 1]); // tệp mới nhất còn
  } finally { s2.cleanup(); }
});

test('DELETE tất cả (removeAll) cũng dọn quarantine (người dùng chủ động xoá hết giọng); xoá từng mục thì không đụng quarantine', () => {
  const s = setup({ mb: 100, days: 30 });
  try {
    seed3(s);
    fs.writeFileSync(path.join(s.dir, 'rac.wav'), 'khong phai wav');
    const store = s.open();
    assert.equal(store.list().quarantined, 1);
    assert.deepEqual(store.remove('t_one'), { ok: true });
    assert.equal(store.list().quarantined, 1);
    assert.deepEqual(store.removeAll(), { ok: true, deleted: 2 });
    assert.equal(store.list().quarantined, 0);
    assert.deepEqual(files(path.join(s.dir, 'quarantine')), []);
  } finally { s.cleanup(); }
});

test('không chuyển được vào quarantine (bị chặn) ⇒ tệp vẫn nằm nguyên tại chỗ, không bị xoá', { skip: process.platform === 'win32' }, () => {
  const s = setup({ mb: 100, days: 30 });
  try {
    fs.mkdirSync(s.dir, { recursive: true });
    fs.writeFileSync(path.join(s.dir, 'rac.wav'), 'khong phai wav');
    fs.writeFileSync(path.join(s.dir, 'quarantine'), 'tệp chặn đường'); // "quarantine" là TỆP ⇒ mkdir thất bại
    const store = s.open();
    assert.equal(fs.readFileSync(path.join(s.dir, 'rac.wav'), 'utf8'), 'khong phai wav');
    assert.ok(s.logs.some((e) => e.event === 'audio_quarantine_failed'));
    assert.equal(store.list().count, 0);
  } finally { s.cleanup(); }
});

test('parseWavHeader: chấp nhận chunk phụ (LIST) trước data, dùng độ dài THẬT khi header khai báo quá lớn, từ chối sai định dạng', () => {
  const good = realWav(2);
  assert.deepEqual(parseWavHeader(good.subarray(0, 4096), good.length), { audio_ms: 2000 });
  // chèn chunk LIST (lẻ byte, cần đệm 1) giữa fmt và data
  const list = Buffer.concat([Buffer.from('LIST'), Buffer.from([3, 0, 0, 0]), Buffer.from('abc'), Buffer.from([0])]);
  const withList = Buffer.concat([good.subarray(0, 36), list, good.subarray(36)]);
  assert.deepEqual(parseWavHeader(withList.subarray(0, 4096), withList.length), { audio_ms: 2000 });
  const lying = Buffer.from(good); lying.writeUInt32LE(0x7fffffff, 40);
  assert.deepEqual(parseWavHeader(lying.subarray(0, 4096), lying.length), { audio_ms: 2000 });
  assert.equal(parseWavHeader(Buffer.from('RIFFxxxxWAVE'), 12), null);
  assert.equal(parseWavHeader(Buffer.alloc(0), 0), null);
});

test('tệp nhận lại và tệp cách ly được ép quyền 0600 (kể cả khi người dùng/công cụ khác để 0644)', { skip: process.platform === 'win32' }, () => {
  const s = setup({ mb: 100, days: 30 });
  try {
    fs.mkdirSync(s.dir, { recursive: true });
    fs.writeFileSync(path.join(s.dir, 'tot.wav'), realWav(1), { mode: 0o644 });
    fs.writeFileSync(path.join(s.dir, 'rac.wav'), 'khong phai wav', { mode: 0o644 });
    fs.chmodSync(path.join(s.dir, 'tot.wav'), 0o644);
    fs.chmodSync(path.join(s.dir, 'rac.wav'), 0o644);
    s.open();
    assert.equal(fs.statSync(path.join(s.dir, 'tot.wav')).mode & 0o777, 0o600);
    assert.equal(fs.statSync(path.join(s.dir, 'quarantine', 'rac.wav')).mode & 0o777, 0o600);
  } finally { s.cleanup(); }
});
