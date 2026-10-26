import { test } from 'node:test';
import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { encodeWav } from '../engine/stt/audio.js';
import {
  parsePrompts, parseAvfoundationDevices, parseVolumedetect, assessRecording, planSession,
  recordArgs, wavDurationSeconds, mergeSetMeta,
} from './record.js';

const CLI = fileURLToPath(new URL('../bin/vflow.js', import.meta.url));
const PROMPTS = fileURLToPath(new URL('./prompts/vi-en-40.txt', import.meta.url));

// Đầu ra thật của ffmpeg 8.1 trên Mac M1 Pro (2026-10-26), cả camera lẫn micro.
const LIST_STDERR = `[AVFoundation indev @ 0xc7f018140] AVFoundation video devices:
[AVFoundation indev @ 0xc7f018140] [0] Camera FaceTime HD
[AVFoundation indev @ 0xc7f018140] [1] Capture screen 0
[AVFoundation indev @ 0xc7f018140] [2] Capture screen 1
[AVFoundation indev @ 0xc7f018140] AVFoundation audio devices:
[AVFoundation indev @ 0xc7f018140] [0] Micrô MacBook Pro
[AVFoundation indev @ 0xc7f018140] [1] AirPods của Bạn [2]
[in#0 @ 0xc7f018000] Error opening input: Input/output error
Error opening input file .`;

test('liệt kê thiết bị: tách đúng audio/video, tên có dấu và ngoặc vuông, bỏ dòng lỗi', () => {
  const d = parseAvfoundationDevices(LIST_STDERR);
  assert.deepEqual(d.audio, [{ index: 0, name: 'Micrô MacBook Pro' }, { index: 1, name: 'AirPods của Bạn [2]' }]);
  assert.equal(d.video.length, 3);
  assert.equal(d.video[1].name, 'Capture screen 0');
  assert.deepEqual(parseAvfoundationDevices('ffmpeg: command not found'), { video: [], audio: [] });
});

test('volumedetect: đọc mean/max, -inf và thiếu số ⇒ null (không phải 0)', () => {
  const s = '[Parsed_volumedetect_0 @ 0x1] n_samples: 17408\n[Parsed_volumedetect_0 @ 0x1] mean_volume: -21.1 dB\n[Parsed_volumedetect_0 @ 0x1] max_volume: -0.0 dB\n';
  assert.deepEqual(parseVolumedetect(s), { mean_db: -21.1, max_db: -0 });
  assert.deepEqual(parseVolumedetect('mean_volume: -91.0 dB\nmax_volume: -inf dB'), { mean_db: -91, max_db: -Infinity });
  assert.deepEqual(parseVolumedetect('Error opening input'), { mean_db: null, max_db: null });
});

test('cờ cảnh báo âm lượng/thời lượng đúng ngưỡng, ở biên và khi thiếu số liệu', () => {
  const codes = (m) => assessRecording(m).map((w) => w.code).sort();
  assert.deepEqual(codes({ mean_db: -25, max_db: -6, duration_s: 3 }), []);
  assert.deepEqual(codes({ mean_db: -45.1, max_db: -6, duration_s: 3 }), ['too_quiet']);
  assert.deepEqual(codes({ mean_db: -45, max_db: -20, duration_s: 1 }), [], 'đúng ngưỡng thì chưa cảnh báo');
  assert.deepEqual(codes({ mean_db: -30, max_db: -20.1, duration_s: 3 }), ['too_quiet']);
  assert.deepEqual(codes({ mean_db: -12, max_db: -0.5, duration_s: 3 }), ['clipped']);
  assert.deepEqual(codes({ mean_db: -12, max_db: -0.6, duration_s: 3 }), []);
  assert.deepEqual(codes({ mean_db: -25, max_db: -6, duration_s: 0.99 }), ['too_short']);
  assert.deepEqual(codes({ mean_db: -91, max_db: -Infinity, duration_s: 0.2 }), ['too_quiet', 'too_short']);
  assert.deepEqual(codes({ mean_db: null, max_db: null, duration_s: null }), ['unknown_duration', 'unknown_level']);
});

test('tệp câu: NN. <câu>, bỏ dòng trống, lỗi khi sai dạng/trùng; bộ 40 câu thật đọc được', () => {
  assert.deepEqual(parsePrompts('1. Một câu.\n\n02.  Hai  \n'), [{ id: '01', text: 'Một câu.' }, { id: '02', text: 'Hai' }]);
  assert.throws(() => parsePrompts('01. a\nkhông có số'), /Dòng 2/);
  assert.throws(() => parsePrompts('01. a\n1. b'), /trùng/);
  assert.throws(() => parsePrompts('\n\n'), /không có câu/);
  const p = parsePrompts(fs.readFileSync(PROMPTS, 'utf8'));
  assert.equal(p.length, 40);
  assert.equal(p[39].id, '40');
});

test('tiếp tục thu: chỉ câu có đủ cả wav lẫn txt mới là xong; bản dở .part không tính', () => {
  const prompts = [{ id: '01' }, { id: '02' }, { id: '03' }, { id: '04' }];
  const { done, pending } = planSession(prompts, ['01.wav', '01.txt', '02.wav', '.03.part.wav', '03.txt', 'set.json']);
  assert.deepEqual(done.map((x) => x.id), ['01']);
  assert.deepEqual(pending.map((x) => x.id), ['02', '03', '04']);
});

test('tham số ffmpeg: luôn PCM16 16 kHz mono; mic dùng đúng thiết bị; giả dùng lavfi, không đụng micro', () => {
  const mic = recordArgs({ out: 'x.wav', device: 2 });
  assert.deepEqual(mic.slice(mic.indexOf('-f'), mic.indexOf('-f') + 4), ['-f', 'avfoundation', '-i', ':2']);
  for (const a of [mic, recordArgs({ out: 'x.wav', fake: true, fakeGainDb: -40 })]) {
    const j = a.join(' ');
    assert.match(j, /-ac 1 -ar 16000 -c:a pcm_s16le -f wav -y x\.wav$/);
  }
  const fake = recordArgs({ out: 'x.wav', fake: true, fakeGainDb: -40 }).join(' ');
  assert.ok(!fake.includes('avfoundation'));
  assert.match(fake, /-f lavfi -i sine=.*volume=-40dB/);
});

test('thời lượng WAV từ header, kể cả data size 0xFFFFFFFF; không phải WAV ⇒ null', () => {
  const wav = encodeWav(new Float32Array(16000 * 2.5), 16000);
  assert.equal(wavDurationSeconds(wav), 2.5);
  const open = new Uint8Array(wav);
  new DataView(open.buffer).setUint32(40, 0xffffffff, true);
  assert.equal(wavDurationSeconds(open), 2.5);
  assert.equal(wavDurationSeconds(new TextEncoder().encode('ID3 không phải wav')), null);
});

test('set.json: một lần thu giả làm cả bộ thành synthetic, không bao giờ "rửa" về giọng thật', () => {
  const a = mergeSetMeta(null, { fake: true, device: 0, now: 't1' });
  assert.equal(a.synthetic, true);
  const b = mergeSetMeta(a, { fake: false, device: 0, now: 't2' });
  assert.equal(b.synthetic, true);
  assert.deepEqual(b.sources, ['avfoundation:0', 'ffmpeg-lavfi-sine']);
  assert.equal(b.created, 't1');
  assert.equal(mergeSetMeta(null, { fake: false, device: 1, now: 't' }).synthetic, false);
});

const hasFfmpeg = spawnSync(process.env.VFLOW_FFMPEG || 'ffmpeg', ['-version']).status === 0;

test('record-set --input-fake: lưu NN.wav/NN.txt đúng định dạng, cảnh báo nhỏ tiếng, chạy lại tiếp tục câu sau', { skip: !hasFfmpeg && 'không có ffmpeg' }, async () => {
  const out = fs.mkdtempSync(path.join(os.tmpdir(), 'vflow-rec-test-'));
  try {
    const { spawn } = await import('node:child_process');
    // stdin giả: Enter bắt đầu, chờ 1,3 s, Enter dừng, Enter lưu; sau đó "q".
    const run = (extra, script) => new Promise((resolve) => {
      const c = spawn(process.execPath, [CLI, 'record-set', '--prompts', PROMPTS, '--out', out, '--input-fake', ...extra], { stdio: ['pipe', 'pipe', 'pipe'] });
      let stdout = '';
      c.stdout.on('data', (d) => { stdout += d; });
      c.stderr.on('data', (d) => { stdout += d; });
      (async () => {
        for (const [line, wait] of script) { c.stdin.write(line + '\n'); await new Promise((r) => setTimeout(r, wait)); }
        c.stdin.end();
      })();
      c.on('close', (code) => resolve({ code, stdout }));
    });
    const r1 = await run(['--fake-gain=-40'], [['', 1300], ['', 300], ['', 200], ['q', 100]]);
    assert.equal(r1.code, 0, r1.stdout);
    assert.match(r1.stdout, /CẢNH BÁO \[too_quiet\]/);
    assert.ok(fs.existsSync(path.join(out, '01.wav')));
    assert.equal(fs.readFileSync(path.join(out, '01.txt'), 'utf8'), 'Deploy bản mới lên staging giúp anh.\n');
    const wav = new Uint8Array(fs.readFileSync(path.join(out, '01.wav')));
    const view = new DataView(wav.buffer, wav.byteOffset);
    assert.deepEqual([view.getUint16(20, true), view.getUint16(22, true), view.getUint32(24, true), view.getUint16(34, true)], [1, 1, 16000, 16]);
    const dur = wavDurationSeconds(wav);
    assert.ok(dur > 1 && dur < 2.5, `thời lượng ${dur}`);
    assert.equal(JSON.parse(fs.readFileSync(path.join(out, 'set.json'), 'utf8')).synthetic, true);

    const r2 = await run([], [['q', 100]]);
    assert.match(r2.stdout, /Đã có 1\/40 câu/);
    assert.match(r2.stdout, /02\/40/);
    assert.ok(!/01\/40/.test(r2.stdout), 'không được hỏi lại câu đã có');
    assert.ok(fs.readdirSync(out).every((n) => !n.endsWith('.part.wav')));
  } finally {
    fs.rmSync(out, { recursive: true, force: true });
  }
});

test('record-set không ghi âm thanh vào trong repo và báo sai cú pháp', () => {
  const repo = fileURLToPath(new URL('..', import.meta.url));
  const r = spawnSync(process.execPath, [CLI, 'record-set', '--prompts', PROMPTS, '--out', path.join(repo, 'eval', 'x-set'), '--input-fake'], { encoding: 'utf8', input: '' });
  assert.equal(r.status, 2);
  assert.match(r.stderr, /Không ghi âm thanh vào trong repo/);
  assert.ok(!fs.existsSync(path.join(repo, 'eval', 'x-set')));
  assert.equal(spawnSync(process.execPath, [CLI, 'record-set', '--out', '/tmp/x'], { encoding: 'utf8' }).status, 2);
  assert.equal(spawnSync(process.execPath, [CLI, 'record-set', '--prompts', PROMPTS, '--out', '/tmp/x', '--device', 'abc'], { encoding: 'utf8' }).status, 2);
});
