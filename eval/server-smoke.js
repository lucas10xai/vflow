#!/usr/bin/env node
/**
 * Kiểm thử khói server thật bằng curl (chạy trên chính máy chạy engine, ví dụ HP):
 *   node eval/server-smoke.js [--port 7699] [--wav <tệp wav mẫu>]
 * Khởi động `vflow serve`, gọi curl cho các bất biến 1/3/4 của contract, audio/wav + audio/L16,
 * im lặng, rồi dừng server. So danh sách tệp trong thư mục tạm và VFLOW_HOME trước/sau.
 * Thân âm thanh đưa vào curl qua stdin (--data-binary @-), không ghi tệp âm thanh tạm.
 * Không in token (chỉ in ***).
 */
import { spawn, spawnSync } from 'node:child_process';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { parseArgs } from 'node:util';
import { fileURLToPath } from 'node:url';
import { encodeWav, parseWav, resample, toInt16 } from '../engine/stt/audio.js';
import { vflowHome } from '../engine/stt/registry.js';

const { values } = parseArgs({ options: { port: { type: 'string', default: '7699' }, wav: { type: 'string' } } });
const port = Number(values.port);
const home = vflowHome();
const CLI = fileURLToPath(new URL('../bin/vflow.js', import.meta.url));
const wavPath = values.wav ?? path.join(home, 'models', 'zipformer-vi-30m', 'test_wavs', '0.wav');
const curlBin = process.platform === 'win32' ? path.join(process.env.SystemRoot ?? 'C:\\Windows', 'System32', 'curl.exe') : 'curl';

/** Liệt kê tệp (đệ quy cho VFLOW_HOME, cấp 1 cho thư mục tạm dùng chung). */
function snapshot() {
  const out = new Map();
  for (const n of fs.readdirSync(os.tmpdir())) out.set(path.join(os.tmpdir(), n), 'tmp');
  for (const d of fs.readdirSync(home, { recursive: true, withFileTypes: true })) {
    const p = path.join(d.parentPath ?? d.path, d.name);
    if (d.isFile()) out.set(p, String(fs.statSync(p).mtimeMs));
  }
  return out;
}

let failed = 0;
const check = (ok, label, detail = '') => {
  if (!ok) failed++;
  console.log(`${ok ? 'ĐẠT ' : 'TRƯỢT'} ${label}${detail ? ` — ${detail}` : ''}`);
};

/**
 * @param {string[]} args @param {Uint8Array} [stdin]
 * @returns {{ status: number, body: any, raw: string }}
 */
function curl(args, stdin) {
  const r = spawnSync(curlBin, ['-s', '-o', '-', '-w', '\n%{http_code}', ...args], { input: stdin, maxBuffer: 16 * 1024 * 1024 });
  const text = r.stdout.toString('utf8');
  const i = text.lastIndexOf('\n');
  const raw = text.slice(0, i);
  let body = null;
  try { body = JSON.parse(raw); } catch { /* không phải JSON */ }
  return { status: Number(text.slice(i + 1)), body, raw };
}

const base = `http://127.0.0.1:${port}`;

async function waitHealthy(child) {
  for (let i = 0; i < 100; i++) {
    if (child.exitCode !== null) throw new Error(`serve thoát sớm (mã ${child.exitCode})`);
    const r = curl([`${base}/healthz`]);
    if (r.status === 200) return r;
    await new Promise((res) => setTimeout(res, 200));
  }
  throw new Error('serve không lên sau 20 s');
}

const before = snapshot();
const serverLog = [];
const child = spawn(process.execPath, [CLI, 'serve', '--port', String(port)], { stdio: ['ignore', 'ignore', 'pipe'] });
child.stderr.on('data', (d) => serverLog.push(String(d)));
try {
  const h = await waitHealthy(child);
  // Đợi model mặc định nạp xong (serve nạp sau khi đã nghe cổng).
  let health = h.body;
  for (let i = 0; i < 50 && !health.models.find((m) => m.id === 'zipformer-vi-30m')?.loaded; i++) {
    await new Promise((res) => setTimeout(res, 200));
    health = curl([`${base}/healthz`]).body;
  }
  console.log(`healthz: ${JSON.stringify(health)}`);
  check(health.models.every((m) => m.loaded || m.reason), 'healthz: model chưa dùng được đều có reason');

  const token = fs.readFileSync(path.join(home, 'token'), 'utf8').trim();
  console.log('token: *** (đọc từ VFLOW_HOME/token)');
  if (process.platform !== 'win32') check((fs.statSync(path.join(home, 'token')).mode & 0o777) === 0o600, 'token quyền 0600');
  const H = ['-H', `Authorization: Bearer ${token}`];
  const wavBytes = new Uint8Array(fs.readFileSync(wavPath));

  // Bất biến 3: token
  const noTok = curl(['-X', 'POST', '-H', 'Content-Type: audio/wav', '--data-binary', '@-', `${base}/v1/transcribe`], wavBytes);
  check(noTok.status === 401 && noTok.body?.error?.code === 'unauthorized', 'thiếu token ⇒ 401 unauthorized', `${noTok.status}`);
  const badTok = curl(['-X', 'POST', '-H', `Authorization: Bearer ${'0'.repeat(64)}`, '-H', 'Content-Type: audio/wav', '--data-binary', '@-', `${base}/v1/transcribe`], wavBytes);
  check(badTok.status === 401 && badTok.body?.error?.code === 'unauthorized', 'sai token ⇒ 401 unauthorized', `${badTok.status}`);
  // Bất biến 3: Host
  const badHost = curl([...H, '-H', 'Host: evil.example', '-X', 'POST', '-H', 'Content-Type: audio/wav', '--data-binary', '@-', `${base}/v1/transcribe`], wavBytes);
  check(badHost.status === 403, 'Host lạ (có token đúng) ⇒ bị từ chối', `${badHost.status} ${badHost.raw}`);
  const badHost2 = curl(['-H', `Host: attacker.test:${port}`, `${base}/healthz`]);
  check(badHost2.status === 403, 'Host lạ ở /healthz ⇒ bị từ chối', `${badHost2.status}`);
  const cors = spawnSync(curlBin, ['-s', '-D', '-', '-o', process.platform === 'win32' ? 'NUL' : '/dev/null', `${base}/healthz`]).stdout.toString();
  check(!/access-control-/i.test(cors), 'không có header CORS');

  // audio/wav
  const w = curl([...H, '-X', 'POST', '-H', 'Content-Type: audio/wav', '--data-binary', '@-', `${base}/v1/transcribe?mode=clean`], wavBytes);
  check(w.status === 200 && typeof w.body?.text === 'string' && w.body.text_raw.length > 0, 'audio/wav ⇒ 200, có chữ', `${w.status} audio_ms=${w.body?.audio_ms} stt=${w.body?.timings_ms?.stt}ms rtf=${w.body?.rtf}`);
  console.log(`  text_raw: ${w.body?.text_raw}`);
  console.log(`  text:     ${w.body?.text}`);
  // audio/L16 (đổi wav mẫu sang 16 kHz mono int16 trong RAM)
  const pw = parseWav(wavBytes);
  const pcm = toInt16(pw.sampleRate === 16000 ? pw.samples : resample(pw.samples, pw.sampleRate, 16000));
  const l16 = curl([...H, '-X', 'POST', '-H', 'Content-Type: audio/L16; rate=16000; channels=1', '--data-binary', '@-', `${base}/v1/transcribe`], new Uint8Array(pcm.buffer));
  check(l16.status === 200 && l16.body?.text_raw === w.body?.text_raw, 'audio/L16 ⇒ 200, cùng chữ với bản wav', `${l16.status}`);
  // wav 44,1 kHz stereo (cùng câu)
  const up = resample(pw.samples, pw.sampleRate, 44100);
  const st = new Float32Array(up.length * 2);
  for (let i = 0; i < up.length; i++) { st[2 * i] = up[i]; st[2 * i + 1] = up[i]; }
  const w44 = curl([...H, '-X', 'POST', '-H', 'Content-Type: audio/wav', '--data-binary', '@-', `${base}/v1/transcribe`], encodeWav(st, 44100, 2));
  check(w44.status === 200 && w44.body?.text_raw.length > 0, 'wav 44,1 kHz stereo ⇒ 200', `"${w44.body?.text_raw}"`);
  // Im lặng
  const sil = curl([...H, '-X', 'POST', '-H', 'Content-Type: audio/wav', '--data-binary', '@-', `${base}/v1/transcribe`], encodeWav(new Float32Array(32000), 16000));
  check(sil.status === 200 && sil.body?.silence === true && sil.body?.text === '', 'im lặng ⇒ silence:true, text ""', sil.raw);
  // Bất biến 4: model thiếu
  const miss = curl([...H, '-X', 'POST', '-H', 'Content-Type: audio/wav', '--data-binary', '@-', `${base}/v1/transcribe?model=phowhisper-large`], wavBytes);
  check(miss.status === 503 && miss.body?.error?.code === 'model_unavailable', 'model từ xa không có token/tunnel ⇒ 503 model_unavailable có lý do', miss.raw);
  const streamingMissing = !health.models.find((m) => m.id === 'zipformer-vi-30m-streaming')?.loaded;
  if (streamingMissing) {
    const s2 = curl([...H, '-X', 'POST', '-H', 'Content-Type: audio/wav', '--data-binary', '@-', `${base}/v1/transcribe?model=zipformer-vi-30m-streaming`], wavBytes);
    console.log(`  model streaming: ${s2.status} ${s2.raw}`);
  }
  // Lỗi khác
  const bad = curl([...H, '-X', 'POST', '-H', 'Content-Type: audio/mpeg', '--data-binary', '@-', `${base}/v1/transcribe`], new Uint8Array([1, 2, 3]));
  check(bad.status === 400 && bad.body?.error?.code === 'bad_audio', 'audio/mpeg ⇒ 400 bad_audio');
  const long = curl([...H, '-X', 'POST', '-H', 'Content-Type: audio/L16; rate=8000; channels=1', '--data-binary', '@-', `${base}/v1/transcribe`], new Uint8Array(8000 * 2 * 121));
  check(long.status === 413 && long.body?.error?.code === 'payload_too_large', '121 s âm thanh ⇒ 413 payload_too_large');
  const dict = curl([...H, `${base}/v1/dictionary`]);
  check(dict.status === 200 && Array.isArray(dict.body?.entries), 'GET /v1/dictionary ⇒ 200 (chuyển sang engine/post)', `${dict.body?.entries?.length} mục`);
} catch (e) {
  check(false, 'chạy kiểm thử', String(e?.message ?? e));
} finally {
  child.kill();
  await new Promise((res) => (child.exitCode !== null ? res(undefined) : child.once('exit', res)));
}

// Bất biến 1: không có tệp mới nào (trừ token/dictionary do serve tạo lần đầu, liệt kê rõ).
const after = snapshot();
const added = [...after.keys()].filter((p) => !before.has(p));
const changed = [...after.keys()].filter((p) => before.has(p) && before.get(p) !== after.get(p) && after.get(p) !== 'tmp');
const allowed = new Set([path.join(home, 'token'), path.join(home, 'dictionary.json')]);
console.log(`tệp mới: ${JSON.stringify(added)} · tệp đổi: ${JSON.stringify(changed)}`);
check(added.filter((p) => !allowed.has(p)).length === 0 && changed.filter((p) => !allowed.has(p)).length === 0,
  'bất biến 1: không có tệp mới/đổi trong thư mục tạm và VFLOW_HOME (ngoài token/dictionary)');
const logText = serverLog.join('');
check(!logText.includes('"text') && !(/[ạảãàáâầấậẩẫăằắặẳẵ]/u.test(logText.replace(/vflow engine.*\n|CẢNH BÁO.*\n|Đã tải model.*\n/g, ''))),
  'log server không chứa văn bản nhận dạng');
console.log(`log server (${logText.split('\n').filter(Boolean).length} dòng), 3 dòng cuối:\n${logText.trim().split('\n').slice(-3).join('\n')}`);
console.log(failed ? `KẾT QUẢ: ${failed} mục TRƯỢT` : 'KẾT QUẢ: tất cả ĐẠT');
process.exitCode = failed ? 1 : 0;
