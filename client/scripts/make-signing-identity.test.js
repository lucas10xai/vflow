// Kiểm make-signing-identity.sh. Hai nhóm:
//  1. Cờ dòng lệnh + --dry-run: không đụng keychain thật (chỉ ĐỌC trạng thái hiện có để in).
//  2. Luồng THẬT trên keychain TẠM (security create-keychain, xoá bằng security delete-keychain
//     trong t.after): dùng VFLOW_SIGN_KEYCHAIN để không đụng login keychain của chủ dự án, và
//     VFLOW_SIGN_SKIP_TRUST=1 để KHÔNG đụng Certificate Trust Settings thật (xem bằng chứng ở đầu
//     lib-signing.sh: security add-trusted-cert chỉ nhận -k để chọn keychain CHỨA chứng chỉ, còn
//     bản thân trust luôn ghi vào user domain toàn hệ thống — không có cách giới hạn vào một
//     keychain tạm). Vì vậy đường đi "tin cậy thật rồi ký thành công" KHÔNG được kiểm ở đây — xem
//     ghi chú ở cuối tệp.
// Cần bash + Keychain Services thật (macOS) nên bỏ qua trên Windows/Linux.
import test from 'node:test';
import assert from 'node:assert/strict';
import { execFileSync, spawnSync } from 'node:child_process';
import { mkdtempSync, rmSync, existsSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { randomUUID } from 'node:crypto';

const scriptsDir = dirname(fileURLToPath(import.meta.url));
const scriptPath = join(scriptsDir, 'make-signing-identity.sh');
const skip = process.platform !== 'darwin' ? 'cần Keychain Services thật (macOS)' : false;

/** Chạy make-signing-identity.sh, trả về {stdout (gộp cả stderr), code}; không throw khi exit != 0. */
function runScript(args, env) {
  const r = spawnSync('bash', [scriptPath, ...args], {
    encoding: 'utf8',
    env: { ...process.env, ...env },
  });
  return { stdout: (r.stdout ?? '') + (r.stderr ?? ''), code: r.status };
}

test('bash -n: cú pháp hợp lệ', { skip }, () => {
  execFileSync('bash', ['-n', scriptPath]);
});

test('không cờ ⇒ lỗi mã 64', { skip }, () => {
  const r = runScript([]);
  assert.equal(r.code, 64);
});

test('--yes và --dry-run cùng lúc ⇒ lỗi mã 64', { skip }, () => {
  const r = runScript(['--yes', '--dry-run']);
  assert.equal(r.code, 64);
});

test('cờ không rõ ⇒ lỗi mã 64', { skip }, () => {
  const r = runScript(['--bogus']);
  assert.equal(r.code, 64);
});

test('--dry-run không đụng gì (login keychain không đổi, không tạo tệp tạm sót lại)', { skip }, () => {
  const r = runScript(['--dry-run']);
  assert.equal(r.code, 0);
  assert.match(r.stdout, /--dry-run/);
});

test('--dry-run --remove không đụng gì', { skip }, () => {
  const r = runScript(['--dry-run', '--remove']);
  assert.equal(r.code, 0);
});

test('luồng thật trên keychain tạm: none → (SKIP_TRUST) untrusted → idempotent → remove → none', { skip }, (t) => {
  const kcDir = mkdtempSync(join(tmpdir(), 'vflow-sign-test-'));
  const keychain = join(kcDir, `test-${randomUUID()}.keychain-db`);
  execFileSync('security', ['create-keychain', '-p', 'vflow-test-pass-not-secret', keychain]);
  t.after(() => {
    try {
      execFileSync('security', ['delete-keychain', keychain]);
    } catch {
      // đã xoá trong test (--remove) thì delete-keychain lần 2 có thể lỗi "không tồn tại" — bỏ qua.
    }
    rmSync(kcDir, { recursive: true, force: true });
  });

  const env = { VFLOW_SIGN_KEYCHAIN: keychain, VFLOW_SIGN_SKIP_TRUST: '1' };

  const before = execFileSync('security', ['find-identity', '-p', 'codesigning', keychain], { encoding: 'utf8' });
  assert.match(before, /0 identities found/, 'keychain tạm mới tạo chưa có danh tính nào');

  const first = runScript(['--yes'], env);
  assert.equal(first.code, 0, `lần đầu --yes thất bại:\n${first.stdout}`);
  assert.match(first.stdout, /CẢNH BÁO TO.*VFLOW_SIGN_SKIP_TRUST/s);
  assert.match(first.stdout, /trạng thái: untrusted/);

  const afterFirst = execFileSync('security', ['find-identity', '-p', 'codesigning', keychain], { encoding: 'utf8' });
  assert.match(afterFirst, /"vflow Local Signing" \(CSSMERR_TP_NOT_TRUSTED\)/);
  const afterFirstValid = execFileSync('security', ['find-identity', '-v', '-p', 'codesigning', keychain], {
    encoding: 'utf8',
  });
  assert.match(afterFirstValid, /0 valid identities found/, 'chưa tin cậy ⇒ find-identity -v không thấy');

  // codesign thật phải báo "no identity found" — đúng như bằng chứng đo được, không phải giả định.
  let codesignFailed = false;
  try {
    execFileSync('codesign', ['-s', 'vflow Local Signing', '--keychain', keychain, scriptPath], { stdio: 'pipe' });
  } catch (err) {
    codesignFailed = true;
    assert.match(err.stderr.toString(), /no identity found/);
  }
  assert.ok(codesignFailed, 'codesign PHẢI lỗi khi chứng chỉ chưa được tin cậy');

  const countMatches = (out) => (out.match(/"vflow Local Signing"/g) ?? []).length;
  const beforeSecondCount = countMatches(afterFirst);

  const second = runScript(['--yes'], env);
  assert.equal(second.code, 0, `lần hai (idempotent) thất bại:\n${second.stdout}`);
  assert.match(second.stdout, /trạng thái: untrusted/);
  const afterSecond = execFileSync('security', ['find-identity', '-p', 'codesigning', keychain], { encoding: 'utf8' });
  assert.equal(
    countMatches(afterSecond),
    beforeSecondCount,
    'chạy --yes lần hai khi đã "untrusted" KHÔNG được tạo thêm bản chứng chỉ trùng',
  );

  const remove = runScript(['--yes', '--remove'], env);
  assert.equal(remove.code, 0, `--remove thất bại:\n${remove.stdout}`);
  const afterRemove = execFileSync('security', ['find-identity', '-p', 'codesigning', keychain], { encoding: 'utf8' });
  assert.match(afterRemove, /0 identities found/);

  const removeAgain = runScript(['--yes', '--remove'], env);
  assert.equal(removeAgain.code, 0, '--remove lần hai (đã xoá rồi) phải idempotent, không lỗi');
  assert.match(removeAgain.stdout, /không có gì để xoá/);
});

// GHI CHÚ: đường đi "security add-trusted-cert" (bước tin cậy thật) rồi "codesign" thành công
// KHÔNG được kiểm tự động ở đây. `security add-trusted-cert -k <keychain>` chỉ quyết định keychain
// CHỨA chứng chỉ, nhưng Trust Settings luôn ghi vào domain "user" toàn hệ thống (không có cách giới
// hạn vào một keychain tạm, theo `security add-trusted-cert -h`) — chạy bước này trong test sẽ đổi
// Certificate Trust Settings THẬT của chủ dự án, vi phạm ràng buộc của nhiệm vụ. Việc kiểm bước này
// chỉ an toàn khi chạy thủ công bởi chủ dự án với `--yes` thật trên login keychain (xem báo cáo).
