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
  for (const args of [
    [], ['khong-co'], ['transcribe'], ['models'], ['models', 'pull'], ['bench', 'x.wav', '--runs', '0'], ['eval'],
    ['transcribe', 'a.wav', '--model', 'khong-co'], ['transcribe', '--la', 'a.wav'],
    ['snippets'], ['snippets', 'khong-ro'], ['snippets', 'add'], ['snippets', 'add', 'chi-trigger'], ['snippets', 'remove'],
    ['settings'], ['settings', 'khong-ro'], ['settings', 'set'], ['settings', 'set', 'chi-mot-tham-so'],
  ]) {
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

test('snippets list|add|remove đọc/ghi ~/.vflow/snippets.json qua VFLOW_HOME', () => {
  assert.match(run(['snippets', 'list']).out, /chưa có snippet/);
  const add = run(['snippets', 'add', 'chữ ký', 'Nguyễn Văn An — AIOS']);
  assert.equal(add.code, 0, add.err);
  assert.match(add.out, /Đã lưu snippet/);
  const list = run(['snippets', 'list']);
  assert.match(list.out, /chữ ký/);
  const stored = JSON.parse(fs.readFileSync(path.join(home, 'snippets.json'), 'utf8'));
  assert.deepEqual(stored.entries[0].trigger, 'chữ ký');
  assert.equal(stored.entries[0].text, 'Nguyễn Văn An — AIOS');
  if (process.platform !== 'win32') assert.equal(fs.statSync(path.join(home, 'snippets.json')).mode & 0o777, 0o600);
  const addBad = run(['snippets', 'add', 'x'.repeat(61), 'y']);
  assert.equal(addBad.code, 1);
  const rm = run(['snippets', 'remove', 'chữ ký']);
  assert.equal(rm.code, 0);
  assert.match(run(['snippets', 'list']).out, /chưa có snippet/);
  const rmMissing = run(['snippets', 'remove', 'không-có']);
  assert.equal(rmMissing.code, 1);
});

test('settings get|set đọc/ghi ~/.vflow/config.json qua VFLOW_HOME, kiểm giá trị, giữ khoá khác', () => {
  fs.writeFileSync(path.join(home, 'config.json'), JSON.stringify({ default_model: 'zipformer-vi-30m' }));
  const get0 = JSON.parse(run(['settings', 'get']).out);
  assert.deepEqual(get0, { cloud_llm: true, llm_model: null, llm_timeout_ms: 8000, actions_enabled: true });
  const set = run(['settings', 'set', 'cloud_llm', 'false']);
  assert.equal(set.code, 0, set.err);
  assert.equal(JSON.parse(set.out).cloud_llm, false);
  assert.equal(JSON.parse(run(['settings', 'get']).out).cloud_llm, false);
  const raw = JSON.parse(fs.readFileSync(path.join(home, 'config.json'), 'utf8'));
  assert.equal(raw.default_model, 'zipformer-vi-30m', 'giữ khoá khác trong config.json');
  const bad = run(['settings', 'set', 'llm_timeout_ms', '1']);
  assert.equal(bad.code, 1);
  const badKey = run(['settings', 'set', 'khong_ton_tai', '1']);
  assert.equal(badKey.code, 1);
});

test('doctor trả mã 1 khi model mặc định chưa có, và không in token từ xa', () => {
  const r = spawnSync(process.execPath, [CLI, 'doctor'], {
    env: { ...process.env, VFLOW_HOME: home, VFLOW_REMOTE_TOKEN: 'bi-mat-xyz' }, encoding: 'utf8',
  });
  assert.equal(r.status, 1);
  assert.match(r.stdout, /\[LỖI\] Model zipformer-vi-30m/);
  assert.ok(!r.stdout.includes('bi-mat-xyz') && !r.stderr.includes('bi-mat-xyz'));
});
