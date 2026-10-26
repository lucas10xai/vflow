/**
 * Token Bearer của engine: 32 byte ngẫu nhiên (hex), lưu `<VFLOW_HOME>/token` quyền 0600.
 */
import { randomBytes, timingSafeEqual, createHash } from 'node:crypto';
import fsp from 'node:fs/promises';
import path from 'node:path';

const TOKEN_RE = /^[0-9a-f]{64}$/;

/**
 * Đọc token có sẵn hoặc sinh mới. Token hỏng ⇒ ném lỗi (không tự ghi đè âm thầm).
 * @param {string} file
 * @returns {Promise<{ token: string, created: boolean }>}
 */
export async function ensureToken(file) {
  await fsp.mkdir(path.dirname(file), { recursive: true, mode: 0o700 });
  try {
    const token = (await fsp.readFile(file, 'utf8')).trim();
    if (!TOKEN_RE.test(token)) throw new Error(`Tệp token ${file} không đúng định dạng (64 ký tự hex). Xoá tệp để sinh lại.`);
    if (process.platform !== 'win32') {
      const st = await fsp.stat(file);
      if ((st.mode & 0o077) !== 0) await fsp.chmod(file, 0o600);
    }
    return { token, created: false };
  } catch (err) {
    if (/** @type {any} */ (err).code !== 'ENOENT') throw err;
  }
  const token = randomBytes(32).toString('hex');
  await fsp.writeFile(file, token + '\n', { mode: 0o600, flag: 'wx' });
  return { token, created: true };
}

/**
 * So sánh hằng thời gian (băm trước để độ dài không lộ qua thời gian).
 * @param {string} given @param {string} expected
 */
export function tokenMatches(given, expected) {
  const a = createHash('sha256').update(String(given)).digest();
  const b = createHash('sha256').update(String(expected)).digest();
  return timingSafeEqual(a, b) && String(given) === String(expected);
}
