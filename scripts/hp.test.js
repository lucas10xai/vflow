// Kiểm bộ lọc tệp của `scripts/hp.sh sync` (phía Mac): cái gì được gửi sang HP.
// Cần bash nên bỏ qua trên Windows.
import test from 'node:test';
import assert from 'node:assert/strict';
import { execFileSync } from 'node:child_process';
import { mkdtempSync, mkdirSync, writeFileSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

const hpSh = join(dirname(fileURLToPath(import.meta.url)), 'hp.sh');
const skip = process.platform === 'win32' ? 'cần bash (chạy trên Mac)' : false;

/** Chạy một hàm của hp.sh với REPO trỏ vào thư mục tạm. */
function bash(repo, snippet) {
  return execFileSync('bash', ['-c', `source "$1"; REPO="$2"; ${snippet}`, '_', hpSh, repo], {
    encoding: 'utf8',
  });
}

test('sync chỉ gửi tệp mã nguồn, không gửi secret, model, node_modules, wav lớn', { skip }, (t) => {
  const repo = mkdtempSync(join(tmpdir(), 'vflow-hp-test-'));
  t.after(() => rmSync(repo, { recursive: true, force: true }));
  const files = {
    'package.json': '{}',
    'engine/stt/a.js': '',
    'eval/small.wav': Buffer.alloc(1024),
    'eval/big.wav': Buffer.alloc(5 * 1024 * 1024 + 1),
    'eval/exact5mb.wav': Buffer.alloc(5 * 1024 * 1024),
    '.env': 'KEY=***',
    '.env.local': 'KEY=***',
    'engine/.DS_Store': '',
    '.git/config': '',
    'node_modules/x/index.js': '',
    'engine/node_modules/y.js': '',
    'models/m.onnx': '',
    'engine/stt/Models/m.onnx': '',
    '.vflow/config.json': '',
  };
  for (const [rel, content] of Object.entries(files)) {
    mkdirSync(join(repo, dirname(rel)), { recursive: true });
    writeFileSync(join(repo, rel), content);
  }
  const listed = bash(repo, 'local_find f').split('\0').filter(Boolean).map((p) => p.replace(/^\.\//, '')).sort();
  assert.deepEqual(listed, ['engine/stt/a.js', 'eval/exact5mb.wav', 'eval/small.wav', 'package.json']);
  const dirs = bash(repo, 'local_find d').split('\0').filter(Boolean).map((p) => p.replace(/^\.\//, '')).sort();
  assert.deepEqual(dirs, ['engine', 'engine/stt', 'eval']);
});

test('run từ chối tham số chứa dấu ngoặc kép trước khi đụng tới HP', { skip }, () => {
  // Host không tồn tại: nếu kiểm tra tham số không chặn trước, script sẽ cố SSH và trả 255.
  let code = 0;
  try {
    execFileSync('bash', [hpSh, 'run', 'node', '-e', 'console.log("x")'], {
      env: { ...process.env, VFLOW_HP_HOST: 'vflow-no-such-host.invalid' },
      stdio: 'pipe',
    });
  } catch (err) {
    code = err.status;
  }
  assert.equal(code, 2);
});
