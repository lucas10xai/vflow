import { test, before, after } from 'node:test';
import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { encodeWav } from '../engine/stt/audio.js';

const CLI = fileURLToPath(new URL('./vflow.js', import.meta.url));
let home;

/** @param {string[]} args */
const run = (args) => {
  const r = spawnSync(process.execPath, [CLI, ...args], {
    env: { ...process.env, VFLOW_HOME: home, VFLOW_REMOTE_TOKEN: '' }, encoding: 'utf8', timeout: 30000,
  });
  return { code: r.status, out: r.stdout, err: r.stderr };
};

before(() => { home = fs.mkdtempSync(path.join(os.tmpdir(), 'vflow-cli-test-')); });
after(() => fs.rmSync(home, { recursive: true, force: true }));

test('sai cú pháp ⇒ mã 2 kèm hướng dẫn', () => {
  for (const args of [[], ['khong-co'], ['transcribe'], ['models'], ['models', 'pull'], ['bench', 'x.wav', '--runs', '0'], ['eval'], ['transcribe', 'a.wav', '--model', 'khong-co'], ['transcribe', '--la', 'a.wav']]) {
    const r = run(args);
    assert.equal(r.code, 2, `${args.join(' ')} → ${r.code}: ${r.err}`);
  }
  assert.match(run(['--help']).out, /Cách dùng: vflow/);
  assert.equal(run(['--help']).code, 0);
});

test('transcribe khi chưa có model ⇒ mã 1 và lý do model_unavailable/not_downloaded', () => {
  const wav = path.join(home, 'a.wav');
  fs.writeFileSync(wav, encodeWav(new Float32Array(1600).fill(0.1), 16000));
  const r = run(['transcribe', wav]);
  assert.equal(r.code, 1);
  assert.match(r.err, /model_unavailable\/not_downloaded/);
  assert.equal(r.out, '');
});

test('transcribe tệp không phải wav PCM16 ⇒ mã 1, bad_audio; tệp không tồn tại ⇒ mã 1', () => {
  const bad = path.join(home, 'b.wav');
  fs.writeFileSync(bad, 'ID3 không phải wav');
  const r = run(['transcribe', bad]);
  assert.equal(r.code, 1);
  assert.match(r.err, /bad_audio/);
  assert.equal(run(['transcribe', path.join(home, 'khong-co.wav')]).code, 1);
});

test('models list báo trạng thái thật; eval với thư mục không có cặp wav/txt ⇒ mã 1', () => {
  const r = run(['models', 'list']);
  assert.equal(r.code, 0);
  assert.match(r.out, /zipformer-vi-30m\s+local\s+chưa có \(not_downloaded\)/);
  const empty = path.join(home, 'set');
  fs.mkdirSync(empty);
  fs.writeFileSync(path.join(empty, 'x.wav'), encodeWav(new Float32Array(10), 16000));
  const e = run(['eval', '--set', empty]);
  assert.equal(e.code, 1);
  assert.match(e.err, /Không có cặp/);
});

test('doctor trả mã 1 khi model mặc định chưa có, và không in token từ xa', () => {
  const r = spawnSync(process.execPath, [CLI, 'doctor'], {
    env: { ...process.env, VFLOW_HOME: home, VFLOW_REMOTE_TOKEN: 'bi-mat-xyz' }, encoding: 'utf8',
  });
  assert.equal(r.status, 1);
  assert.match(r.stdout, /\[LỖI\] Model zipformer-vi-30m/);
  assert.ok(!r.stdout.includes('bi-mat-xyz') && !r.stderr.includes('bi-mat-xyz'));
});
