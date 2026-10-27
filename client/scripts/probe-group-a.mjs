#!/usr/bin/env node
// Kiểm độc lập phía ENGINE của "Nhóm A" (teach, lưu âm thanh tuỳ chọn, ZIP, ký hiệu theo ngữ cảnh,
// cài đặt mới, không rò rỉ riêng tư). Chạy: node client/scripts/probe-group-a.mjs
//
// An toàn: dựng VFLOW_HOME + HOME giả trong thư mục tạm, chạy "node bin/vflow.js serve" ở cổng
// ngẫu nhiên 27800–27899 (KHÔNG BAO GIỜ 7611, KHÔNG đụng ~/.vflow thật). STT là một máy chủ STT từ xa GIẢ
// (contract/remote-stt.md) ở cổng tạm của hệ điều hành, trả chữ do script đặt — không cần model, không
// nặng RAM. Kết quả: bảng PASS/FAIL tiếng Việt, thoát mã 1 nếu có FAIL, 2 nếu không dựng được môi trường.
// Tự dọn (tắt engine, xoá thư mục tạm) kể cả khi lỗi. Không phụ thuộc gói ngoài.
import http from 'node:http';
import os from 'node:os';
import path from 'node:path';
import fs from 'node:fs';
import { spawn } from 'node:child_process';
import { createHash, randomBytes, randomInt } from 'node:crypto';
import { fileURLToPath } from 'node:url';

// VFLOW_PROBE_ENGINE_BIN (tuỳ chọn): trỏ tới bin/vflow.js của một BẢN SAO engine — dùng để thử phá có chủ đích
// (mutation) xem probe có thật sự bắt lỗi. Mặc định dùng bin/vflow.js của repo này.
const REPO = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..', '..');
const ENGINE_BIN = process.env.VFLOW_PROBE_ENGINE_BIN ? path.resolve(process.env.VFLOW_PROBE_ENGINE_BIN) : path.join(REPO, 'bin', 'vflow.js');
const REAL_VFLOW = path.join(os.homedir(), '.vflow');
const MARK = 'quasarlamp'; // từ mồi trong lời nói: KHÔNG được xuất hiện trong log/chẩn đoán/export
const HIST_BAIT = 'nhatkybimat9271'; // chuỗi mồi trong history.jsonl
const KEY_BAIT = `sk-probe-${randomBytes(12).toString('hex')}`; // "khoá 9Router" giả trong rewrite.key
const FAKE_REMOTE_TOKEN = `fake-${randomBytes(8).toString('hex')}`;

// ---------- ghi nhận kết quả ----------
/** @type {{ok:boolean, group:string, claim:string, obs:string}[]} */
const results = [];
let group = '';
function section(title) { group = title; process.stdout.write(`\n== ${title} ==\n`); }
/** @param {boolean} ok @param {string} claim @param {string} obs */
function check(ok, claim, obs = '') {
  results.push({ ok: !!ok, group, claim, obs });
  process.stdout.write(`${ok ? 'PASS' : 'FAIL'}  ${claim}${obs ? `  [quan sát: ${obs}]` : ''}\n`);
}
/** Chạy một nhóm kiểm; lỗi bất ngờ thành FAIL (không làm sập cả script, không im lặng). */
async function run(title, fn) {
  section(title);
  try { await fn(); } catch (e) { check(false, 'Nhóm kiểm chạy hết không gặp lỗi bất ngờ', String(e?.stack ?? e).split('\n').slice(0, 3).join(' | ')); }
}

// ---------- tiện ích HTTP ----------
/**
 * @param {number} port
 * @param {{method?:string, path:string, token?:string|null, headers?:Record<string,string>, body?:Buffer|string|null, host?:string}} o
 * @returns {Promise<{status:number, headers:http.IncomingHttpHeaders, body:Buffer, text:string, json:any}>}
 */
function request(port, { method = 'GET', path: p, token, headers = {}, body = null, host }) {
  return new Promise((resolve, reject) => {
    const h = { host: host ?? `127.0.0.1:${port}`, ...headers };
    if (token) h.authorization = `Bearer ${token}`;
    if (body !== null) h['content-length'] = String(Buffer.byteLength(body));
    const rq = http.request({ host: '127.0.0.1', port, method, path: p, headers: h, agent: false, timeout: 180000 }, (res) => {
      const chunks = [];
      res.on('data', (c) => chunks.push(c));
      res.on('end', () => {
        const buf = Buffer.concat(chunks);
        const text = buf.toString('utf8');
        let json = null;
        try { json = JSON.parse(text); } catch { /* không phải JSON */ }
        resolve({ status: res.statusCode ?? 0, headers: res.headers, body: buf, text, json });
      });
      res.on('error', reject);
    });
    rq.on('timeout', () => rq.destroy(new Error('hết thời gian chờ HTTP')));
    rq.on('error', reject);
    if (body !== null) rq.write(body);
    rq.end();
  });
}

// ---------- âm thanh tổng hợp (không dùng micro, không ghi đĩa) ----------
/** PCM16 LE mono: sóng sin 220 Hz đủ lớn để không bị coi là im lặng. @param {number} seconds @param {number} rate */
function tonePcm(seconds, rate = 16000) {
  const oneSec = Buffer.alloc(rate * 2);
  for (let i = 0; i < rate; i++) oneSec.writeInt16LE(Math.round(9000 * Math.sin((2 * Math.PI * 220 * i) / rate) + 3000 * Math.sin((2 * Math.PI * 551 * i) / rate)), i * 2);
  const whole = Math.floor(seconds);
  const frac = Math.round((seconds - whole) * rate) * 2;
  const out = Buffer.alloc(whole * oneSec.length + frac);
  for (let s = 0; s < whole; s++) oneSec.copy(out, s * oneSec.length);
  oneSec.copy(out, whole * oneSec.length, 0, frac);
  return out;
}
function silentPcm(seconds, rate = 16000) { return Buffer.alloc(Math.round(seconds * rate) * 2); }
/** @param {Buffer} pcm @param {number} rate */
function wavBytes(pcm, rate = 16000) {
  const h = Buffer.alloc(44);
  h.write('RIFF', 0); h.writeUInt32LE(36 + pcm.length, 4); h.write('WAVE', 8); h.write('fmt ', 12);
  h.writeUInt32LE(16, 16); h.writeUInt16LE(1, 20); h.writeUInt16LE(1, 22); h.writeUInt32LE(rate, 24);
  h.writeUInt32LE(rate * 2, 28); h.writeUInt16LE(2, 32); h.writeUInt16LE(16, 34); h.write('data', 36); h.writeUInt32LE(pcm.length, 40);
  return Buffer.concat([h, pcm]);
}
const L16 = 'audio/L16; rate=16000; channels=1';

// ---------- CRC32 và bộ đọc ZIP TỰ VIẾT (độc lập với engine/post/zip.js, không gọi unzip) ----------
const CRC_TABLE = (() => {
  const t = new Uint32Array(256);
  for (let n = 0; n < 256; n++) { let c = n; for (let k = 0; k < 8; k++) c = c & 1 ? 0xedb88320 ^ (c >>> 1) : c >>> 1; t[n] = c >>> 0; }
  return t;
})();
/** @param {Buffer} buf */
function crc32(buf) { let c = 0xffffffff; for (let i = 0; i < buf.length; i++) c = CRC_TABLE[(c ^ buf[i]) & 0xff] ^ (c >>> 8); return (c ^ 0xffffffff) >>> 0; }

/** @param {Buffer} buf @returns {{problems:string[], entries:{name:string, data:Buffer, crc:number, size:number}[]}} */
function parseZip(buf) {
  const problems = [];
  const entries = [];
  if (buf.length < 22) return { problems: [`quá ngắn (${buf.length} byte)`], entries };
  if (buf.readUInt32LE(0) !== 0x04034b50 && buf.readUInt32LE(0) !== 0x06054b50) problems.push('byte đầu không phải PK\\x03\\x04 (local header)');
  let eocd = -1;
  for (let i = buf.length - 22; i >= Math.max(0, buf.length - 22 - 65535); i--) if (buf.readUInt32LE(i) === 0x06054b50) { eocd = i; break; }
  if (eocd < 0) return { problems: [...problems, 'không có End Of Central Directory'], entries };
  const total = buf.readUInt16LE(eocd + 10);
  const cdSize = buf.readUInt32LE(eocd + 12);
  const cdOff = buf.readUInt32LE(eocd + 16);
  if (cdOff + cdSize !== eocd) problems.push(`central directory (${cdOff}+${cdSize}) không kết thúc đúng chỗ EOCD (${eocd})`);
  let p = cdOff;
  let expectLocal = 0;
  for (let n = 0; n < total; n++) {
    if (p + 46 > buf.length || buf.readUInt32LE(p) !== 0x02014b50) { problems.push(`mục central #${n} sai chữ ký`); break; }
    const flags = buf.readUInt16LE(p + 8);
    const method = buf.readUInt16LE(p + 10);
    const crc = buf.readUInt32LE(p + 16);
    const csize = buf.readUInt32LE(p + 20);
    const usize = buf.readUInt32LE(p + 24);
    const nl = buf.readUInt16LE(p + 28); const el = buf.readUInt16LE(p + 30); const cl = buf.readUInt16LE(p + 32);
    const lho = buf.readUInt32LE(p + 42);
    const name = buf.subarray(p + 46, p + 46 + nl).toString('utf8');
    p += 46 + nl + el + cl;
    if (method !== 0) problems.push(`${name}: method=${method} (kỳ vọng 0 = store)`);
    if (lho !== expectLocal) problems.push(`${name}: local header ở ${lho}, kỳ vọng ${expectLocal} (có khoảng trống/chồng lấn)`);
    if (lho + 30 > buf.length || buf.readUInt32LE(lho) !== 0x04034b50) { problems.push(`${name}: local header sai chữ ký`); continue; }
    const lnl = buf.readUInt16LE(lho + 26); const lel = buf.readUInt16LE(lho + 28);
    const lname = buf.subarray(lho + 30, lho + 30 + lnl).toString('utf8');
    if (lname !== name) problems.push(`${name}: tên local "${lname}" ≠ tên central`);
    const dstart = lho + 30 + lnl + lel;
    const data = buf.subarray(dstart, dstart + csize);
    if (data.length !== csize) problems.push(`${name}: thiếu dữ liệu`);
    if (csize !== usize) problems.push(`${name}: csize ${csize} ≠ usize ${usize} dù method=store`);
    const actual = crc32(data);
    if (actual !== crc) problems.push(`${name}: CRC32 central 0x${crc.toString(16)} ≠ tính lại 0x${actual.toString(16)}`);
    let end = dstart + csize;
    if (flags & 8) {
      let d = end;
      if (buf.readUInt32LE(d) === 0x08074b50) d += 4;
      const dcrc = buf.readUInt32LE(d); const dcs = buf.readUInt32LE(d + 4); const dus = buf.readUInt32LE(d + 8);
      if (dcrc !== crc || dcs !== csize || dus !== usize) problems.push(`${name}: data descriptor (crc 0x${dcrc.toString(16)}, ${dcs}/${dus}) lệch central`);
      end = d + 12;
    } else {
      const lcrc = buf.readUInt32LE(lho + 14);
      if (lcrc !== crc) problems.push(`${name}: CRC trong local header lệch central`);
    }
    expectLocal = end;
    entries.push({ name, data: Buffer.from(data), crc, size: usize });
  }
  if (expectLocal !== cdOff) problems.push(`vùng local kết thúc ở ${expectLocal}, central directory bắt đầu ở ${cdOff}`);
  return { problems, entries };
}

// ---------- STT từ xa GIẢ ----------
const fake = { text: 'xin chào các bạn', delayMs: 0, calls: 0 };
/** @type {http.Server} */
let fakeServer;
function startFakeStt() {
  fakeServer = http.createServer((rq, rs) => {
    const send = (code, obj) => { rs.writeHead(code, { 'content-type': 'application/json' }); rs.end(JSON.stringify(obj)); };
    if (rq.headers.authorization !== `Bearer ${FAKE_REMOTE_TOKEN}`) return send(401, { error: { code: 'unauthorized', message: 'sai token' } });
    if (rq.url === '/healthz') return send(200, { ok: true, model: 'phowhisper-large', loaded: true });
    if (rq.url?.startsWith('/v1/transcribe')) {
      rq.resume();
      rq.on('end', () => {
        fake.calls++;
        const t = fake.text;
        setTimeout(() => send(200, { text: t, audio_ms: 0, stt_ms: 1, model: 'phowhisper-large' }), fake.delayMs);
      });
      return undefined;
    }
    return send(404, { error: { code: 'bad_request', message: 'không có' } });
  });
  return new Promise((resolve, reject) => {
    fakeServer.once('error', reject);
    fakeServer.listen(0, '127.0.0.1', () => resolve(/** @type {any} */ (fakeServer.address()).port));
  });
}

// ---------- tiến trình engine ----------
let ROOT = ''; let HOME = ''; let FAKE_HOME = ''; let AUDIO_DIR = ''; let TOKEN = '';
/** @type {import('node:child_process').ChildProcess|null} */
let engine = null;
let enginePort = 0;
let engineLog = '';
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
const api = (o) => request(enginePort, { token: TOKEN, ...o });

async function startEngine() {
  for (let attempt = 0; attempt < 10; attempt++) {
    const port = 27800 + randomInt(0, 100);
    if (port === 7611) continue;
    const env = { ...process.env, VFLOW_HOME: HOME, HOME: FAKE_HOME, USERPROFILE: FAKE_HOME, VFLOW_REMOTE_TOKEN: FAKE_REMOTE_TOKEN };
    delete env.VFLOW_PORT;
    const child = spawn(process.execPath, [ENGINE_BIN, 'serve', '--port', String(port)], { env, stdio: ['ignore', 'ignore', 'pipe'] });
    child.stderr.setEncoding('utf8');
    child.stderr.on('data', (d) => { engineLog += d; });
    let exited = null;
    child.once('exit', (code, sig) => { exited = { code, sig }; });
    const deadline = Date.now() + 20000;
    let ready = false;
    while (Date.now() < deadline && !exited) {
      try { const r = await request(port, { path: '/healthz' }); if (r.status === 200) { ready = true; break; } } catch { /* chưa nghe */ }
      await sleep(100);
    }
    if (ready) {
      engine = child; enginePort = port;
      if (fs.existsSync(path.join(HOME, 'token'))) TOKEN = fs.readFileSync(path.join(HOME, 'token'), 'utf8').trim();
      return;
    }
    if (!exited) child.kill('SIGKILL');
    await sleep(150);
  }
  throw new Error('không khởi động được engine sau 10 lần thử cổng');
}
function stopEngine() {
  return new Promise((resolve) => {
    const c = engine;
    if (!c || c.exitCode !== null || c.signalCode !== null) { engine = null; return resolve(undefined); }
    const t = setTimeout(() => c.kill('SIGKILL'), 4000);
    c.once('exit', () => { clearTimeout(t); engine = null; resolve(undefined); });
    c.kill('SIGTERM');
    return undefined;
  });
}

// ---------- truy cập trạng thái đĩa ----------
const diskWavs = () => (fs.existsSync(AUDIO_DIR) ? fs.readdirSync(AUDIO_DIR).filter((n) => n.endsWith('.wav')).sort() : []);
const mode = (p) => (fs.statSync(p).mode & 0o777).toString(8);
const sha = (b) => createHash('sha256').update(b).digest('hex');
const fileSha = (p) => (fs.existsSync(p) ? sha(fs.readFileSync(p)) : null);
const putSettings = (patch) => api({ method: 'PUT', path: '/v1/settings', headers: { 'content-type': 'application/json' }, body: JSON.stringify(patch) });
const getSettings = async () => (await api({ path: '/v1/settings' })).json;
const listAudio = async () => (await api({ path: '/v1/audio' })).json;
const errCode = (r) => r.json?.error?.code;

/** Gửi một câu dictation qua /v1/transcribe với chữ do STT giả trả. */
async function dictate({ text = 'xin chào các bạn', app, mode: m = 'normal', pcm = tonePcm(2) }) {
  fake.text = text;
  const q = new URLSearchParams({ mode: m });
  if (app) q.set('app', app);
  return api({ method: 'POST', path: `/v1/transcribe?${q}`, headers: { 'content-type': L16 }, body: pcm });
}

// =====================================================================================
async function main() {
  ROOT = fs.mkdtempSync(path.join(os.tmpdir(), 'vflow-probe-a-'));
  HOME = path.join(ROOT, 'vflow-home');
  FAKE_HOME = path.join(ROOT, 'home');
  AUDIO_DIR = path.join(HOME, 'audio');
  fs.mkdirSync(HOME, { recursive: true, mode: 0o700 });
  fs.mkdirSync(FAKE_HOME, { recursive: true });
  if (path.resolve(HOME) === path.resolve(REAL_VFLOW) || !path.resolve(HOME).startsWith(path.resolve(os.tmpdir()))) throw new Error('VFLOW_HOME không nằm trong thư mục tạm — dừng.');

  const fakePort = await startFakeStt();
  fs.writeFileSync(path.join(HOME, 'rewrite.key'), `${KEY_BAIT}\n`, { mode: 0o600 });
  fs.writeFileSync(path.join(HOME, 'config.json'), JSON.stringify({
    default_model: 'phowhisper-large',
    remote: { phowhisper: { url: `http://127.0.0.1:${fakePort}` } },
    rewrite: { key_file: path.join(HOME, 'rewrite.key') },
    cloud_llm: false,
  }, null, 2), { mode: 0o600 });
  await startEngine();
  process.stdout.write(`Môi trường: engine 127.0.0.1:${enginePort} (cổng ngẫu nhiên, không phải 7611), STT giả 127.0.0.1:${fakePort}, VFLOW_HOME tạm (đã cô lập, HOME giả)\n`);
  fs.writeFileSync(path.join(HOME, 'history.jsonl'), `${JSON.stringify({ id: 'h_probe', at: new Date().toISOString(), appBundleId: 'com.apple.Notes', mode: 'normal', model: 'x', textRaw: HIST_BAIT, text: HIST_BAIT, audioMs: 1000 })}\n`, { mode: 0o600 });

  // ---------------------------------------------------------------- cài đặt
  await run('Cài đặt mới (context_symbols, audio_history*)', async () => {
    const d = await getSettings();
    check(d.audio_history === false && d.audio_history_mb === 200 && d.audio_history_days === 7 && d.context_symbols === true && !('vocab_boost' in d),
      'Mặc định: audio_history=false, mb=200, days=7, context_symbols=true; KHÔNG còn khoá vocab_boost (đã gỡ)',
      JSON.stringify({ ah: d.audio_history, mb: d.audio_history_mb, days: d.audio_history_days, cs: d.context_symbols, has_vocab_boost: 'vocab_boost' in d }));
    const gone = await putSettings({ vocab_boost: false });
    check(gone.status === 400, 'PUT vocab_boost (khoá đã gỡ) ⇒ 400 như mọi khoá lạ', `${gone.status} ${errCode(gone)}`);
    const bad = [
      ['audio_history_mb', 10], ['audio_history_mb', 49], ['audio_history_mb', 2001], ['audio_history_mb', 50.5], ['audio_history_mb', '100'], ['audio_history_mb', null],
      ['audio_history_days', 0], ['audio_history_days', 91], ['audio_history_days', 1.5], ['audio_history_days', '7'], ['audio_history_days', -1],
      ['audio_history', 'true'], ['audio_history', 1], ['context_symbols', 'false'], ['context_symbols', null],
    ];
    const accepted = [];
    for (const [k, v] of bad) {
      const r = await putSettings({ [k]: v });
      if (r.status !== 400 || errCode(r) !== 'bad_request') accepted.push(`${k}=${JSON.stringify(v)}→${r.status}`);
    }
    check(accepted.length === 0, `Giá trị sai miền/kiểu (${bad.length} ca) đều bị từ chối 400 bad_request`, accepted.length ? `lọt: ${accepted.join('; ')}` : `${bad.length}/${bad.length} bị từ chối`);
    const unknown = await putSettings({ audio_history_bogus: true });
    check(unknown.status === 400, 'Khoá lạ bị từ chối 400', `${unknown.status} ${errCode(unknown)}`);
    const mixed = await putSettings({ audio_history_days: 5, audio_history_mb: 10 });
    const after = await getSettings();
    check(mixed.status === 400 && after.audio_history_days === 7, 'PUT có một trường sai thì từ chối CẢ gói (days=5 không bị áp)', `status=${mixed.status} days=${after.audio_history_days}`);
    const ok1 = await putSettings({ audio_history_mb: 50, audio_history_days: 1, context_symbols: false, audio_history: true });
    const g1 = await getSettings();
    check(ok1.status === 200 && g1.audio_history_mb === 50 && g1.audio_history_days === 1 && g1.context_symbols === false && g1.audio_history === true,
      'Giá trị hợp lệ (biên dưới mb=50, days=1, các cờ bật/tắt) được lưu và đọc lại đúng', JSON.stringify({ mb: g1.audio_history_mb, days: g1.audio_history_days, cs: g1.context_symbols, ah: g1.audio_history }));
    const ok2 = await putSettings({ audio_history_mb: 2000, audio_history_days: 90 });
    const g2 = await getSettings();
    check(ok2.status === 200 && g2.audio_history_mb === 2000 && g2.audio_history_days === 90, 'Biên trên (mb=2000, days=90) hợp lệ', JSON.stringify({ mb: g2.audio_history_mb, days: g2.audio_history_days }));
    const cfg = JSON.parse(fs.readFileSync(path.join(HOME, 'config.json'), 'utf8'));
    check(cfg.default_model === 'phowhisper-large' && cfg.remote?.phowhisper?.url && cfg.audio_history_mb === 2000 && mode(path.join(HOME, 'config.json')) === '600',
      'config.json giữ khoá cũ (default_model, remote), có giá trị mới, quyền 0600', `mode=${mode(path.join(HOME, 'config.json'))} keys=${Object.keys(cfg).join(',')}`);
    check(!JSON.stringify(g2).includes(KEY_BAIT) && !JSON.stringify(g2).includes(TOKEN), 'GET /v1/settings không chứa token/khoá', 'không thấy chuỗi mồi');
    await putSettings({ audio_history: false, audio_history_mb: 200, audio_history_days: 7, context_symbols: true });
  });

  // ---------------------------------------------------------------- tắt lưu âm thanh
  await run('Lưu âm thanh: TẮT (mặc định)', async () => {
    const r = await dictate({ text: `chào ${MARK} bạn` });
    check(r.status === 200 && r.json?.text && !('audio_id' in r.json), 'Tắt ⇒ dictation thành công và KHÔNG có audio_id', `status=${r.status} audio_id=${JSON.stringify(r.json?.audio_id)} text="${r.json?.text}"`);
    check(diskWavs().length === 0, 'Tắt ⇒ không có tệp .wav nào trên đĩa', `${diskWavs().length} tệp, thư mục audio ${fs.existsSync(AUDIO_DIR) ? 'có' : 'chưa tạo'}`);
    const l = await listAudio();
    check(l.enabled === false && l.count === 0, 'GET /v1/audio báo enabled=false, count=0', JSON.stringify({ enabled: l.enabled, count: l.count }));
  });

  // ---------------------------------------------------------------- bật lưu âm thanh
  /** @type {string[]} */
  let ids = [];
  await run('Lưu âm thanh: BẬT, quyền tệp, nghe lại', async () => {
    await putSettings({ audio_history: true, audio_history_mb: 200, audio_history_days: 7 });
    for (let i = 0; i < 3; i++) {
      const r = await dictate({ text: `câu số ${i} ${MARK}`, pcm: tonePcm(1.5 + i) });
      if (r.json?.audio_id) ids.push(r.json.audio_id);
      check(r.status === 200 && typeof r.json?.audio_id === 'string' && r.json.audio_id === r.json.id, `Bật ⇒ dictation #${i + 1} có audio_id (= id của dictation)`, `status=${r.status} id=${r.json?.id} audio_id=${r.json?.audio_id}`);
    }
    const files = diskWavs();
    check(files.length === 3, 'Có đúng 3 tệp .wav trên đĩa', `${files.length}: ${files.join(',')}`);
    if (process.platform !== 'win32') {
      const bad = files.filter((f) => mode(path.join(AUDIO_DIR, f)) !== '600');
      check(bad.length === 0, 'Mọi tệp .wav quyền 0600', bad.length ? `sai: ${bad.map((f) => `${f}=${mode(path.join(AUDIO_DIR, f))}`)}` : files.map((f) => mode(path.join(AUDIO_DIR, f))).join(','));
      check(mode(AUDIO_DIR) === '700', 'Thư mục audio quyền 0700', mode(AUDIO_DIR));
      const idx = path.join(AUDIO_DIR, 'index.json');
      check(fs.existsSync(idx) && mode(idx) === '600', 'index.json quyền 0600', fs.existsSync(idx) ? mode(idx) : 'không có index.json');
      const leftovers = fs.readdirSync(AUDIO_DIR).filter((n) => n.includes('.tmp-'));
      check(leftovers.length === 0, 'Không để lại tệp tạm (.tmp-) trong thư mục audio', leftovers.join(',') || 'sạch');
    }
    const l = await listAudio();
    const onDiskBytes = files.reduce((s, f) => s + fs.statSync(path.join(AUDIO_DIR, f)).size, 0);
    const listIds = (l.items ?? []).map((i) => i.id).sort();
    check(l.count === files.length && l.bytes === onDiskBytes && JSON.stringify(listIds) === JSON.stringify(files.map((f) => f.slice(0, -4)).sort()),
      'GET /v1/audio khớp tệp thật (số lượng, id, tổng byte)', `list: count=${l.count} bytes=${l.bytes}; đĩa: ${files.length} tệp ${onDiskBytes} byte`);
    check(l.enabled === true && l.budget_bytes === 200 * 1048576 && l.days === 7, 'GET /v1/audio báo enabled/budget/days đúng', JSON.stringify({ enabled: l.enabled, budget_bytes: l.budget_bytes, days: l.days }));
    const sorted = (l.items ?? []).map((i) => Date.parse(i.at));
    check(sorted.every((t, i) => i === 0 || sorted[i - 1] >= t), 'Danh sách sắp mới nhất trước', 'đúng thứ tự giảm dần');
    // nghe lại
    const first = ids[0];
    const g = await api({ path: `/v1/audio/${first}` });
    const disk = fs.readFileSync(path.join(AUDIO_DIR, `${first}.wav`));
    const w = g.body;
    check(g.status === 200 && /audio\/wav/.test(String(g.headers['content-type'])) && Buffer.compare(w, disk) === 0,
      'GET /v1/audio/<id> trả đúng byte tệp WAV, content-type audio/wav', `status=${g.status} type=${g.headers['content-type']} ${w.length}/${disk.length} byte`);
    const okHeader = w.length > 44 && w.toString('latin1', 0, 4) === 'RIFF' && w.toString('latin1', 8, 12) === 'WAVE' && w.readUInt16LE(20) === 1 && w.readUInt16LE(22) === 1 && w.readUInt32LE(24) === 16000 && w.readUInt16LE(34) === 16
      && w.readUInt32LE(40) === w.length - 44;
    check(okHeader, 'Tệp lưu là WAV hợp lệ 16 kHz mono 16-bit, kích thước data khớp', `${w.length} byte, rate=${w.readUInt32LE(24)}`);
    // khi nghe lại không để lại hậu quả: vẫn 3 tệp
    check(diskWavs().length === 3, 'Nghe lại không làm mất/đổi tệp', `${diskWavs().length} tệp`);
    // im lặng không tạo tệp/audio_id
    const sil = await dictate({ text: 'bình thường', pcm: silentPcm(2) });
    check(sil.status === 200 && sil.json?.silence === true && !('audio_id' in sil.json) && diskWavs().length === 3, 'Âm im lặng ⇒ silence:true, không audio_id, không tạo tệp', `status=${sil.status} silence=${sil.json?.silence} audio_id=${sil.json?.audio_id} tệp=${diskWavs().length}`);
  });

  // ---------------------------------------------------------------- xác thực
  await run('Xác thực: endpoint mới từ chối khi thiếu/sai token', async () => {
    const before = diskWavs();
    const calls0 = fake.calls;
    const first = ids[0];
    const eps = [
      ['POST', '/v1/teach', tonePcm(1)], ['GET', '/v1/audio', null], ['DELETE', '/v1/audio', null], ['GET', '/v1/audio/', null],
      ['GET', `/v1/audio/${first}`, null], ['DELETE', `/v1/audio/${first}`, null], ['GET', '/v1/audio/export', null],
    ];
    for (const [method, p, body] of eps) {
      const none = await request(enginePort, { method, path: p, body, headers: { 'content-type': L16 } });
      const wrong = await request(enginePort, { method, path: p, token: 'sai-token-0000', body, headers: { 'content-type': L16 } });
      const ok = none.status === 401 && wrong.status === 401 && errCode(none) === 'unauthorized' && errCode(wrong) === 'unauthorized';
      check(ok, `${method} ${p.replace(first, '<id>')} thiếu/sai token ⇒ 401 unauthorized`, `thiếu=${none.status}/${errCode(none)} sai=${wrong.status}/${errCode(wrong)}`);
    }
    const after = diskWavs();
    check(JSON.stringify(before) === JSON.stringify(after) && fake.calls === calls0, 'Yêu cầu bị từ chối KHÔNG xoá tệp và KHÔNG gọi STT', `tệp ${before.length}→${after.length}, gọi STT +${fake.calls - calls0}`);
    const badHost = await request(enginePort, { path: '/v1/audio', token: TOKEN, host: 'evil.example.com' });
    check(badHost.status === 403, 'Host lạ ⇒ 403 (chống DNS rebinding) trên /v1/audio', `${badHost.status}`);
    const origin = await request(enginePort, { path: '/v1/audio', token: TOKEN, headers: { origin: 'http://evil.example.com' } });
    check(origin.status === 403 && origin.headers['access-control-allow-origin'] === undefined, 'Có header Origin ⇒ 403 và không có CORS header', `${origin.status}, ACAO=${origin.headers['access-control-allow-origin']}`);
  });

  // ---------------------------------------------------------------- teach
  await run('/v1/teach (dạy từ bằng giọng)', async () => {
    await putSettings({ audio_history: true });
    // từ điển để chứng minh teach trả chữ THÔ còn dictation thì qua từ điển
    const put = await api({ method: 'PUT', path: '/v1/dictionary', headers: { 'content-type': 'application/json' }, body: JSON.stringify({ entries: [{ term: 'deploy', spoken: ['đi plôi'], kind: 'term' }] }) });
    check(put.status === 200, 'Đặt từ điển thử (deploy ⇐ "đi plôi")', `${put.status} ${put.json?.error?.message ?? ''}`);
    const teachPost = (body, ct = L16, q = '') => api({ method: 'POST', path: `/v1/teach${q}`, headers: { 'content-type': ct }, body });
    const snap = async () => {
      const st = (await api({ path: '/v1/stats' })).json;
      const dict = (await api({ path: '/v1/dictionary' })).json;
      return {
        history: fileSha(path.join(HOME, 'history.jsonl')), stats: fileSha(path.join(HOME, 'stats.json')),
        statsCounters: JSON.stringify({ c: st.total_count, w: st.total_words, a: st.total_audio_ms }),
        audioList: JSON.stringify(((await listAudio()).items ?? []).map((i) => i.id)), disk: diskWavs().join(','),
        uses: JSON.stringify(dict.entries.map((e) => [e.term, e.uses])), dictFile: fileSha(path.join(HOME, 'dictionary.json')),
      };
    };

    fake.text = 'Đi  Plôi   Xong';
    fake.delayMs = 0;
    const dic = await dictate({ text: 'đi plôi xong', pcm: tonePcm(1) });
    check(dic.json?.text?.toLowerCase().includes('deploy'), 'Đối chứng: cùng chữ qua /v1/transcribe thì từ điển có áp (deploy)', `text="${dic.json?.text}"`);
    const before = await snap(); // chụp trạng thái SAU đối chứng, TRƯỚC mọi lần gọi teach
    const ok = await teachPost(tonePcm(3));
    check(ok.status === 200 && ok.json?.heard === 'đi plôi xong' && ok.json.audio_ms === 3000, 'Teach hợp lệ ⇒ 200, heard là CHỮ THÔ chuẩn hoá (thường, gọn khoảng trắng), KHÔNG qua từ điển', JSON.stringify(ok.json));
    // định dạng sai
    const wrong = [
      ['Content-Type text/plain', Buffer.from('hello'), 'text/plain'],
      ['không có Content-Type', tonePcm(1), ''],
      ['WAV rác 100 byte', randomBytes(100), 'audio/wav'],
      ['L16 độ dài lẻ (3 byte)', Buffer.from([1, 2, 3]), L16],
      ['L16 rate=0', tonePcm(1), 'audio/L16; rate=0; channels=1'],
      ['L16 channels=0', tonePcm(1), 'audio/L16; rate=16000; channels=0'],
    ];
    for (const [name, body, ct] of wrong) {
      const r = await api({ method: 'POST', path: '/v1/teach', headers: ct ? { 'content-type': ct } : {}, body });
      const msg = r.json?.error?.message;
      check(r.status === 400 && errCode(r) === 'bad_audio' && typeof msg === 'string' && msg.length > 5, `Sai định dạng (${name}) ⇒ 400 bad_audio kèm thông báo`, `${r.status} ${errCode(r)} "${String(msg ?? r.text).slice(0, 70)}"`);
    }
    const afterBad = await teachPost(tonePcm(1));
    check(afterBad.status === 200, 'Sau các lỗi định dạng, teach vẫn nhận yêu cầu mới (không kẹt cờ bận)', `${afterBad.status}`);
    // độ dài
    const c1 = fake.calls;
    const long = await teachPost(tonePcm(15.5));
    check(long.status === 413 && errCode(long) === 'too_long' && fake.calls === c1, 'Audio 15,5 s ⇒ 413 too_long, KHÔNG gọi STT (không cắt ngầm)', `${long.status} ${errCode(long)} "${long.json?.error?.message?.slice(0, 60)}" gọi STT +${fake.calls - c1}`);
    const edge = await teachPost(tonePcm(15));
    check(edge.status === 200, 'Audio đúng 15,0 s vẫn được nhận (biên)', `${edge.status} ${JSON.stringify(edge.json)?.slice(0, 80)}`);
    const wav44 = await teachPost(wavBytes(tonePcm(14, 44100), 44100), 'audio/wav');
    check(wav44.status === 200 && wav44.json?.audio_ms === 14000, 'WAV 44,1 kHz dài 14 s ⇒ 200, độ dài tính theo tần số lấy mẫu', `${wav44.status} audio_ms=${wav44.json?.audio_ms}`);
    const wav8 = await teachPost(wavBytes(tonePcm(16, 8000), 8000), 'audio/wav');
    check(wav8.status === 413 && errCode(wav8) === 'too_long', 'WAV 8 kHz dài 16 s (chỉ ~256 KB) ⇒ vẫn 413 (đo theo thời lượng, không theo byte)', `${wav8.status} ${errCode(wav8)}`);
    const sil = await teachPost(silentPcm(2));
    check(sil.status === 200 && sil.json?.heard === '', 'Âm im lặng ⇒ 200 heard rỗng (không bịa chữ)', JSON.stringify(sil.json));
    // đồng thời
    fake.delayMs = 900;
    fake.text = 'một hai ba';
    const A = teachPost(tonePcm(2));
    await sleep(200);
    const B = await teachPost(tonePcm(2));
    const Ar = await A;
    check(Ar.status === 200 && B.status === 429 && errCode(B) === 'busy', 'Hai yêu cầu đồng thời ⇒ một cái 200, một cái 429 busy', `A=${Ar.status}, B=${B.status}/${errCode(B)}`);
    fake.delayMs = 0;
    const C = await teachPost(tonePcm(1));
    check(C.status === 200, 'Sau khi xong, yêu cầu kế tiếp lại được nhận (cờ bận đã nhả)', `${C.status}`);
    // không tác dụng phụ: so toàn bộ trạng thái trước/sau MỌI lần gọi teach ở trên (thành công lẫn lỗi)
    const after = await snap();
    const diff = Object.keys(before).filter((k) => before[k] !== after[k]);
    check(diff.length === 0, 'Teach (mọi lần gọi ở trên, cả thành công lẫn lỗi, audio_history đang BẬT) KHÔNG ghi history.jsonl/stats/từ điển(uses)/tệp âm thanh',
      diff.length ? `thay đổi: ${diff.map((k) => `${k}: ${before[k]} → ${after[k]}`).join('; ')}` : `không đổi (${Object.keys(after).length} chỉ số: history, stats.json, bộ đếm, danh sách+đĩa audio, uses, dictionary.json)`);
    // dọn từ điển thử
    await api({ method: 'PUT', path: '/v1/dictionary', headers: { 'content-type': 'application/json' }, body: JSON.stringify({ entries: [] }) });
  });

  // ---------------------------------------------------------------- ZIP
  await run('Xuất ZIP âm thanh (/v1/audio/export)', async () => {
    const files = diskWavs();
    const r = await api({ path: '/v1/audio/export' });
    check(r.status === 200 && /application\/zip/.test(String(r.headers['content-type'])), 'GET /v1/audio/export ⇒ 200 application/zip', `${r.status} ${r.headers['content-type']} ${r.body.length} byte`);
    const z = parseZip(r.body);
    check(z.problems.length === 0, 'Cấu trúc ZIP hợp lệ: PK\\x03\\x04, central directory, EOCD, CRC32 từng tệp khớp, không hở/chồng vùng', z.problems.length ? z.problems.join(' | ') : `${z.entries.length} mục, CRC khớp hết`);
    const wavEntries = z.entries.filter((e) => e.name.endsWith('.wav'));
    check(wavEntries.length === files.length && z.entries.some((e) => e.name === 'index.json') && z.entries.length === files.length + 1,
      'Chứa đúng số tệp (mỗi WAV trên đĩa + index.json)', `ZIP: ${wavEntries.length} wav + ${z.entries.length - wavEntries.length} khác; đĩa: ${files.length}`);
    const same = wavEntries.every((e) => fs.existsSync(path.join(AUDIO_DIR, e.name)) && Buffer.compare(e.data, fs.readFileSync(path.join(AUDIO_DIR, e.name))) === 0);
    check(same, 'Byte từng WAV trong ZIP giống hệt tệp trên đĩa', same ? 'khớp' : 'có tệp khác nội dung/không có trên đĩa');
    const names = z.entries.map((e) => e.name);
    check(new Set(names).size === names.length && names.every((n) => /^[A-Za-z0-9_-]+\.(wav|json)$/.test(n)), 'Tên mục an toàn (không có / \\ .., không trùng)', names.join(','));
    const idxEntry = z.entries.find((e) => e.name === 'index.json');
    let idx = null;
    try { idx = JSON.parse(idxEntry?.data.toString('utf8') ?? ''); } catch { /* xử lý ở dưới */ }
    const arr = Array.isArray(idx) ? idx : idx?.items;
    const allowedKeys = new Set(['id', 'at', 'audio_ms', 'app', 'mode', 'bytes']);
    const stray = (arr ?? []).flatMap((o) => Object.keys(o).filter((k) => !allowedKeys.has(k) || /text|transcript|heard|raw|content|body/i.test(k)));
    const longStr = (arr ?? []).some((o) => Object.values(o).some((v) => typeof v === 'string' && v.length > 80));
    check(Array.isArray(arr) && arr.length === files.length && stray.length === 0 && !longStr && !idxEntry.data.toString('utf8').includes(MARK),
      'index.json parse được, đủ mục, KHÔNG có trường văn bản (không "text"/"transcript"…, không chuỗi dài, không lời đã nói)', Array.isArray(arr) ? `${arr.length} mục, khoá: ${[...new Set((arr ?? []).flatMap((o) => Object.keys(o)))].join(',')}${stray.length ? `, KHOÁ LẠ: ${stray.join(',')}` : ''}` : 'index.json không đúng dạng');
    check(!r.body.toString('latin1').includes(MARK), 'ZIP không chứa chữ đã nói (từ mồi)', 'không thấy');
  });

  // ---------------------------------------------------------------- rò rỉ
  await run('Rò rỉ riêng tư: /v1/export, /v1/diagnostics', async () => {
    // tạo vài lỗi thật để recent_errors có dữ liệu
    await dictate({ text: `lỗi ${MARK}`, pcm: Buffer.from('rác') }).catch(() => {});
    await api({ method: 'POST', path: '/v1/transcribe?mode=khongco', headers: { 'content-type': L16 }, body: tonePcm(1) });
    await dictate({ text: `kiểm rò rỉ ${MARK} gạch chéo`, app: 'com.apple.Notes' });
    const file = diskWavs()[0];
    const wavFile = fs.readFileSync(path.join(AUDIO_DIR, file));
    const chunk = wavFile.subarray(2000, 2064);
    const needles = {
      'token': TOKEN, 'khoá rewrite.key': KEY_BAIT, 'token STT giả': FAKE_REMOTE_TOKEN,
      'đường dẫn VFLOW_HOME tạm': HOME, 'đường dẫn thư mục tạm gốc': ROOT, 'HOME giả': FAKE_HOME, 'home thật': os.homedir(), '"RIFF"': 'RIFF', '"WAVEfmt"': 'WAVEfmt',
    };
    const realTmp = fs.realpathSync(ROOT);
    if (realTmp !== ROOT) needles['đường dẫn tạm (realpath)'] = realTmp;
    const bodies = {
      'export (mặc định)': (await api({ path: '/v1/export' })),
      'export?include_history=0': (await api({ path: '/v1/export?include_history=0' })),
      'diagnostics': (await api({ path: '/v1/diagnostics' })),
      'settings': (await api({ path: '/v1/settings' })),
      'healthz': (await request(enginePort, { path: '/healthz' })),
      'lỗi 401': (await request(enginePort, { path: '/v1/export' })),
      'lỗi 404 audio': (await api({ path: '/v1/audio/khongco' })),
    };
    for (const [bn, r] of Object.entries(bodies)) {
      const hay = r.body.toString('latin1');
      const hayU = r.text;
      const hits = Object.entries(needles).filter(([, v]) => v && (hay.includes(v) || hayU.includes(v))).map(([k]) => k);
      const audioHits = [];
      if (hay.includes(chunk.toString('latin1'))) audioHits.push('byte thô');
      if (hay.includes(chunk.toString('base64'))) audioHits.push('base64');
      if (hay.includes(chunk.toString('hex'))) audioHits.push('hex');
      check(hits.length === 0 && audioHits.length === 0, `${bn}: không chứa token/khoá/đường dẫn tuyệt đối/byte âm thanh`, hits.length || audioHits.length ? `RÒ RỈ: ${[...hits, ...audioHits].join(', ')}` : `${r.status}, ${r.body.length} byte sạch`);
    }
    const ex = bodies['export (mặc định)'];
    const diag = bodies.diagnostics;
    check(!ex.text.includes(HIST_BAIT) && !ex.text.includes(MARK) && !diag.text.includes(HIST_BAIT) && !diag.text.includes(MARK),
      'export mặc định và diagnostics không chứa văn bản history hay lời vừa đọc', 'không thấy chuỗi mồi');
    const keys = Object.keys(ex.json ?? {});
    check(ex.json?.format === 'vflow-export' && !('history' in (ex.json ?? {})) && !keys.some((k) => /audio|wav|token|key/i.test(k)), 'export mặc định không có phần history, không có phần âm thanh/token', `khoá: ${keys.join(',')}`);
    const withHist = await api({ path: '/v1/export?include_history=1' });
    const hhits = [['token', TOKEN], ['khoá', KEY_BAIT], ['home thật', os.homedir()], ['VFLOW_HOME tạm', HOME], ['RIFF', 'RIFF']].filter(([, v]) => withHist.text.includes(v)).map(([k]) => k);
    check(hhits.length === 0, 'export?include_history=1 (người dùng chủ động) vẫn không chứa token/khoá/đường dẫn/byte âm thanh', hhits.length ? `RÒ RỈ: ${hhits}` : `có history theo thiết kế: ${withHist.text.includes(HIST_BAIT) ? 'có' : 'KHÔNG'} chữ mồi; không có bí mật`);
    const recent = diag.json?.recent_errors ?? [];
    check(recent.length > 0 && recent.every((e) => Object.keys(e).sort().join() === 'at,code,route,status'), 'diagnostics.recent_errors chỉ gồm {at,route,status,code} và có dữ liệu thật', `${recent.length} dòng, ví dụ ${JSON.stringify(recent[0])}`);
    process.stdout.write(`      (thông tin) diagnostics.counts=${JSON.stringify(diag.json?.counts)} paths=${JSON.stringify(diag.json?.paths)}\n`);
  });

  // ---------------------------------------------------------------- path traversal + xoá
  await run('Xoá và path traversal', async () => {
    const canary = path.join(HOME, 'canary.txt');
    fs.writeFileSync(canary, 'CANARY-NGOAI-THU-MUC-AUDIO');
    const victims = [canary, path.join(HOME, 'token'), path.join(HOME, 'config.json'), path.join(HOME, 'history.jsonl')];
    const victimHash = victims.map(fileSha);
    const filesBefore = diskWavs();
    const nasty = [
      '..%2f..%2ftoken', '%2e%2e%2f%2e%2e%2ftoken', '..%2fcanary.txt', '%2e%2e%2fcanary.txt', '..%5c..%5ctoken', 'a%2fb', 'a%5cb', 'a%00b', '%00',
      'x.wav', `${filesBefore[0]}`, 'index', 'index.json', '..', '%2e%2e', 'caf%C3%A9', '%E2%80%AE', '..%252f..%252ftoken', 'a%20b', ';ls', '*',
    ];
    const leaked = []; const wrongStatus = [];
    for (const id of nasty) {
      for (const method of ['GET', 'DELETE']) {
        const r = await api({ method, path: `/v1/audio/${id}` });
        if (r.status !== 404) wrongStatus.push(`${method} ${id}→${r.status}`);
        if (r.text.includes(TOKEN) || r.text.includes('CANARY-NGOAI') || r.text.includes('"default_model"') || r.text.includes(HIST_BAIT)) leaked.push(`${method} ${id}`);
      }
    }
    // dạng đường dẫn thô không mã hoá (client HTTP không chuẩn hoá)
    for (const raw of ['/v1/audio/../token', '/v1/audio/../../token', '/v1/audio/./../canary.txt', '/v1/audio//token', '/v1/audio/%2e%2e/token']) {
      for (const method of ['GET', 'DELETE']) {
        const r = await api({ method, path: raw });
        if (r.status === 200 || r.text.includes(TOKEN) || r.text.includes('CANARY-NGOAI')) leaked.push(`${method} ${raw}→${r.status}`);
        if (method === 'GET' && ![404, 400].includes(r.status)) wrongStatus.push(`${raw}→${r.status}`);
      }
    }
    check(wrongStatus.length === 0, `Id lạ/traversal (${nasty.length} dạng × GET/DELETE) ⇒ 404`, wrongStatus.length ? `sai: ${wrongStatus.join('; ')}` : 'tất cả 404');
    check(leaked.length === 0, 'KHÔNG đọc được token/canary/config/history ngoài thư mục audio qua traversal', leaked.length ? `RÒ RỈ: ${leaked.join('; ')}` : 'không rò');
    const intact = victims.map(fileSha);
    check(JSON.stringify(intact) === JSON.stringify(victimHash) && JSON.stringify(diskWavs()) === JSON.stringify(filesBefore), 'Traversal/DELETE lạ không xoá hay sửa tệp nào (token, config, history, canary, các WAV)', `canary ${fs.existsSync(canary) ? 'còn' : 'MẤT'}, WAV ${filesBefore.length}→${diskWavs().length}`);
    const notAll = await api({ method: 'DELETE', path: '/v1/audio/export' });
    check(diskWavs().length === filesBefore.length && notAll.status !== 200, 'DELETE /v1/audio/export không xoá gì (không bị hiểu nhầm là id)', `status=${notAll.status}, WAV ${diskWavs().length}`);
    fs.rmSync(canary);

    // xoá một
    const l0 = await listAudio();
    const target = l0.items[0].id;
    const other = l0.items.slice(1).map((i) => i.id);
    const d1 = await api({ method: 'DELETE', path: `/v1/audio/${target}` });
    check(d1.status === 200 && d1.json?.ok === true && !fs.existsSync(path.join(AUDIO_DIR, `${target}.wav`)), 'DELETE /v1/audio/<id> ⇒ 200 và tệp thật biến mất khỏi đĩa', `${d1.status} ${JSON.stringify(d1.json)}, tệp ${fs.existsSync(path.join(AUDIO_DIR, `${target}.wav`)) ? 'CÒN' : 'đã mất'}`);
    const d2 = await api({ method: 'DELETE', path: `/v1/audio/${target}` });
    const g2 = await api({ path: `/v1/audio/${target}` });
    check(d2.status === 404 && errCode(d2) === 'not_found' && g2.status === 404, 'Xoá lần hai / nghe lại id đã xoá ⇒ 404 not_found', `DELETE ${d2.status}/${errCode(d2)}, GET ${g2.status}`);
    const l1 = await listAudio();
    check(l1.count === l0.count - 1 && other.every((id) => fs.existsSync(path.join(AUDIO_DIR, `${id}.wav`))) && !l1.items.some((i) => i.id === target), 'Các tệp khác còn nguyên, danh sách giảm đúng 1', `count ${l0.count}→${l1.count}`);
    const unk = await api({ method: 'DELETE', path: '/v1/audio/tr_khongtontai' });
    check(unk.status === 404 && errCode(unk) === 'not_found', 'DELETE id lạ hợp lệ định dạng ⇒ 404 not_found', `${unk.status} ${errCode(unk)}`);
    const idxAfter = JSON.parse(fs.readFileSync(path.join(AUDIO_DIR, 'index.json'), 'utf8'));
    check((idxAfter.items ?? []).length === l1.count && !(idxAfter.items ?? []).some((i) => i.id === target), 'index.json trên đĩa cập nhật theo (không còn mục đã xoá)', `${(idxAfter.items ?? []).length} mục`);
    // xoá tất cả
    const dAll = await api({ method: 'DELETE', path: '/v1/audio' });
    const lAll = await listAudio();
    check(dAll.status === 200 && dAll.json?.ok === true && diskWavs().length === 0 && lAll.count === 0 && lAll.bytes === 0, 'DELETE /v1/audio xoá hết: 200, 0 tệp .wav trên đĩa, danh sách rỗng', `${dAll.status} ${JSON.stringify(dAll.json)}, đĩa ${diskWavs().length} tệp, list ${lAll.count}`);
    const zip0 = await api({ path: '/v1/audio/export' });
    const z0 = parseZip(zip0.body);
    check(zip0.status === 200 && z0.problems.length === 0 && z0.entries.length === 1 && z0.entries[0].name === 'index.json' && z0.entries[0].data.toString().trim().startsWith('[]'),
      'Export khi kho rỗng ⇒ ZIP hợp lệ chỉ có index.json rỗng (không lỗi)', `${zip0.status}, ${z0.entries.map((e) => e.name)} ${z0.problems.join('|')}`);
    const dAll2 = await api({ method: 'DELETE', path: '/v1/audio' });
    check(dAll2.status === 200 && dAll2.json?.deleted === 0, 'Xoá hết khi đã rỗng ⇒ 200 deleted=0 (không lỗi)', JSON.stringify(dAll2.json));
  });

  // ---------------------------------------------------------------- ngân sách
  await run('Ngân sách dung lượng (audio_history_mb=50, days=1)', async () => {
    await putSettings({ audio_history: true, audio_history_mb: 50, audio_history_days: 1 });
    const budget = 50 * 1048576;
    const made = [];
    const pcm = tonePcm(700); // ~22,4 MB mỗi tệp
    for (let i = 0; i < 4; i++) {
      const r = await dictate({ text: `dài ${i} ${MARK}`, pcm });
      made.push(r.json?.audio_id ?? null);
      await sleep(30);
    }
    check(made.every(Boolean), 'Bốn dictation 700 s đều thành công kèm audio_id', `status ok, ${made.filter(Boolean).length}/4 có audio_id`);
    const files = diskWavs();
    const total = files.reduce((s, f) => s + fs.statSync(path.join(AUDIO_DIR, f)).size, 0);
    const l = await listAudio();
    const expectKept = made.slice(-2);
    check(total <= budget && l.bytes <= budget, 'Tổng dung lượng thật trên đĩa ≤ ngân sách 50 MB', `${(total / 1048576).toFixed(1)} MB trên đĩa, list.bytes=${(l.bytes / 1048576).toFixed(1)} MB, ngân sách ${budget / 1048576} MB`);
    check(files.length === 2 && JSON.stringify(files.map((f) => f.slice(0, -4)).sort()) === JSON.stringify([...expectKept].sort()),
      'Tệp CŨ NHẤT bị đuổi trước (còn đúng 2 tệp mới nhất)', `còn ${files.length}: ${files.map((f) => made.indexOf(f.slice(0, -4)) + 1).sort()} (thứ tự tạo 1..4), kỳ vọng [3,4]`);
    check(l.count === files.length && l.bytes === total, 'GET /v1/audio khớp sau khi đuổi', `count=${l.count}/${files.length} bytes=${l.bytes}/${total}`);
    const gone = await api({ path: `/v1/audio/${made[0]}` });
    check(gone.status === 404, 'Nghe lại tệp đã bị đuổi ⇒ 404 (không đứt giữa chừng)', `${gone.status}`);
    await api({ method: 'DELETE', path: '/v1/audio' });
  });

  // ---------------------------------------------------------------- hạn ngày
  await run('Hạn ngày (audio_history_days=1) và dọn khi khởi động', async () => {
    // tạo hai tệp thật rồi dừng engine để dựng tình huống quá hạn
    const keepA = (await dictate({ text: `giữ ${MARK}`, pcm: tonePcm(1) })).json?.audio_id;
    await stopEngine();
    const now = Date.now();
    const small = wavBytes(tonePcm(1));
    const mk = (id, ageHours, inIndex, entries) => {
      const p = path.join(AUDIO_DIR, `${id}.wav`);
      fs.writeFileSync(p, small, { mode: 0o600 });
      const t = new Date(now - ageHours * 3600 * 1000);
      fs.utimesSync(p, t, t);
      if (inIndex) entries.push({ id, at: t.toISOString(), audio_ms: 1000, bytes: small.length, app: null, mode: 'normal' });
    };
    const idxPath = path.join(AUDIO_DIR, 'index.json');
    const idx = JSON.parse(fs.readFileSync(idxPath, 'utf8'));
    mk('tr_het_han_72h', 72, true, idx.items);
    mk('tr_het_han_25h', 25, true, idx.items);
    mk('tr_con_han_23h', 23, true, idx.items);
    mk('tr_mo_coi_100h', 100, false, []); // có tệp, không có trong mục lục, mtime rất cũ
    fs.writeFileSync(idxPath, JSON.stringify(idx, null, 2));
    check(diskWavs().length === 5, 'Dựng tình huống: 5 tệp (1 mới, 23h, 25h, 72h, 1 mồ côi 100h)', diskWavs().join(','));
    await startEngine();
    const set = await getSettings();
    check(set.audio_history_mb === 50 && set.audio_history_days === 1 && set.audio_history === true, 'Cài đặt giữ nguyên sau khi khởi động lại engine (đọc từ config.json)', JSON.stringify({ mb: set.audio_history_mb, days: set.audio_history_days }));
    const files = diskWavs().map((f) => f.slice(0, -4)).sort();
    const l = await listAudio();
    check(!files.includes('tr_het_han_72h') && !files.includes('tr_het_han_25h'), 'Tệp quá hạn (25h, 72h, mtime cũ) bị dọn khỏi đĩa lúc khởi động', `còn: ${files.join(',')}`);
    check(files.includes('tr_con_han_23h') && files.includes(keepA), 'Tệp chưa quá hạn (23h) và tệp mới KHÔNG bị dọn nhầm', `còn: ${files.join(',')}`);
    check(!files.includes('tr_mo_coi_100h'), 'Tệp mồ côi hợp lệ nhưng mtime 100h: được nhận lại rồi bị dọn vì QUÁ HẠN (theo mtime), không phải vì "mồ côi"', `còn: ${files.join(',')}`);
    check(l.count === files.length && !(l.items ?? []).some((i) => /het_han|mo_coi/.test(i.id)), 'GET /v1/audio khớp đĩa sau khi dọn', `count=${l.count}, đĩa ${files.length}`);
    if (process.platform !== 'win32') {
      fs.chmodSync(AUDIO_DIR, 0o755); // giả lập thư mục cũ/umask lạ để thấy engine có ép lại quyền khi ghi
      const again = await dictate({ text: `ghi lại ${MARK}`, pcm: tonePcm(1) });
      check(again.status === 200 && again.json?.audio_id && mode(AUDIO_DIR) === '700' && mode(path.join(AUDIO_DIR, `${again.json.audio_id}.wav`)) === '600',
        'Thư mục audio bị nới lỏng (0755) được ép lại 0700 ở lần ghi kế, tệp mới 0600', `thư mục=${mode(AUDIO_DIR)}`);
    }
    const dAll = await api({ method: 'DELETE', path: '/v1/audio' });
    check(dAll.status === 200 && diskWavs().length === 0, 'Dọn sạch sau thử nghiệm (DELETE /v1/audio)', `đĩa ${diskWavs().length} tệp`);
    // Mục lục audio/index.json HỎNG KHÔNG được làm mất tệp hợp lệ (P6): dựng lại từ đĩa; tệp rác ⇒ quarantine/
    await putSettings({ audio_history_days: 90 });
    await stopEngine();
    const wavA = wavBytes(tonePcm(1)); const wavB = wavBytes(tonePcm(2));
    const junk = Buffer.from('day-khong-phai-wav '.repeat(30));
    fs.writeFileSync(path.join(AUDIO_DIR, 'tr_mucluc_hong_1.wav'), wavA, { mode: 0o600 });
    fs.writeFileSync(path.join(AUDIO_DIR, 'tr_mucluc_hong_2.wav'), wavB, { mode: 0o600 });
    fs.writeFileSync(path.join(AUDIO_DIR, 'tr_rac.wav'), junk, { mode: 0o600 });
    fs.writeFileSync(path.join(AUDIO_DIR, 'index.json'), 'khong-phai-json{{{');
    await startEngine();
    const lb = await listAudio();
    const idsB = (lb.items ?? []).map((i) => i.id).sort();
    check(fileSha(path.join(AUDIO_DIR, 'tr_mucluc_hong_1.wav')) === sha(wavA) && fileSha(path.join(AUDIO_DIR, 'tr_mucluc_hong_2.wav')) === sha(wavB),
      'Mục lục hỏng ⇒ CẢ HAI tệp WAV hợp lệ còn nguyên trên đĩa (byte y hệt)', `đĩa: ${diskWavs().join(',')}`);
    check(idsB.join(',') === 'tr_mucluc_hong_1,tr_mucluc_hong_2' && lb.items.find((i) => i.id === 'tr_mucluc_hong_2')?.audio_ms === 2000,
      'GET /v1/audio liệt kê lại đủ hai tệp, audio_ms phân tích từ header (1000/2000)', JSON.stringify(lb.items?.map((i) => [i.id, i.audio_ms])));
    check(lb.index_rebuilt === true && lb.recovered === 2 && lb.quarantined === 1, 'GET /v1/audio báo index_rebuilt=true, recovered=2, quarantined=1', JSON.stringify({ ir: lb.index_rebuilt, rec: lb.recovered, q: lb.quarantined }));
    const qdir = path.join(AUDIO_DIR, 'quarantine');
    check(fileSha(path.join(qdir, 'tr_rac.wav')) === sha(junk) && !fs.existsSync(path.join(AUDIO_DIR, 'tr_rac.wav')), 'Tệp .wav rác được CHUYỂN vào quarantine/ (không xoá, nội dung nguyên vẹn)', `quarantine: ${fs.existsSync(qdir) ? fs.readdirSync(qdir).join(',') : 'không có'}`);
    if (process.platform !== 'win32') check(mode(qdir) === '700', 'quarantine/ quyền 0700', mode(qdir));
    const rebuiltIdx = JSON.parse(fs.readFileSync(path.join(AUDIO_DIR, 'index.json'), 'utf8'));
    check(Array.isArray(rebuiltIdx.items) && rebuiltIdx.items.length === 2, 'index.json được GHI LẠI hợp lệ (2 mục, không kể rác)', `${rebuiltIdx.items?.length} mục`);
    const dl = await api({ path: '/v1/audio/tr_mucluc_hong_1' });
    check(dl.status === 200 && sha(dl.body) === sha(wavA), 'Tải lại tệp đã dựng lại mục lục ⇒ 200, byte y hệt', `${dl.status}`);
    await stopEngine(); await startEngine();
    const lb2 = await listAudio();
    check(lb2.count === 2 && lb2.index_rebuilt === false && lb2.quarantined === 1, 'Khởi động lại lần nữa: mục lục đã lành (index_rebuilt=false), quarantine còn nguyên', JSON.stringify({ c: lb2.count, ir: lb2.index_rebuilt, q: lb2.quarantined }));
    // mục lục thiếu 1 mục cho tệp có thật + mục trỏ tệp đã mất
    await stopEngine();
    const idx2 = JSON.parse(fs.readFileSync(path.join(AUDIO_DIR, 'index.json'), 'utf8'));
    idx2.items = idx2.items.filter((e) => e.id !== 'tr_mucluc_hong_2');
    idx2.items.push({ id: 'tr_ma', at: new Date().toISOString(), audio_ms: 500, bytes: 100, app: null, mode: null });
    fs.writeFileSync(path.join(AUDIO_DIR, 'index.json'), JSON.stringify(idx2));
    await startEngine();
    const lb3 = await listAudio();
    check(fileSha(path.join(AUDIO_DIR, 'tr_mucluc_hong_2.wav')) === sha(wavB) && (lb3.items ?? []).map((i) => i.id).sort().join(',') === 'tr_mucluc_hong_1,tr_mucluc_hong_2',
      'Mục lục thiếu mục cho tệp có thật ⇒ tệp được nhận lại (không bị xoá); mục trỏ tệp đã mất bị bỏ', JSON.stringify(lb3.items?.map((i) => i.id)));
    const delAll = await api({ method: 'DELETE', path: '/v1/audio' });
    check(delAll.status === 200 && diskWavs().length === 0 && (!fs.existsSync(qdir) || fs.readdirSync(qdir).length === 0) && (await listAudio()).quarantined === 0,
      'DELETE /v1/audio (người dùng chủ động xoá hết) dọn cả WAV lẫn quarantine/', `đĩa ${diskWavs().length}, quarantine ${fs.existsSync(qdir) ? fs.readdirSync(qdir).length : 0}`);
  });

  // ---------------------------------------------------------------- ký hiệu theo ngữ cảnh
  await run('Ký hiệu theo ngữ cảnh (context_symbols)', async () => {
    await putSettings({ audio_history: false, audio_history_mb: 200, audio_history_days: 7, context_symbols: true });
    const sentence = `gửi file ${MARK} gạch chéo main cho an a còng example`;
    const symbolic = (t) => t.includes('/') && t.includes('@') && !/gạch chéo/i.test(t) && !/a còng/i.test(t);
    const literal = (t) => /gạch chéo/i.test(t) && /a còng/i.test(t) && !t.includes('/') && !t.includes('@');
    const apps = [['com.apple.Terminal', 'Terminal'], ['com.googlecode.iterm2', 'iTerm2'], ['com.microsoft.VSCode', 'VS Code'], ['com.todesktop.230313mzl4w4u92', 'Cursor'], ['com.apple.dt.Xcode', 'Xcode'], ['com.tinyspeck.slackmacgap', 'Slack']];
    for (const [id, name] of apps) {
      const r = await dictate({ text: sentence, app: id });
      check(r.status === 200 && symbolic(r.json.text), `${name} (${id}) ⇒ ra ký hiệu`, `"${r.json?.text}"`);
    }
    const plain = [['com.apple.Notes', 'Notes'], ['com.apple.mail', 'Mail'], ['com.apple.TextEdit', 'TextEdit'], ['com.google.Chrome', 'Chrome'], [undefined, '(không gửi app)'], ['', '(app rỗng)']];
    for (const [id, name] of plain) {
      const r = await dictate({ text: sentence, app: id });
      check(r.status === 200 && literal(r.json.text), `${name}${id ? ` (${id})` : ''} ⇒ giữ nguyên là chữ`, `"${r.json?.text}"`);
    }
    const auto1 = await dictate({ text: sentence, app: 'com.apple.Terminal', mode: 'auto' });
    const auto2 = await dictate({ text: sentence, app: 'com.apple.Notes', mode: 'auto' });
    check(auto1.status === 200 && symbolic(auto1.json.text) && auto2.status === 200 && literal(auto2.json.text), 'mode=auto: Terminal (tự chọn chế độ Lập trình) ra ĐỦ ký hiệu (/ và @), Notes giữ chữ', `Terminal="${auto1.json?.text}" (mode ${auto1.json?.mode}); Notes="${auto2.json?.text}" (mode ${auto2.json?.mode})`);
    const devMode = await dictate({ text: sentence, app: 'com.apple.Terminal', mode: 'dev' });
    check(devMode.status === 200 && symbolic(devMode.json.text), 'mode=dev chọn thẳng, app=Terminal ⇒ ra ký hiệu (/ và @)', `"${devMode.json?.text}"`);
    const urlT = await dictate({ text: 'mở trang https hai chấm hai gạch chéo example', app: 'com.apple.Terminal', mode: 'auto' });
    const urlN = await dictate({ text: 'mở trang https hai chấm hai gạch chéo example', app: 'com.apple.Notes', mode: 'auto' });
    check(urlT.json?.text?.includes('https://example') && !urlN.json?.text?.includes('://'), 'URL đọc "hai chấm hai gạch chéo" ⇒ "://" trong Terminal, giữ chữ trong Notes', `Terminal="${urlT.json?.text}"; Notes="${urlN.json?.text}"`);
    const upper = await dictate({ text: sentence, app: 'com.apple.terminal' });
    check(upper.status === 200 && literal(upper.json.text), 'Bundle id sai hoa/thường (com.apple.terminal) KHÔNG khớp ⇒ giữ chữ (so khớp chính xác)', `"${upper.json?.text}"`);
    const slackCmd = await dictate({ text: 'gạch chéo giúp đỡ', app: 'com.tinyspeck.slackmacgap' });
    const termCmd = await dictate({ text: 'gạch chéo giúp đỡ', app: 'com.apple.Terminal' });
    process.stdout.write(`      (thông tin) "gạch chéo giúp đỡ" ở Slack → "${slackCmd.json?.text}"; ở Terminal → "${termCmd.json?.text}"\n`);
    const mention = await dictate({ text: 'nhắn a còng nam xong', app: 'com.tinyspeck.slackmacgap' });
    process.stdout.write(`      (thông tin) Slack "nhắn a còng nam xong" → "${mention.json?.text}"\n`);
    // Không dư dấu cách ở MỌI vị trí: đầu/giữa/cuối câu, trước dấu câu (P6)
    const T = 'com.apple.Terminal'; const S = 'com.tinyspeck.slackmacgap';
    const posCases = [
      [T, 'gửi cho an a còng example', 'gửi cho an@example', 'cuối câu'],
      [T, 'a còng example rồi chạy', '@example rồi chạy', 'đầu câu'],
      [T, 'gửi an a còng example rồi chạy', 'gửi an@example rồi chạy', 'giữa câu'],
      [T, 'gửi an a còng example dấu phẩy rồi chạy', 'gửi an@example, rồi chạy', 'trước dấu câu (dấu phẩy bằng giọng)'],
      [S, 'chào a còng nam', 'chào @nam', 'cuối câu (Slack)'],
      [S, 'chào a còng nam dấu chấm', 'chào @nam.', 'trước dấu chấm (Slack)'],
      [S, 'gạch chéo deploy', '/deploy', 'lệnh slash cuối câu (Slack)'],
      [S, 'gạch chéo deploy staging', '/deploy staging', 'lệnh slash còn chữ phía sau (Slack)'],
      [T, 'git gạch nối gạch nối', 'git --', 'cờ -- cuối câu'],
      [T, 'git gạch nối gạch nối help', 'git --help', 'cờ -- giữa câu'],
      [T, 'mở file a gạch dưới', 'mở file a_', 'ký hiệu dính cuối câu'],
    ];
    for (const [app, text, want, where] of posCases) {
      const r = await dictate({ text, app });
      check(r.status === 200 && r.json?.text === want && !/\s$/.test(r.json?.text ?? ''), `Không dư dấu cách — ${where}`, `"${text}" ⇒ ${JSON.stringify(r.json?.text)} (mong ${JSON.stringify(want)})`);
    }
    const normalWords = await dictate({ text: 'chúng ta nói chuyện về gạch chéo trong toán học', app: 'com.apple.Notes' });
    check(normalWords.json?.text?.includes('gạch chéo'), 'Notes: câu nói thường có "gạch chéo" giữ nguyên', `"${normalWords.json?.text}"`);
    // tắt
    const off = await putSettings({ context_symbols: false });
    const offResults = [];
    for (const [id] of apps) offResults.push((await dictate({ text: sentence, app: id })).json?.text ?? '');
    check(off.status === 200 && offResults.every(literal), 'context_symbols=false ⇒ MỌI app (kể cả Terminal/IDE/Slack) giữ chữ', offResults.map((t) => `"${t}"`).join(' | '));
    const applied = (await dictate({ text: sentence, app: 'com.apple.Terminal' })).json?.post?.applied ?? [];
    check(!applied.some((a) => a.type === 'context_symbol'), 'context_symbols=false ⇒ post.applied không có context_symbol', JSON.stringify(applied.map((a) => a.type)));
    await putSettings({ context_symbols: true });
    const back = await dictate({ text: sentence, app: 'com.apple.Terminal' });
    const ap2 = back.json?.post?.applied ?? [];
    check(symbolic(back.json?.text ?? '') && ap2.some((a) => a.type === 'context_symbol'), 'Bật lại ⇒ có hiệu lực ngay, post.applied ghi context_symbol', `"${back.json?.text}" ${JSON.stringify(ap2.map((a) => a.type))}`);
  });

  // ---------------------------------------------------------------- nhật ký engine
  await run('Nhật ký của engine (stderr)', async () => {
    const hits = Object.entries({ 'token': TOKEN, 'khoá': KEY_BAIT, 'token STT giả': FAKE_REMOTE_TOKEN, 'từ mồi trong lời nói': MARK, 'chuỗi history': HIST_BAIT, 'Bearer': 'Bearer ' }).filter(([, v]) => engineLog.includes(v)).map(([k]) => k);
    check(hits.length === 0 && engineLog.length > 0, 'Log engine không chứa token/khoá/lời đã nói/văn bản history', hits.length ? `RÒ RỈ: ${hits.join(', ')}` : `${engineLog.split('\n').filter(Boolean).length} dòng log sạch`);
    const unparsable = engineLog.split('\n').filter((l) => l.startsWith('{')).filter((l) => { try { JSON.parse(l); return false; } catch { return true; } });
    check(unparsable.length === 0, 'Mọi dòng log JSON đều parse được', `${unparsable.length} dòng hỏng`);
  });
}

// =====================================================================================
let exitCode = 0;
let aborted = false;
async function cleanup() {
  try { await stopEngine(); } catch { /* đã tắt */ }
  try { await new Promise((r) => (fakeServer ? fakeServer.close(() => r(undefined)) : r(undefined))); } catch { /* đã đóng */ }
  if (ROOT) fs.rmSync(ROOT, { recursive: true, force: true });
}
for (const sig of ['SIGINT', 'SIGTERM']) process.on(sig, () => { aborted = true; cleanup().finally(() => process.exit(130)); });
try {
  await main();
} catch (e) {
  process.stdout.write(`\nLỖI MÔI TRƯỜNG: ${e?.stack ?? e}\n`);
  exitCode = 2;
} finally {
  const pid = engine?.pid;
  await cleanup();
  let alive = false;
  if (pid) { try { process.kill(pid, 0); alive = true; } catch { alive = false; } }
  const gone = !ROOT || !fs.existsSync(ROOT);
  process.stdout.write(`\nDọn dẹp: engine ${pid ? `pid ${pid} ${alive ? 'VẪN CÒN SỐNG' : 'đã tắt'}` : 'đã tắt'}; thư mục tạm ${gone ? 'đã xoá' : 'CHƯA XOÁ'}.\n`);
  if (alive || !gone) exitCode = exitCode || 2;
}
const fails = results.filter((r) => !r.ok);
process.stdout.write(`\n==== TỔNG KẾT ====\n${results.length - fails.length} PASS, ${fails.length} FAIL / ${results.length} khẳng định\n`);
if (fails.length) {
  process.stdout.write('\nCác khẳng định FAIL:\n');
  for (const f of fails) process.stdout.write(` - [${f.group}] ${f.claim}${f.obs ? `\n     quan sát: ${f.obs}` : ''}\n`);
}
if (aborted) exitCode = 130;
process.exit(exitCode || (fails.length ? 1 : 0));
