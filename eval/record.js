/**
 * Thu âm bộ câu đo (M2): mỗi câu một cặp `NN.wav` (PCM16 16 kHz mono) + `NN.txt` (đúng nội dung câu).
 * Thu bằng ffmpeg (macOS avfoundation) CHỈ khi người dùng bấm Enter; không bao giờ thu nền.
 * Âm thanh là dữ liệu cá nhân: chỉ ghi vào thư mục `--out` (mặc định nên ở ~/.vflow/eval/<tên-bộ>/),
 * không gửi đi đâu. Phần thuần (phân tích, đánh giá mức âm, tiếp tục thu) tách riêng để test.
 */
import fs from 'node:fs';
import fsp from 'node:fs/promises';
import path from 'node:path';
import readline from 'node:readline';
import { spawn, spawnSync } from 'node:child_process';

export const FFMPEG = process.env.VFLOW_FFMPEG || 'ffmpeg';
export const SAMPLE_RATE = 16000;

/** Ngưỡng cảnh báo sau mỗi lần thu. */
export const LEVELS = Object.freeze({ quietMeanDb: -45, quietMaxDb: -20, clipMaxDb: -0.5, minSeconds: 1 });

export const MIC_PERMISSION_HELP = `Cấp quyền micro trên macOS:
  1. Lần đầu thu, macOS hỏi "Terminal (hoặc iTerm/Ghostty…) muốn truy cập micrô" → bấm Cho phép.
  2. Nếu đã lỡ từ chối: Cài đặt hệ thống → Quyền riêng tư & Bảo mật → Micrô → bật cho ứng dụng terminal đang dùng,
     rồi THOÁT HẲN và mở lại terminal đó (quyền chỉ áp dụng cho tiến trình mới).
  3. Kiểm tra: vflow record-set --list-devices phải thấy "[0] Micrô MacBook Pro" (hoặc mic đang dùng).
  ffmpeg chạy dưới quyền của terminal nên không cần cấp riêng cho ffmpeg.`;

/**
 * Đọc tệp câu dạng `NN. <câu>` (bỏ dòng trống). Sai định dạng/trùng số ⇒ ném lỗi (không đoán).
 * @param {string} text
 * @returns {{ id: string, text: string }[]}
 */
export function parsePrompts(text) {
  const out = [];
  const seen = new Set();
  String(text).split(/\r?\n/).forEach((line, i) => {
    if (line.trim() === '') return;
    const m = /^\s*(\d{1,3})\.\s+(.+?)\s*$/.exec(line);
    if (!m) throw new Error(`Dòng ${i + 1} không đúng dạng "NN. <câu>"`);
    const id = m[1].padStart(2, '0');
    if (seen.has(id)) throw new Error(`Số câu ${id} bị trùng (dòng ${i + 1})`);
    seen.add(id);
    out.push({ id, text: m[2].normalize('NFC') });
  });
  if (out.length === 0) throw new Error('Tệp câu không có câu nào');
  return out;
}

/**
 * Phân tích đầu ra `ffmpeg -f avfoundation -list_devices true -i ""` (stderr).
 * @param {string} stderr
 * @returns {{ video: {index:number,name:string}[], audio: {index:number,name:string}[] }}
 */
export function parseAvfoundationDevices(stderr) {
  /** @type {{ video: {index:number,name:string}[], audio: {index:number,name:string}[] }} */
  const out = { video: [], audio: [] };
  /** @type {'video'|'audio'|null} */
  let section = null;
  for (const line of String(stderr).split(/\r?\n/)) {
    if (/AVFoundation video devices:/.test(line)) { section = 'video'; continue; }
    if (/AVFoundation audio devices:/.test(line)) { section = 'audio'; continue; }
    const m = /^\[[^\]]*AVFoundation[^\]]*\]\s+\[(\d+)\]\s+(.+?)\s*$/.exec(line);
    if (m && section) out[section].push({ index: Number(m[1]), name: m[2] });
    else if (!/^\[[^\]]*AVFoundation/.test(line)) section = null;
  }
  return out;
}

/**
 * Lấy mean/max dB từ stderr của bộ lọc `volumedetect`. Thiếu ⇒ null (không xác định, không phải 0).
 * @param {string} stderr
 * @returns {{ mean_db: number|null, max_db: number|null }}
 */
export function parseVolumedetect(stderr) {
  const num = (/** @type {string} */ key) => {
    const m = new RegExp(`${key}:\\s*(-?(?:\\d+(?:\\.\\d+)?|inf))\\s*dB`).exec(String(stderr));
    if (!m) return null;
    return m[1] === '-inf' ? -Infinity : Number(m[1]);
  };
  return { mean_db: num('mean_volume'), max_db: num('max_volume') };
}

/**
 * Cờ cảnh báo cho một bản thu. Giá trị thiếu ⇒ cờ `unknown_level`/`unknown_duration`.
 * @param {{ mean_db: number|null, max_db: number|null, duration_s: number|null }} m
 * @returns {{ code: string, message: string }[]}
 */
export function assessRecording({ mean_db, max_db, duration_s }) {
  const w = [];
  const fmt = (/** @type {number} */ v) => (v === -Infinity ? '-inf' : v.toFixed(1));
  if (mean_db === null || max_db === null) {
    w.push({ code: 'unknown_level', message: 'Không đo được mức âm lượng (ffmpeg volumedetect không trả số).' });
  } else {
    if (mean_db < LEVELS.quietMeanDb || max_db < LEVELS.quietMaxDb) {
      w.push({ code: 'too_quiet', message: `Âm lượng quá nhỏ (mean ${fmt(mean_db)} dB, max ${fmt(max_db)} dB; cần mean ≥ ${LEVELS.quietMeanDb} dB và max ≥ ${LEVELS.quietMaxDb} dB). Lại gần mic hoặc kiểm mic đang chọn.` });
    }
    if (max_db >= LEVELS.clipMaxDb) {
      w.push({ code: 'clipped', message: `Có thể bị vỡ tiếng (max ${fmt(max_db)} dB ≥ ${LEVELS.clipMaxDb} dB). Lùi xa mic hoặc nói nhỏ hơn.` });
    }
  }
  if (duration_s === null || !Number.isFinite(duration_s)) {
    w.push({ code: 'unknown_duration', message: 'Không xác định được thời lượng bản thu.' });
  } else if (duration_s < LEVELS.minSeconds) {
    w.push({ code: 'too_short', message: `Bản thu quá ngắn (${duration_s.toFixed(2)} s < ${LEVELS.minSeconds} s).` });
  }
  return w;
}

/** @param {string} id */
export const clipFiles = (id) => ({ wav: `${id}.wav`, txt: `${id}.txt` });

/**
 * Câu nào đã xong (có cả NN.wav và NN.txt) và hàng đợi còn lại theo thứ tự.
 * @param {{ id: string }[]} prompts
 * @param {Iterable<string>} existing tên tệp trong thư mục
 */
export function planSession(prompts, existing) {
  const names = new Set(existing);
  const done = [];
  const pending = [];
  for (const p of prompts) {
    const f = clipFiles(p.id);
    (names.has(f.wav) && names.has(f.txt) ? done : pending).push(p);
  }
  return { done, pending };
}

/**
 * Tham số ffmpeg để thu vào `out` (WAV PCM16 16 kHz mono). Dừng bằng cách gửi "q" vào stdin của ffmpeg.
 * @param {{ out: string, device?: number, fake?: boolean, fakeGainDb?: number }} o
 */
export function recordArgs({ out, device = 0, fake = false, fakeGainDb = 0 }) {
  const input = fake
    // arealtime (thay -re, vốn đẩy trước ~0,5 s) để thời lượng bản thu giả bám đúng lúc bấm Enter.
    ? ['-f', 'lavfi', '-i', `sine=frequency=440:sample_rate=${SAMPLE_RATE}:samples_per_frame=320,arealtime${fakeGainDb ? `,volume=${fakeGainDb}dB` : ''}`]
    : ['-f', 'avfoundation', '-i', `:${device}`];
  return ['-hide_banner', '-nostats', '-loglevel', 'error', ...input,
    '-ac', '1', '-ar', String(SAMPLE_RATE), '-c:a', 'pcm_s16le', '-f', 'wav', '-y', out];
}

/** Thời lượng (giây) từ header WAV PCM; không đọc được ⇒ null. @param {Uint8Array} bytes */
export function wavDurationSeconds(bytes) {
  if (bytes.length < 12 || String.fromCharCode(...bytes.subarray(0, 4)) !== 'RIFF') return null;
  const view = new DataView(bytes.buffer, bytes.byteOffset, bytes.byteLength);
  let off = 12;
  let byteRate = null;
  while (off + 8 <= bytes.length) {
    const id = String.fromCharCode(...bytes.subarray(off, off + 4));
    let size = view.getUint32(off + 4, true);
    if (id === 'fmt ' && off + 20 <= bytes.length) byteRate = view.getUint32(off + 16, true);
    if (id === 'data') {
      if (!byteRate) return null;
      // ffmpeg đọc từ pipe/dừng sớm có thể để size = 0xFFFFFFFF: lấy phần còn lại của tệp.
      if (size === 0xffffffff || off + 8 + size > bytes.length) size = bytes.length - off - 8;
      return size / byteRate;
    }
    off += 8 + size + (size % 2);
  }
  return null;
}

/**
 * Gộp siêu dữ liệu bộ (`set.json`). `synthetic` dính: đã có một lần thu giả thì cả bộ là giả.
 * @param {any} prev nội dung cũ (hoặc null)
 * @param {{ fake: boolean, device: number, promptsFile?: string, now?: string }} cur
 */
export function mergeSetMeta(prev, { fake, device, promptsFile, now = new Date().toISOString() }) {
  const sources = new Set(Array.isArray(prev?.sources) ? prev.sources : []);
  sources.add(fake ? 'ffmpeg-lavfi-sine' : `avfoundation:${device}`);
  return {
    synthetic: Boolean(prev?.synthetic) || fake,
    ...(prev?.voice ? { voice: prev.voice } : {}),
    sources: [...sources].sort(),
    prompts: promptsFile ? path.basename(promptsFile) : prev?.prompts ?? null,
    created: prev?.created ?? now,
    updated: now,
  };
}

/** @param {string} dir @param {{ fake: boolean, device: number, promptsFile?: string }} cur */
async function writeSetMeta(dir, cur) {
  const file = path.join(dir, 'set.json');
  let prev = null;
  try { prev = JSON.parse(await fsp.readFile(file, 'utf8')); } catch (e) {
    if (/** @type {any} */ (e).code !== 'ENOENT') throw new Error(`${file} hỏng: ${/** @type {Error} */ (e).message}`);
  }
  await fsp.writeFile(file, JSON.stringify(mergeSetMeta(prev, cur), null, 2) + '\n');
}

/** Câu dễ đọc: chữ in đậm, nếu là TTY thì dùng dòng cao gấp đôi (DEC double-height). */
export function bigText(text, { tty = false, columns = 80 } = {}) {
  const width = Math.max(20, Math.floor((tty ? columns / 2 : columns) - 4));
  const lines = [];
  let cur = '';
  for (const word of text.split(/\s+/)) {
    if (cur && (cur + ' ' + word).length > width) { lines.push(cur); cur = word; } else cur = cur ? `${cur} ${word}` : word;
  }
  if (cur) lines.push(cur);
  if (!tty) return lines.map((l) => `  ${l}`).join('\n');
  return lines.map((l) => `\x1b#3\x1b[1m  ${l}\x1b[0m\n\x1b#4\x1b[1m  ${l}\x1b[0m`).join('\n');
}

/** Đọc từng dòng stdin như hàng đợi; hết stdin ⇒ trả null (coi như thoát). */
export function lineReader(input = process.stdin) {
  const rl = readline.createInterface({ input, terminal: false });
  /** @type {string[]} */ const queue = [];
  /** @type {((v: string|null) => void)[]} */ const waiters = [];
  let closed = false;
  rl.on('line', (l) => { const w = waiters.shift(); if (w) w(l); else queue.push(l); });
  rl.on('close', () => { closed = true; while (waiters.length) waiters.shift()?.(null); });
  return {
    /** @returns {Promise<string|null>} */
    next() {
      if (queue.length) return Promise.resolve(/** @type {string} */ (queue.shift()));
      if (closed) return Promise.resolve(null);
      return new Promise((resolve) => waiters.push(resolve));
    },
    close: () => rl.close(),
  };
}

/** @param {string[]} args */
function runFfmpeg(args) {
  return spawnSync(FFMPEG, args, { encoding: 'utf8', maxBuffer: 16 * 1024 * 1024 });
}

export function listAudioDevices() {
  const r = runFfmpeg(['-hide_banner', '-f', 'avfoundation', '-list_devices', 'true', '-i', '']);
  if (r.error) throw new Error(`Không chạy được ffmpeg (${FFMPEG}): ${r.error.message}`);
  return parseAvfoundationDevices(r.stderr).audio;
}

/** @param {string} file */
export function measureVolume(file) {
  const r = runFfmpeg(['-hide_banner', '-nostats', '-i', file, '-af', 'volumedetect', '-f', 'null', '-']);
  if (r.error) return { mean_db: null, max_db: null };
  return parseVolumedetect(r.stderr);
}

/**
 * Thu một bản: ffmpeg chạy tới khi `stop()` được gọi (gửi "q" để ffmpeg đóng header WAV đúng).
 * @param {string[]} args
 */
function startRecording(args) {
  const child = spawn(FFMPEG, args, { stdio: ['pipe', 'ignore', 'pipe'] });
  let stderr = '';
  child.stderr.on('data', (d) => { stderr += d; });
  const exited = new Promise((resolve) => {
    child.on('error', (e) => resolve({ code: -1, stderr: String(e.message) }));
    child.on('close', (code) => resolve({ code, stderr }));
  });
  return {
    exited: /** @type {Promise<{code:number|null, stderr:string}>} */ (exited),
    async stop() {
      if (child.exitCode === null) {
        child.stdin.write('q');
        child.stdin.end();
        const t = setTimeout(() => child.kill('SIGINT'), 3000);
        const r = await exited;
        clearTimeout(t);
        return r;
      }
      return exited;
    },
  };
}

/**
 * Phiên thu tương tác.
 * @param {{ prompts: {id:string,text:string}[], out: string, device?: number, fake?: boolean,
 *           fakeGainDb?: number, redo?: string[], promptsFile?: string,
 *           input?: NodeJS.ReadableStream, write?: (s: string) => void, tty?: boolean, columns?: number }} o
 * @returns {Promise<{ saved: string[], skipped: string[], quit: boolean, remaining: number }>}
 */
export async function recordSession(o) {
  const write = o.write ?? ((s) => process.stdout.write(s));
  const tty = o.tty ?? Boolean(process.stdout.isTTY);
  await fsp.mkdir(o.out, { recursive: true, mode: 0o700 });
  await writeSetMeta(o.out, { fake: Boolean(o.fake), device: o.device ?? 0, promptsFile: o.promptsFile });
  // Bản thu dở của lần trước (bị Ctrl-C) không bao giờ được tính là đã xong.
  for (const n of await fsp.readdir(o.out)) if (/^\.\d+\.part\.wav$/.test(n)) await fsp.rm(path.join(o.out, n), { force: true });
  const reader = lineReader(o.input ?? process.stdin);
  const saved = [];
  const skipped = [];
  let quit = false;
  try {
    const { done, pending } = planSession(o.prompts, await fsp.readdir(o.out));
    const queue = [...pending];
    for (const id of o.redo ?? []) {
      const p = o.prompts.find((x) => x.id === id);
      if (!p) throw new Error(`--redo: không có câu ${id}`);
      if (queue.includes(p)) continue;
      write(`Câu ${id} đã có bản thu. Ghi đè? (y/N) `);
      const a = await reader.next();
      if (a !== null && a.trim().toLowerCase() === 'y') queue.unshift(p);
    }
    queue.sort((a, b) => o.prompts.indexOf(a) - o.prompts.indexOf(b));
    write(`Bộ: ${o.out}\nĐã có ${done.length}/${o.prompts.length} câu; còn ${queue.length} câu cần thu.\n`);
    if (queue.length === 0) write('Không còn câu nào cần thu. Dùng --redo NN để thu lại một câu.\n');
    const total = String(o.prompts.length).padStart(2, '0');

    outer: for (const p of queue) {
      const files = clipFiles(p.id);
      const tmp = path.join(o.out, `.${p.id}.part.wav`);
      take: for (;;) {
        write(`\n──────── ${p.id}/${total} ────────\n${bigText(p.text, { tty, columns: o.columns ?? process.stdout.columns ?? 80 })}\n\n`);
        write('[Enter] bắt đầu thu · s bỏ qua · q thoát > ');
        const a = (await reader.next());
        if (a === null || a.trim() === 'q') { quit = true; break outer; }
        if (a.trim() === 's') { skipped.push(p.id); continue outer; }
        const rec = startRecording(recordArgs({ out: tmp, device: o.device ?? 0, fake: o.fake, fakeGainDb: o.fakeGainDb }));
        write('● ĐANG THU… [Enter] để dừng ');
        const raced = await Promise.race([reader.next().then((l) => ({ line: l })), rec.exited.then((r) => ({ early: r }))]);
        const r = await rec.stop();
        if ('early' in raced || r.code !== 0 || !fs.existsSync(tmp)) {
          write(`\nffmpeg dừng bất thường (mã ${r.code}): ${r.stderr.trim().split('\n').slice(-3).join(' | ') || 'không có thông báo'}\n`);
          if (!o.fake) write(`${MIC_PERMISSION_HELP}\n`);
          await fsp.rm(tmp, { force: true });
          throw new Error('Thu âm thất bại');
        }
        if (raced.line === null) { quit = true; await fsp.rm(tmp, { force: true }); break outer; }
        const duration = wavDurationSeconds(new Uint8Array(await fsp.readFile(tmp)));
        const vol = measureVolume(tmp);
        const warns = assessRecording({ ...vol, duration_s: duration });
        const f = (/** @type {number|null} */ v) => (v === null ? 'không xác định' : v === -Infinity ? '-inf' : v.toFixed(1));
        write(`\nThời lượng ${duration === null ? 'không xác định' : duration.toFixed(2) + ' s'} · mean ${f(vol.mean_db)} dB · max ${f(vol.max_db)} dB\n`);
        for (const w of warns) write(`  CẢNH BÁO [${w.code}]: ${w.message}\n`);
        for (;;) {
          write('[Enter] lưu & sang câu tiếp · r thu lại · p nghe lại · s bỏ qua · q thoát (không lưu bản này) > ');
          const b = await reader.next();
          const c = b === null ? 'q' : b.trim().toLowerCase();
          if (c === 'p') { spawnSync('afplay', [tmp], { stdio: 'ignore' }); continue; }
          if (c === 'r') { await fsp.rm(tmp, { force: true }); continue take; }
          if (c === 's') { await fsp.rm(tmp, { force: true }); skipped.push(p.id); continue outer; }
          if (c === 'q') { await fsp.rm(tmp, { force: true }); quit = true; break outer; }
          if (c === '') {
            await fsp.rename(tmp, path.join(o.out, files.wav));
            await fsp.writeFile(path.join(o.out, files.txt), p.text + '\n');
            saved.push(p.id);
            write(`Đã lưu ${files.wav} + ${files.txt}\n`);
            continue outer;
          }
        }
      }
    }
  } finally {
    reader.close();
  }
  const remaining = planSession(o.prompts, await fsp.readdir(o.out)).pending.length;
  return { saved, skipped, quit, remaining };
}
