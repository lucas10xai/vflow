import { test } from 'node:test';
import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { encodeWav } from '../engine/stt/audio.js';
import {
  alignWords, heardAt, termReport, summarizeModel, representativeness, verdict, runCompare, buildReport, compareMarkdown,
} from './compare.js';

const CLI = fileURLToPath(new URL('../bin/vflow.js', import.meta.url));

test('căn hàng từ: thay/chèn/xoá đúng vị trí', () => {
  const ops = alignWords(['deploy', 'bản', 'mới'], ['đi', 'plôi', 'bản', 'mới']).map((o) => o.op);
  assert.deepEqual(ops.filter((o) => o !== 'eq').sort(), ['ins', 'sub']);
  assert.deepEqual(alignWords(['a', 'b', 'c'], ['a', 'c']).map((o) => o.op), ['eq', 'del', 'eq']);
  assert.deepEqual(alignWords([], ['x']).map((o) => o.op), ['ins']);
});

test('nghe ra gì ở vị trí thuật ngữ: một từ → nhiều âm tiết, cụm nhiều từ, bị bỏ hẳn, không có trong tham chiếu', () => {
  assert.equal(heardAt('Deploy bản mới lên staging giúp anh.', 'đi plôi bản mới lên sờ tây dinh giúp anh', 'deploy'), 'đi plôi');
  assert.equal(heardAt('Deploy bản mới lên staging giúp anh.', 'đi plôi bản mới lên sờ tây dinh giúp anh', 'staging'), 'sờ tây dinh');
  assert.equal(heardAt('Tạo pull request cho anh', 'tạo pun ri quét cho anh', 'pull request'), 'pun ri quét');
  assert.equal(heardAt('Chạy npm install ngay', 'chạy ngay', 'npm'), '');
  assert.equal(heardAt('Mở Node.js lên', 'mở nốt jết lên', 'Node.js'), 'nốt jết');
  assert.equal(heardAt('không có gì', 'không có gì', 'deploy'), null);
});

const clip = (name, ref, raw, post = raw, extra = {}) => ({ name, ref, raw, post, audio_ms: 5000, stt_ms: 500, ...extra });
const bad = (name, ref) => ({ name, ref, error: { code: 'timeout', reason: null, message: 'x' } });

test('tổng hợp: clip lỗi KHÔNG tính thành 0 lỗi, được đếm riêng; không clip nào thành công ⇒ không xác định', () => {
  const items = [clip('01', 'một hai ba bốn', 'một hai ba bốn'), bad('02', 'năm sáu bảy tám')];
  const s = summarizeModel(items, []);
  assert.equal(s.ok, 1);
  assert.equal(s.failed, 1);
  assert.deepEqual(s.errors, [{ clip: '02', code: 'timeout', reason: null }]);
  // Chỉ 4 từ của clip thành công là mẫu số; clip lỗi không làm WER "đẹp" lên (8 từ, 0 lỗi).
  assert.equal(s.post.tone.wer.ref_len, 4);
  const none = summarizeModel([bad('01', 'a b'), bad('02', 'c d')], []);
  assert.equal(none.post, null);
  assert.equal(none.raw, null);
  assert.equal(none.latency_ms.median, null);
  assert.equal(none.rtf.median, null);
});

test('tổng hợp: WER thô và sau post tách riêng, nhạy/không nhạy dấu thanh; RTF và độ trễ câu ~5 s', () => {
  const items = [
    clip('01', 'deploy lên staging', 'đi plôi lên staging', 'deploy lên staging', { audio_ms: 5000, stt_ms: 400 }),
    clip('02', 'đã xong', 'da xong', 'da xong', { audio_ms: 2000, stt_ms: 3000 }),
  ];
  const s = summarizeModel(items, ['deploy', 'staging']);
  assert.equal(s.raw.tone.wer.errors, 2 + 1);
  assert.equal(s.post.tone.wer.errors, 1);
  assert.equal(s.post.no_tone.wer.errors, 1, '"da" ≠ "đã" vì đ vẫn giữ khi bỏ dấu thanh');
  assert.equal(s.latency_5s.clips, 1);
  assert.equal(s.latency_5s.p95, 400);
  assert.ok(Math.abs(s.rtf.median - (0.08 + 1.5) / 2) < 1e-12);
  assert.equal(s.terms.hit_raw, 1);
  assert.equal(s.terms.hit_post, 2);
});

test('thuật ngữ sót: chỉ tính theo văn bản sau post, "nghe ra" lấy từ văn bản thô; clip lỗi không tính', () => {
  const items = [
    clip('01', 'Commit rồi push lên main', 'com mít rồi pút lên mên', 'commit rồi pút lên mên'),
    clip('02', 'push đi', 'pút đi', 'pút đi'),
    bad('03', 'push lại'),
  ];
  const t = termReport(items, ['commit', 'push', 'main']);
  assert.equal(t.expected, 4);
  assert.equal(t.hit_post, 1);
  assert.equal(t.hit_raw, 0);
  assert.deepEqual(t.per_term.push.missed, [{ clip: '01', heard: 'pút' }, { clip: '02', heard: 'pút' }]);
  assert.deepEqual(t.per_term.main.missed, [{ clip: '01', heard: 'mên' }]);
  assert.equal(t.per_term.commit.missed.length, 0);
  assert.equal(termReport([bad('01', 'push')], ['push']).rate_post, null);
});

test('KHÔNG ĐẠI DIỆN khi < 30 câu hoặc giọng tổng hợp; kết luận không chọn model khi không đại diện', () => {
  assert.equal(representativeness({ count: 30, synthetic: false }).representative, true);
  assert.equal(representativeness({ count: 29, synthetic: false }).representative, false);
  const syn = representativeness({ count: 40, synthetic: true, voice: 'Linh' });
  assert.equal(syn.representative, false);
  assert.match(syn.reasons[0], /GIỌNG TỔNG HỢP \(Linh\)/);

  const unknown = representativeness({ count: 40, synthetic: null });
  assert.equal(unknown.representative, false, 'thiếu set.json không được coi là giọng thật');
  assert.match(unknown.reasons[0], /KHÔNG xác định/);
  const runs = { m: { load_error: null, load_ms: 1, items: [] } };
  for (const meta of [null, {}, { synthetic: 'yes' }]) {
    const r = buildReport({ set: 's', meta, count: 40, missing_ref: [], mode: 'normal', dictionary: 'd', terms: null, runs });
    assert.equal(r.synthetic, null);
    assert.equal(r.representative.representative, false);
  }
  assert.equal(buildReport({ set: 's', meta: { synthetic: false }, count: 40, missing_ref: [], mode: 'normal', dictionary: 'd', terms: null, runs }).representative.representative, true);

  const good = summarizeModel([clip('01', 'a b c d', 'a b c d', 'a b c d', { audio_ms: 5000, stt_ms: 300 })], []);
  const v = verdict({ m1: good }, syn);
  assert.equal(v.best, null);
  assert.equal(v.best_on_this_set, 'm1');
  assert.match(v.text, /KHÔNG ĐẠI DIỆN/);
});

test('kết luận: WER thấp nhất trong các model đạt RTF < 0,3 và p95 câu 5 s < 1,5 s; thiếu số liệu không bao giờ là đạt', () => {
  const rep = { representative: true, reasons: [] };
  const mk = (hyp, stt, audio = 5000) => summarizeModel([clip('01', 'a b c d', hyp, hyp, { audio_ms: audio, stt_ms: stt })], []);
  const fastBad = mk('a x c d', 300);
  const slowGood = mk('a b c d', 1600); // RTF 0,32 và p95 1,6 s: không đạt
  const v = verdict({ fastBad, slowGood }, rep);
  assert.equal(v.best, 'fastBad');
  assert.equal(v.checks.slowGood.eligible, false);
  assert.match(v.checks.slowGood.reasons.join(), /RTF trung vị 0\.320 ≥ 0\.3/);

  const no5s = mk('a b c d', 100, 2000); // không có clip 4–6 s ⇒ không xác định ⇒ không đạt
  const withErr = summarizeModel([clip('01', 'a b c d', 'a b c d'), bad('02', 'e f')], []);
  const v2 = verdict({ no5s, withErr }, rep);
  assert.equal(v2.best, null);
  assert.match(v2.text, /Không model nào đạt tiêu chí/);
  assert.match(v2.checks.no5s.reasons.join(), /không có clip 4–6 s/);
  assert.match(v2.checks.withErr.reasons.join(), /1\/2 clip lỗi/);
});

test('runCompare: model không tải được ⇒ ghi lý do, mọi clip của nó là lỗi; model khác vẫn chạy và qua post', async () => {
  const pairs = [{ name: '01', wav: 'a', ref: 'xin chào' }, { name: '02', wav: 'b', ref: 'tạm biệt' }];
  const runs = await runCompare({
    pairs, models: ['up', 'down'], warmup: false,
    stt: {
      ensure: async (id) => { if (id === 'down') throw Object.assign(new Error('x'), { code: 'model_unavailable', reason: 'tunnel_down' }); },
      transcribe: async () => ({ text: 'xin chào', audio_ms: 1000, stt_ms: 50 }),
    },
    post: { process: async ({ textRaw }) => ({ text: textRaw.toUpperCase() }) },
    readWave: async () => ({ samples: new Float32Array(1), sampleRate: 16000 }),
  });
  assert.equal(runs.up.items.filter((it) => !it.error).length, 2);
  assert.equal(runs.up.items[0].raw, 'xin chào');
  assert.equal(runs.up.items[0].post, 'XIN CHÀO');
  assert.equal(runs.down.load_error.reason, 'tunnel_down');
  assert.equal(runs.down.items.length, 2);
  assert.ok(runs.down.items.every((it) => it.error?.reason === 'tunnel_down'));
});

test('runCompare: clip lỗi giữa chừng được ghi lỗi và các clip sau vẫn chạy', async () => {
  const pairs = ['01', '02', '03'].map((n) => ({ name: n, wav: n, ref: 'a' }));
  let n = 0;
  const runs = await runCompare({
    pairs, models: ['m'], warmup: false,
    stt: { ensure: async () => {}, transcribe: async () => { n++; if (n === 2) throw Object.assign(new Error('x'), { code: 'timeout' }); return { text: 'a', audio_ms: 1000, stt_ms: 10 }; } },
    post: { process: async ({ textRaw }) => ({ text: textRaw }) },
    readWave: async () => ({ samples: new Float32Array(1), sampleRate: 16000 }),
  });
  assert.deepEqual(runs.m.items.map((it) => it.error?.code ?? 'ok'), ['ok', 'timeout', 'ok']);
  const md = compareMarkdown(buildReport({ set: 's', meta: { synthetic: false }, count: 3, missing_ref: [], mode: 'normal', dictionary: 'd', terms: [], runs }));
  assert.match(md, /\| Clip thành công \/ lỗi \| 2\/3 · lỗi 1 \|/);
  assert.match(md, /Clip lỗi `m`: 02 \(timeout\)/);
  assert.match(md, /^> \*\*⚠ KHÔNG ĐẠI DIỆN\*\* — bộ mẫu chỉ có 3 câu/);
});

test('compare CLI: model từ xa thiếu token ⇒ báo cáo ghi lỗi từng clip (không phải 0), mã 1; sai cú pháp ⇒ mã 2', () => {
  const home = fs.mkdtempSync(path.join(os.tmpdir(), 'vflow-cmp-test-'));
  try {
    const set = path.join(home, 'set');
    fs.mkdirSync(set);
    for (const n of ['01', '02']) {
      fs.writeFileSync(path.join(set, `${n}.wav`), encodeWav(new Float32Array(8000).fill(0.1), 16000));
      fs.writeFileSync(path.join(set, `${n}.txt`), 'deploy lên staging\n');
    }
    const env = { ...process.env, VFLOW_HOME: home, VFLOW_REMOTE_TOKEN: '' };
    const r = spawnSync(process.execPath, [CLI, 'compare', '--set', set, '--models', 'phowhisper-large'], { env, encoding: 'utf8' });
    assert.equal(r.status, 1, r.stderr);
    assert.match(r.stdout, /0\/2 · lỗi 2/);
    assert.match(r.stdout, /LỖI model_unavailable\/missing_token/);
    assert.match(r.stdout, /KHÔNG ĐẠI DIỆN/);
    assert.match(r.stdout, /Không model nào đạt tiêu chí/);
    const reports = fs.readdirSync(path.join(set, 'reports'));
    assert.equal(reports.filter((f) => f.endsWith('.json')).length, 1);
    assert.ok(!fs.existsSync(path.join(home, 'dictionary.json')), 'không được ghi từ điển người dùng');
    for (const args of [['compare', '--set', set], ['compare', '--models', 'zipformer-vi-30m'], ['compare', '--set', set, '--models', 'khong-co'], ['compare', '--set', set, '--models', 'zipformer-vi-30m', '--mode', 'auto']]) {
      assert.equal(spawnSync(process.execPath, [CLI, ...args], { env, encoding: 'utf8' }).status, 2, args.join(' '));
    }
  } finally {
    fs.rmSync(home, { recursive: true, force: true });
  }
});
