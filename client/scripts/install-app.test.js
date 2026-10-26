// Kiểm install-app.sh bằng SHIM: hai tiến trình giả biên dịch thật (Mach-O thật, không phải script
// shebang — `ps -o comm=` trên macOS chỉ trả về ĐƯỜNG DẪN ĐẦY ĐỦ cho tiến trình thực thi trực tiếp,
// không phải cho script chạy qua trình thông dịch, nên phải dùng nhị phân biên dịch thật để khớp
// logic "allowed_prefixes" của install-app.sh — đã đo thật trước khi viết test này).
//
// KHÔNG đụng /Applications hay ~/.vflow thật: mọi đường dẫn đi qua VFLOW_INSTALL_SRC_APP /
// VFLOW_INSTALL_DEST_APP / VFLOW_INSTALL_BACKUP_DIR (thư mục tạm), VFLOW_INSTALL_SKIP_BUILD=1 (bỏ
// qua build-app.sh thật), VFLOW_INSTALL_NO_REOPEN=1, VFLOW_INSTALL_QUIT_TIMEOUT_SECONDS rút ngắn.
//
// GIỚI HẠN ĐÃ BIẾT: `osascript … quit …` được gọi thật trong script nhưng tiến trình giả không phải
// app GUI nên không phản hồi Apple Event — kịch bản "thoát được" mô phỏng bằng tiến trình giả TỰ
// thoát sau một khoảng ngắn (độc lập với AppleScript, vì script vốn đã `|| true` bỏ qua lỗi
// osascript). Đây là đúng phần logic được SỬA ở lần này (chờ + kiểm lại bằng pgrep + quyết định dừng
// hay tiếp tục) — không kiểm luồng Apple Event thật.
import test from 'node:test';
import assert from 'node:assert/strict';
import { execFileSync, spawnSync } from 'node:child_process';
import { mkdtempSync, mkdirSync, writeFileSync, rmSync, readFileSync, existsSync, readdirSync, chmodSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

const scriptsDir = dirname(fileURLToPath(import.meta.url));
const scriptPath = join(scriptsDir, 'install-app.sh');
const skip = process.platform !== 'darwin' ? 'cần macOS (pgrep -if, ps -o comm= đường dẫn đầy đủ, codesign)' : false;

test('bash -n: cú pháp hợp lệ', { skip }, () => {
  execFileSync('bash', ['-n', scriptPath]);
});

let fixturesDir;
let vflowFakeBin;
let engineFakeBin;

test.before(() => {
  if (skip) return;
  fixturesDir = mkdtempSync(join(tmpdir(), 'vflow-install-fixtures-'));

  // "engine" giả: sleep theo biến môi trường FAKE_SLEEP_SECONDS (mặc định dài, không tự thoát).
  writeFileSync(
    join(fixturesDir, 'engine_fake.c'),
    `#include <stdlib.h>\n#include <unistd.h>\nint main(void){int s=atoi(getenv("FAKE_SLEEP_SECONDS")?:"9999");sleep(s);return 0;}\n`,
  );
  // "VFlow" giả: fork + exec engine (argv[1] = đường dẫn engine) rồi tự sleep theo
  // FAKE_OWN_SLEEP_SECONDS trước khi thoát (mô phỏng "thoát nhẹ nhàng sau một khoảng ngắn").
  writeFileSync(
    join(fixturesDir, 'vflow_fake.c'),
    `#include <stdlib.h>\n#include <unistd.h>\n#include <sys/wait.h>\n` +
      `int main(int argc,char**argv){\n` +
      `  pid_t p=fork();\n` +
      `  if(p==0){execl(argv[1],argv[1],"serve",(char*)NULL);_exit(127);}\n` +
      `  int s=atoi(getenv("FAKE_OWN_SLEEP_SECONDS")?:"9999");\n` +
      `  sleep(s);\n` +
      `  return 0;\n` +
      `}\n`,
  );
  engineFakeBin = join(fixturesDir, 'engine_fake');
  vflowFakeBin = join(fixturesDir, 'vflow_fake');
  execFileSync('cc', ['-o', engineFakeBin, join(fixturesDir, 'engine_fake.c')]);
  execFileSync('cc', ['-o', vflowFakeBin, join(fixturesDir, 'vflow_fake.c')]);
});

test.after(() => {
  if (fixturesDir) rmSync(fixturesDir, { recursive: true, force: true });
});

/** Dựng SRC_APP (bản "mới" sẽ cài đè) — bundle tối giản, ký ad-hoc để codesign --verify qua được. */
const FAKE_INFO_PLIST = `<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>VFlow</string>
<key>CFBundleIdentifier</key><string>org.aios.vflow.test</string>
<key>CFBundlePackageType</key><string>APPL</string>
</dict></plist>
`;

function buildFakeSrcApp(dir, marker) {
  const macos = join(dir, 'VFlow.app', 'Contents', 'MacOS');
  mkdirSync(macos, { recursive: true });
  writeFileSync(join(dir, 'VFlow.app', 'Contents', 'VERSION'), marker);
  // Info.plist với CFBundleExecutable là điều kiện để codesign coi MacOS/VFlow là MAIN EXECUTABLE
  // (không phải một "resource" trong seal) — thiếu nó thì `ditto` + `codesign --verify` sau đó báo
  // "a sealed resource is missing or invalid" dù nội dung giống hệt (đã đo thật trước khi thêm).
  writeFileSync(join(dir, 'VFlow.app', 'Contents', 'Info.plist'), FAKE_INFO_PLIST);
  execFileSync('cp', [vflowFakeBin, join(macos, 'VFlow')]);
  execFileSync('codesign', ['--force', '--deep', '-s', '-', join(dir, 'VFlow.app')]);
  return join(dir, 'VFlow.app');
}

/** Dựng DEST_APP "đã cài" — nơi tiến trình giả ĐANG CHẠY sẽ được khởi chạy từ đúng đường dẫn này
 * (để qua được kiểm "allowed_prefixes" của install-app.sh, cần comm= khớp tiền tố DEST_APP). */
function buildFakeDestApp(dir, marker) {
  const macos = join(dir, 'vflow.app', 'Contents', 'MacOS');
  const engineDir = join(dir, 'vflow.app', 'Contents', 'Resources', 'engine', 'bin');
  mkdirSync(macos, { recursive: true });
  mkdirSync(engineDir, { recursive: true });
  writeFileSync(join(dir, 'vflow.app', 'Contents', 'VERSION'), marker);
  execFileSync('cp', [vflowFakeBin, join(macos, 'VFlow')]);
  execFileSync('cp', [engineFakeBin, join(engineDir, 'vflow.js')]);
  return { app: join(dir, 'vflow.app'), enginePath: join(engineDir, 'vflow.js'), exePath: join(macos, 'VFlow') };
}

function runInstall(env) {
  return spawnSync('bash', [scriptPath], {
    encoding: 'utf8',
    env: {
      ...process.env,
      VFLOW_INSTALL_SKIP_BUILD: '1',
      VFLOW_INSTALL_NO_REOPEN: '1',
      ...env,
    },
  });
}

/**
 * Khởi chạy `exePath enginePath` NỀN và tách hẳn khỏi tiến trình Node (nohup + `disown`, qua một
 * wrapper bash chạy-rồi-thoát-ngay) — nếu không, tiến trình giả khi tự thoát sẽ kẹt ở trạng thái
 * "zombie" (vẫn qua được `kill -0`!) cho tới khi Node cha reap nó, nhưng Node cha đang BỊ CHẶN bên
 * trong `spawnSync` gọi install-app.sh nên không reap kịp ⇒ bế tắc giả (đã đo thật: test treo đủ
 * 10s dù tiến trình giả đặt tự thoát sau 1s). Tách khỏi Node ⇒ hệ thống (launchd) reap thay, không
 * phụ thuộc trạng thái event loop của Node lúc đó.
 */
function launchFakeDetached(exePath, enginePath, env) {
  const r = spawnSync(
    'bash',
    ['-c', `nohup "$1" "$2" </dev/null >/dev/null 2>&1 & disown; echo $!`, '_', exePath, enginePath],
    { encoding: 'utf8', env: { ...process.env, ...env } },
  );
  const pid = parseInt(r.stdout.trim(), 10);
  if (!Number.isFinite(pid)) throw new Error(`không khởi chạy được tiến trình giả: ${r.stderr}`);
  return pid;
}

function pgrepPaths(exePath) {
  const r = spawnSync('pgrep', ['-f', exePath], { encoding: 'utf8' });
  return (r.stdout || '').trim().split('\n').filter(Boolean);
}

async function waitUntilGone(pid, timeoutMs) {
  const start = Date.now();
  while (Date.now() - start < timeoutMs) {
    const alive = spawnSync('kill', ['-0', String(pid)]).status === 0;
    if (!alive) return true;
    await new Promise((r) => setTimeout(r, 100));
  }
  return false;
}

test('tiến trình thoát được trong thời gian chờ ⇒ cài đè thành công, giữ 1 bản sao lưu', { skip }, async (t) => {
  const tmp = mkdtempSync(join(tmpdir(), 'vflow-install-coop-'));
  t.after(() => rmSync(tmp, { recursive: true, force: true }));
  const srcDir = join(tmp, 'src');
  const destParent = join(tmp, 'Applications');
  const backupDir = join(tmp, 'backup');
  mkdirSync(srcDir, { recursive: true });
  mkdirSync(destParent, { recursive: true });

  const srcApp = buildFakeSrcApp(srcDir, 'new-version');
  const { app: destApp, enginePath, exePath } = buildFakeDestApp(destParent, 'old-version');

  const pid = launchFakeDetached(exePath, enginePath, { FAKE_OWN_SLEEP_SECONDS: '1', FAKE_SLEEP_SECONDS: '1' });
  await new Promise((r) => setTimeout(r, 300)); // để engine con kịp fork trước khi install-app.sh chạy

  const result = runInstall({
    VFLOW_INSTALL_SRC_APP: srcApp,
    VFLOW_INSTALL_DEST_APP: destApp,
    VFLOW_INSTALL_BACKUP_DIR: backupDir,
    VFLOW_INSTALL_QUIT_TIMEOUT_SECONDS: '10',
  });

  assert.equal(result.status, 0, `install-app.sh phải thoát 0 khi tiến trình cũ thoát kịp.\n${result.stdout}\n${result.stderr}`);
  assert.equal(
    readFileSync(join(destApp, 'Contents', 'VERSION'), 'utf8'),
    'new-version',
    'DEST_APP phải được cài đè bằng bản mới',
  );
  const backups = existsSync(backupDir) ? readdirSync(backupDir).filter((n) => n.startsWith('vflow.app.bak.')) : [];
  assert.equal(backups.length, 1, `phải giữ ĐÚNG MỘT bản sao lưu, thấy: ${backups.join(', ')}`);
  assert.equal(
    readFileSync(join(backupDir, backups[0], 'Contents', 'VERSION'), 'utf8'),
    'old-version',
    'bản sao lưu phải là bản CŨ (trước khi cài đè)',
  );
});

test('tiến trình cứng đầu không thoát ⇒ dừng mã khác 0, KHÔNG chép đè, không tạo backup', { skip }, async (t) => {
  const tmp = mkdtempSync(join(tmpdir(), 'vflow-install-stubborn-'));
  t.after(() => rmSync(tmp, { recursive: true, force: true }));
  const srcDir = join(tmp, 'src');
  const destParent = join(tmp, 'Applications');
  const backupDir = join(tmp, 'backup');
  mkdirSync(srcDir, { recursive: true });
  mkdirSync(destParent, { recursive: true });

  const srcApp = buildFakeSrcApp(srcDir, 'new-version');
  const { app: destApp, enginePath, exePath } = buildFakeDestApp(destParent, 'old-version');

  const pid = launchFakeDetached(exePath, enginePath, { FAKE_OWN_SLEEP_SECONDS: '9999', FAKE_SLEEP_SECONDS: '9999' });
  await new Promise((r) => setTimeout(r, 300));

  try {
    const result = runInstall({
      VFLOW_INSTALL_SRC_APP: srcApp,
      VFLOW_INSTALL_DEST_APP: destApp,
      VFLOW_INSTALL_BACKUP_DIR: backupDir,
      VFLOW_INSTALL_QUIT_TIMEOUT_SECONDS: '2',
    });

    assert.notEqual(result.status, 0, 'install-app.sh phải DỪNG (mã khác 0) khi tiến trình cũ không thoát kịp');
    assert.match(result.stderr, /VẪN CÒN SỐNG/, 'phải báo rõ tiến trình còn sống, không im lặng');
    assert.equal(
      readFileSync(join(destApp, 'Contents', 'VERSION'), 'utf8'),
      'old-version',
      'DEST_APP KHÔNG được bị chép đè khi tiến trình cũ còn sống',
    );
    assert.ok(!existsSync(backupDir) || readdirSync(backupDir).length === 0, 'KHÔNG được tạo backup khi dừng trước bước sao lưu');
    // Vẫn còn sống thật — đúng như kỳ vọng "KHÔNG kill -9".
    assert.equal(spawnSync('kill', ['-0', String(pid)]).status, 0, 'tiến trình giả vẫn phải còn sống (script không được kill -9)');
  } finally {
    // Dọn tiến trình giả do CHÍNH TEST tạo ra (install-app.sh cố ý không đụng tới).
    const enginePids = pgrepPaths(enginePath);
    for (const toKill of [String(pid), ...enginePids]) {
      spawnSync('kill', ['-9', toKill]);
    }
    await waitUntilGone(pid, 2000);
  }
});
