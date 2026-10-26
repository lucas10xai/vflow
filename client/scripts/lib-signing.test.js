// Kiểm hàm dò trạng thái/thông báo ký mã dùng chung (lib-signing.sh) bằng `security`/`codesign` GIẢ
// trên PATH — không đụng keychain thật, không build gì. Bằng chứng hành vi thật của
// `security find-identity` (dùng để thiết kế các hàm này) nằm ở client/scripts/make-signing-identity.test.js.
// Cần bash + macOS `security`/`codesign` thật trong PATH của fake script nên bỏ qua trên Windows.
import test from 'node:test';
import assert from 'node:assert/strict';
import { execFileSync } from 'node:child_process';
import { mkdtempSync, mkdirSync, writeFileSync, rmSync, chmodSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

const scriptsDir = dirname(fileURLToPath(import.meta.url));
const libSigningSh = join(scriptsDir, 'lib-signing.sh');
const skip = process.platform === 'win32' ? 'cần bash (chạy trên Mac)' : false;

const NAME = 'vflow Local Signing';

/**
 * Tạo thư mục PATH giả chỉ chứa `security` (và tuỳ chọn `codesign`) giả, mô phỏng đúng 3 trạng thái
 * đã đo thật trên keychain tạm (xem lib-signing.sh): "none" (không thấy ở đâu cả), "untrusted" (thấy
 * ở find-identity KHÔNG -v, kèm CSSMERR_TP_NOT_TRUSTED, nhưng "0 valid identities found" ở -v),
 * "valid" (thấy ở find-identity CÓ -v).
 */
function fakeSecurityDir(state, { codesignDr } = {}) {
  const dir = mkdtempSync(join(tmpdir(), 'vflow-fake-security-'));
  const bodies = {
    none: `
if [ "$1" = "find-identity" ]; then
  echo "     0 valid identities found"
  exit 0
fi
echo "LỖI: security giả không mô phỏng lệnh: $*" >&2
exit 99
`,
    untrusted: `
if [ "$1" = "find-identity" ] && [ "$2" = "-v" ]; then
  echo "     0 valid identities found"
  exit 0
fi
if [ "$1" = "find-identity" ]; then
  echo "Policy: Code Signing"
  echo "  Matching identities"
  echo "  1) 0000000000000000000000000000000000000000 \\"${NAME}\\" (CSSMERR_TP_NOT_TRUSTED)"
  echo "     1 identities found"
  echo ""
  echo "  Valid identities only"
  echo "     0 valid identities found"
  exit 0
fi
echo "LỖI: security giả không mô phỏng lệnh: $*" >&2
exit 99
`,
    valid: `
if [ "$1" = "find-identity" ] && [ "$2" = "-v" ]; then
  echo "  1) 0000000000000000000000000000000000000000 \\"${NAME}\\""
  echo "     1 valid identities found"
  exit 0
fi
if [ "$1" = "find-identity" ]; then
  echo "Policy: Code Signing"
  echo "  Matching identities"
  echo "  1) 0000000000000000000000000000000000000000 \\"${NAME}\\""
  echo "     1 identities found"
  exit 0
fi
echo "LỖI: security giả không mô phỏng lệnh: $*" >&2
exit 99
`,
  };
  writeFileSync(join(dir, 'security'), `#!/bin/bash\n${bodies[state]}`);
  chmodSync(join(dir, 'security'), 0o755);
  if (codesignDr !== undefined) {
    writeFileSync(
      join(dir, 'codesign'),
      `#!/bin/bash\nif [ "$1" = "-dr-" ]; then printf '%s' ${JSON.stringify(codesignDr)}; exit 0; fi\nexit 99\n`,
    );
    chmodSync(join(dir, 'codesign'), 0o755);
  }
  return dir;
}

/**
 * Nguồn lib-signing.sh trong bash với PATH giả rồi gọi một snippet, trả về {stdout, code} với
 * stdout đã gộp CẢ stderr (2>&1) — các hàm thông báo trong lib-signing.sh in ra stderr có chủ đích
 * (để không lẫn vào giá trị trả về qua $(...)), nên test chỉ cần kiểm nội dung, không cần phân biệt.
 */
function run(fakeDir, snippet) {
  try {
    const stdout = execFileSync(
      'bash',
      ['-c', `export PATH="$1:$PATH"; { source "$2"; ${snippet}; } 2>&1`, '_', fakeDir, libSigningSh],
      { encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'] },
    );
    return { stdout, code: 0 };
  } catch (err) {
    return { stdout: err.stdout?.toString() ?? '', code: err.status };
  }
}

for (const state of ['none', 'untrusted', 'valid']) {
  test(`vflow_signing_state nhận diện đúng trạng thái "${state}" qua security giả`, { skip }, (t) => {
    const dir = fakeSecurityDir(state);
    t.after(() => rmSync(dir, { recursive: true, force: true }));
    const { stdout, code } = run(dir, 'vflow_signing_state');
    assert.equal(code, 0);
    assert.equal(stdout.trim(), state);
  });
}

test('vflow_signing_codesign_arg: chỉ "valid" mới trả tên danh tính, còn lại là "-" (ad-hoc)', { skip }, () => {
  const dir = fakeSecurityDir('none');
  try {
    assert.equal(run(dir, 'vflow_signing_codesign_arg valid').stdout, NAME);
    assert.equal(run(dir, 'vflow_signing_codesign_arg untrusted').stdout, '-');
    assert.equal(run(dir, 'vflow_signing_codesign_arg none').stdout, '-');
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
});

test('vflow_signing_report: trạng thái "untrusted" PHẢI nhắc chạy --yes để thêm tin cậy, không im lặng rơi về ad-hoc', { skip }, () => {
  const dir = fakeSecurityDir('none');
  try {
    const r = run(dir, 'vflow_signing_report untrusted 1>&2');
    assert.match(r.stdout, /CHƯA được tin cậy/);
    assert.match(r.stdout, /make-signing-identity\.sh --yes/);
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
});

test('vflow_signing_check_dr: cảnh báo khi designated requirement còn dựa trên cdhash (ad-hoc không thật sự ổn định)', { skip }, () => {
  const dir = fakeSecurityDir('none', { codesignDr: 'Executable=/tmp/x\n# designated => cdhash H"deadbeef"\n' });
  try {
    const r = run(dir, 'vflow_signing_check_dr /tmp/does-not-matter.app 1>&2');
    assert.match(r.stdout, /cdhash/);
    assert.match(r.stdout, /KHÔNG có tác dụng/);
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
});

test('vflow_signing_check_dr: KHÔNG cảnh báo khi designated requirement neo vào chứng chỉ (không có cdhash)', { skip }, () => {
  const dir = fakeSecurityDir('none', {
    codesignDr: 'Executable=/tmp/x\nidentifier "org.aios.vflow" and certificate leaf = H"abc123"\n',
  });
  try {
    const r = run(dir, 'vflow_signing_check_dr /tmp/does-not-matter.app 1>&2');
    assert.doesNotMatch(r.stdout, /CẢNH BÁO/);
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
});
