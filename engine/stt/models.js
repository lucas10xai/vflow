/**
 * Quản lý model cục bộ: liệt kê, tải về (kiểm sha256), xác định tệp model.
 * Model nằm ở `<VFLOW_HOME>/models/<id>/` (mặc định `~/.vflow/models/<id>/`), không bao giờ trong repo.
 */
import { createHash, randomBytes } from 'node:crypto';
import { spawn } from 'node:child_process';
import fs from 'node:fs';
import fsp from 'node:fs/promises';
import path from 'node:path';
import { Readable } from 'node:stream';
import { pipeline } from 'node:stream/promises';
import { LOCAL_MODELS, REMOTE_MODELS, findModel, hasVerifiedChecksum, modelDir } from './registry.js';
import { SttError, modelUnavailable } from './errors.js';

const MANIFEST = 'manifest.json';

/**
 * @typedef {Record<string, string>} ModelFiles  đường dẫn tuyệt đối
 */

/**
 * Đọc manifest và trả đường dẫn tệp model; thiếu ⇒ `model_unavailable` có lý do.
 * @param {string} home
 * @param {string} id
 * @returns {Promise<{ dir: string, files: ModelFiles, manifest: any }>}
 */
export async function resolveModelFiles(home, id) {
  const spec = LOCAL_MODELS.find((m) => m.id === id);
  if (!spec) throw modelUnavailable('unknown_model', `Không có model cục bộ "${id}".`);
  const dir = modelDir(home, id);
  let manifest;
  try {
    manifest = JSON.parse(await fsp.readFile(path.join(dir, MANIFEST), 'utf8'));
  } catch (err) {
    if (/** @type {any} */ (err).code === 'ENOENT') {
      throw modelUnavailable('not_downloaded', `Model "${id}" chưa được tải. Chạy: vflow models pull ${id}`);
    }
    throw modelUnavailable('manifest_corrupt', `Manifest của model "${id}" hỏng: ${/** @type {Error} */ (err).message}`);
  }
  /** @type {any} */
  const files = {};
  for (const role of Object.keys(spec.files)) {
    const rel = manifest?.files?.[role]?.path;
    if (typeof rel !== 'string' || rel.includes('..') || path.isAbsolute(rel)) {
      throw modelUnavailable('manifest_corrupt', `Manifest của model "${id}" thiếu tệp ${role}.`);
    }
    const abs = path.join(dir, rel);
    try {
      const st = await fsp.stat(abs);
      if (!st.isFile() || st.size === 0) throw new Error('rỗng');
    } catch {
      throw modelUnavailable('files_missing', `Model "${id}" thiếu tệp ${rel}. Chạy lại: vflow models pull ${id}`);
    }
    files[role] = abs;
  }
  return { dir, files, manifest };
}

/**
 * @param {string} home
 * @returns {Promise<Array<{id:string, kind:string, title:string, downloaded?:boolean, path?:string, reason?:string, checksum?:string, license?:string}>>}
 */
export async function listModels(home) {
  const out = [];
  for (const spec of LOCAL_MODELS) {
    try {
      const { dir, manifest } = await resolveModelFiles(home, spec.id);
      out.push({
        id: spec.id, kind: 'local', title: spec.title, license: spec.license,
        downloaded: true, path: dir, checksum: manifest.checksum_status ?? 'không xác định',
      });
    } catch (err) {
      // 'not_downloaded' thường gợi ý chạy `models pull`; model thiếu checksum đã xác minh thì
      // pull sẽ bị chặn ngay (xem pullModel), nên báo đúng lý do đó để khỏi gây hiểu lầm.
      const reason = /** @type {any} */ (err).reason === 'not_downloaded' && !hasVerifiedChecksum(spec)
        ? 'checksum_unverified' : (/** @type {any} */ (err).reason ?? 'internal');
      out.push({ id: spec.id, kind: 'local', title: spec.title, license: spec.license, downloaded: false, reason });
    }
  }
  for (const spec of REMOTE_MODELS) out.push({ id: spec.id, kind: 'remote', title: spec.title });
  return out;
}

/**
 * Tải một URL vào tệp, vừa tải vừa băm. Không giữ toàn bộ trong RAM.
 * @param {string} url
 * @param {string} dest
 * @param {{ fetchImpl?: typeof fetch, onProgress?: (done:number,total:number|null)=>void }} opts
 * @returns {Promise<{ sha256: string, bytes: number }>}
 */
async function download(url, dest, { fetchImpl = fetch, onProgress }) {
  const res = await fetchImpl(url, { redirect: 'follow' });
  if (!res.ok || !res.body) throw new SttError('internal', `Tải ${url} lỗi: HTTP ${res.status}`);
  const total = Number(res.headers.get('content-length')) || null;
  const hash = createHash('sha256');
  let bytes = 0;
  let lastReport = 0;
  const src = Readable.fromWeb(/** @type {any} */ (res.body));
  src.on('data', (chunk) => {
    hash.update(chunk);
    bytes += chunk.length;
    if (onProgress && bytes - lastReport > 4 * 1024 * 1024) { lastReport = bytes; onProgress(bytes, total); }
  });
  await pipeline(src, fs.createWriteStream(dest, { flags: 'wx' }));
  onProgress?.(bytes, total);
  return { sha256: hash.digest('hex'), bytes };
}

/** @param {string} file */
async function sha256File(file) {
  const hash = createHash('sha256');
  await pipeline(fs.createReadStream(file), hash);
  return hash.digest('hex');
}

/** Giải nén tar.bz2 bằng tar hệ thống (bsdtar trên Windows 10+ và macOS; tự từ chối đường dẫn tuyệt đối/".."). */
function extractTar(archive, destDir) {
  const tarBin = process.platform === 'win32'
    ? path.join(process.env.SystemRoot ?? 'C:\\Windows', 'System32', 'tar.exe')
    : 'tar';
  return new Promise((resolve, reject) => {
    const p = spawn(tarBin, ['-xf', archive, '-C', destDir], { stdio: ['ignore', 'ignore', 'pipe'] });
    let err = '';
    p.stderr.on('data', (d) => { err += d; });
    p.on('error', reject);
    p.on('close', (code) => (code === 0 ? resolve(undefined) : reject(new Error(`tar lỗi (mã ${code}): ${err.trim()}`))));
  });
}

/**
 * Chọn tệp theo vai trò trong một thư mục; nhiều ứng viên thì ưu tiên bản int8.
 * @param {string[]} names
 * @param {RegExp} re
 */
function pickFile(names, re) {
  const c = names.filter((n) => re.test(n)).sort();
  if (c.length === 0) return null;
  return c.find((n) => n.includes('int8')) ?? c[0];
}

/**
 * Tải model về `<home>/models/<id>/`, kiểm sha256 và ghi manifest.
 * Thư mục cũ chỉ bị thay sau khi bản mới đã kiểm xong.
 * @param {string} home
 * @param {string} id
 * @param {{ fetchImpl?: typeof fetch, log?: (msg:string)=>void, force?: boolean }} [opts]
 * @returns {Promise<{ dir: string, manifest: any, warnings: string[] }>}
 */
export async function pullModel(home, id, opts = {}) {
  const log = opts.log ?? (() => {});
  const spec = findModel(id);
  if (!spec) throw new SttError('bad_request', `Không có model "${id}". Có: ${[...LOCAL_MODELS, ...REMOTE_MODELS].map((m) => m.id).join(', ')}`);
  if (spec.kind !== 'local') throw new SttError('bad_request', `Model "${id}" chạy từ xa, không cần tải.`);
  if (!hasVerifiedChecksum(spec)) {
    throw modelUnavailable('checksum_unverified', `Model "${id}" chưa có checksum đã xác minh (upstream không công bố, vflow chưa tự tải để băm); từ chối tải để không bỏ qua kiểm toàn vẹn.`);
  }
  const modelsRoot = path.join(home, 'models');
  await fsp.mkdir(modelsRoot, { recursive: true });
  const tag = `${id}.${process.pid}.${randomBytes(4).toString('hex')}`;
  const work = path.join(modelsRoot, `.tmp-${tag}`);
  const finalDir = modelDir(home, id);
  const newDir = path.join(modelsRoot, `.new-${tag}`);
  const oldDir = path.join(modelsRoot, `.old-${tag}`);
  /** @type {string[]} */
  const warnings = [];
  await fsp.mkdir(work);
  try {
    await fsp.mkdir(newDir);
    /** @type {any[]} */
    const sources = [];
    const progress = (name) => (done, total) =>
      log(`  ${name}: ${(done / 1048576).toFixed(1)}${total ? ` / ${(total / 1048576).toFixed(1)}` : ''} MB`);
    const check = (f, got) => {
      // hasVerifiedChecksum() đã chặn ở trên nếu f.sha256 trống; đến đây luôn có giá trị để đối chiếu.
      if (got !== f.sha256) {
        throw new SttError('internal', `Sai sha256 cho ${f.name}: mong đợi ${f.sha256}, nhận ${got}. Đã huỷ, không ghi model.`);
      }
      if (!/^github|^huggingface/.test(f.sha256Source ?? '')) {
        warnings.push(`${f.name}: không có checksum gốc từ upstream; khớp hash vflow đã ghim (${f.sha256Source}).`);
      }
      sources.push({ name: f.name, url: f.url, sha256: got, sha256_expected: f.sha256, sha256_source: f.sha256Source ?? null });
    };

    if (spec.source.type === 'archive') {
      const f = spec.source.file;
      const archive = path.join(work, f.name);
      log(`Tải ${f.url}`);
      const { sha256 } = await download(f.url, archive, { fetchImpl: opts.fetchImpl, onProgress: progress(f.name) });
      check(f, sha256);
      const ex = path.join(work, 'x');
      await fsp.mkdir(ex);
      log('Giải nén…');
      await extractTar(archive, ex);
      const root = path.join(ex, spec.source.root);
      const names = await fsp.readdir(root);
      for (const role of Object.keys(spec.files)) {
        const n = pickFile(names, spec.files[role]);
        if (!n) throw new SttError('internal', `Gói ${f.name} không có tệp ${role} (${spec.files[role]}).`);
        await fsp.rename(path.join(root, n), path.join(newDir, n));
      }
      for (const d of spec.keepDirs ?? []) {
        const src = path.join(root, d);
        if (fs.existsSync(src)) await fsp.rename(src, path.join(newDir, d));
      }
      for (const n of names.filter((x) => /^readme/i.test(x))) {
        if (fs.existsSync(path.join(root, n))) await fsp.rename(path.join(root, n), path.join(newDir, n));
      }
    } else {
      for (const f of spec.source.files) {
        log(`Tải ${f.url}`);
        const dest = path.join(newDir, f.saveAs ?? f.name);
        const { sha256 } = await download(f.url, dest, { fetchImpl: opts.fetchImpl, onProgress: progress(f.name) });
        check(f, sha256);
      }
    }

    const names = await fsp.readdir(newDir);
    /** @type {any} */
    const files = {};
    for (const role of Object.keys(spec.files)) {
      const n = pickFile(names, spec.files[role]);
      if (!n) throw new SttError('internal', `Thiếu tệp ${role} sau khi tải.`);
      files[role] = { path: n, sha256: await sha256File(path.join(newDir, n)) };
    }
    const allUpstream = sources.every((s) => s.sha256_expected && /^github|^huggingface/.test(s.sha256_source ?? ''));
    const manifest = {
      id, engine: spec.engine, title: spec.title, license: spec.license, homepage: spec.homepage,
      pulled_at: new Date().toISOString(),
      checksum_status: allUpstream ? 'khớp checksum upstream' : 'một phần không có checksum gốc (xem sources)',
      sources, files,
    };
    await fsp.writeFile(path.join(newDir, MANIFEST), JSON.stringify(manifest, null, 2) + '\n');

    const hadOld = fs.existsSync(finalDir);
    if (hadOld) await fsp.rename(finalDir, oldDir);
    try {
      await fsp.rename(newDir, finalDir);
    } catch (err) {
      if (hadOld) await fsp.rename(oldDir, finalDir);
      throw err;
    }
    await fsp.rm(oldDir, { recursive: true, force: true });
    return { dir: finalDir, manifest, warnings };
  } finally {
    await fsp.rm(work, { recursive: true, force: true });
    await fsp.rm(newDir, { recursive: true, force: true });
  }
}

/**
 * Băm lại tệp model và so với manifest (dùng cho `doctor`).
 * @param {string} home @param {string} id
 * @returns {Promise<{ ok: boolean, mismatched: string[] }>}
 */
export async function verifyModel(home, id) {
  const { dir, manifest } = await resolveModelFiles(home, id);
  const mismatched = [];
  for (const [role, f] of Object.entries(manifest.files)) {
    const got = await sha256File(path.join(dir, /** @type {any} */ (f).path));
    if (got !== /** @type {any} */ (f).sha256) mismatched.push(role);
  }
  return { ok: mismatched.length === 0, mismatched };
}
