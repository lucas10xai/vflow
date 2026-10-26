// Kiểm scripts/phowhisper.sh bằng `ssh` giả (không chạm gpu-host thật). Cần bash nên bỏ qua trên Windows.
import test from 'node:test';
import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { mkdtempSync, writeFileSync, readFileSync, rmSync, chmodSync, existsSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

const script = join(dirname(fileURLToPath(import.meta.url)), 'phowhisper.sh');
const skip = process.platform === 'win32' ? 'cần bash (chạy trên Mac)' : false;
const SECRET = 'tok-bi-mat-0123456789abcdef';

/**
 * Dựng thư mục có `ssh` giả: ghi mọi lệnh từ xa vào calls.log, trả nvidia-smi theo biến môi trường.
 * @param {{ usedMib?: string, ourMib?: string, nvidiaFails?: boolean }} o
 */
function fakeEnv(t, { usedMib = '2443', ourMib = '0', nvidiaFails = false } = {}) {
  const dir = mkdtempSync(join(tmpdir(), 'vflow-pw-test-'));
  t.after(() => rmSync(dir, { recursive: true, force: true }));
  const ssh = join(dir, 'ssh');
  writeFileSync(ssh, `#!/usr/bin/env bash
cmd="\${@: -1}"
printf '%s\\n' "$cmd" >> "${dir}/calls.log"
case "$cmd" in
  nvidia-smi*) ${nvidiaFails ? 'echo "NVIDIA-SMI has failed" >&2; exit 9' : `echo ${usedMib}; echo ${ourMib}`} ;;
  "cat "*token) echo "${SECRET}" ;;
  *run.sh) echo "Đã chạy pid 1" ;;
  *stop.sh) echo "Đã dừng" ;;
  end=*) exit 1 ;;
  curl*healthz) echo '{"ok": false, "reason": "loading"}' ;;
  *) exit 0 ;;
esac
`);
  chmodSync(ssh, 0o755);
  const env = { ...process.env, PATH: `${dir}:${process.env.PATH}`, VFLOW_HOME: dir, VFLOW_REMOTE_PORT: '47612', VFLOW_HEALTH_TIMEOUT_S: '1' };
  const run = (...args) => spawnSync('bash', [script, ...args], { env, encoding: 'utf8' });
  const calls = () => (existsSync(join(dir, 'calls.log')) ? readFileSync(join(dir, 'calls.log'), 'utf8') : '');
  return { dir, run, calls };
}

test('up từ chối (mã 3) khi dịch vụ khác chiếm > 10 GB VRAM, không chạy run.sh', { skip }, (t) => {
  const f = fakeEnv(t, { usedMib: '10241', ourMib: '0' });
  const r = f.run('up');
  assert.equal(r.status, 3, r.stderr);
  assert.match(r.stderr, /10241 MiB VRAM/);
  assert.doesNotMatch(f.calls(), /run\.sh/);
});

test('up: VRAM của chính vflow không bị tính là dịch vụ khác; đúng 10 GB vẫn được chạy', { skip }, (t) => {
  // 14 GB tổng nhưng 4 GB là máy chủ vflow ⇒ dịch vụ khác 10240 MiB ⇒ không bị chặn ở bước VRAM.
  const f = fakeEnv(t, { usedMib: '14336', ourMib: '4096' });
  const r = f.run('up');
  assert.notEqual(r.status, 3, r.stderr);
  assert.match(f.calls(), /run\.sh/);
  // healthz giả không bao giờ loaded:true ⇒ hết giờ, phải gọi stop.sh để trả GPU và trả mã 1.
  assert.equal(r.status, 1);
  assert.match(f.calls(), /stop\.sh/);
});

test('up: không đọc được nvidia-smi ⇒ không xác định VRAM ⇒ từ chối (mã 1), không chạy run.sh', { skip }, (t) => {
  const f = fakeEnv(t, { nvidiaFails: true });
  const r = f.run('up');
  assert.equal(r.status, 1);
  assert.match(r.stderr, /không xác định được VRAM/);
  assert.doesNotMatch(f.calls(), /run\.sh/);
});

test('exec: token chỉ vào env của tiến trình con, không xuất hiện trong đầu ra của script', { skip }, (t) => {
  const f = fakeEnv(t);
  const r = f.run('exec', '--', 'bash', '-c', 'test "$VFLOW_REMOTE_TOKEN" = "$0" && echo co-token', SECRET);
  assert.equal(r.status, 0, r.stderr);
  assert.equal(r.stdout.trim(), 'co-token');
  const up = f.run('status');
  assert.ok(!up.stdout.includes(SECRET) && !up.stderr.includes(SECRET));
  assert.ok(!readFileSync(script, 'utf8').includes(SECRET));
});

test('down không có tunnel vẫn chạy stop.sh; sai lệnh ⇒ mã 2', { skip }, (t) => {
  const f = fakeEnv(t);
  const r = f.run('down');
  assert.equal(r.status, 0, r.stderr);
  assert.match(r.stdout, /Không có tunnel/);
  assert.match(f.calls(), /stop\.sh/);
  assert.equal(f.run().status, 2);
  assert.equal(f.run('khong-co').status, 2);
  assert.equal(f.run('exec').status, 2);
});
