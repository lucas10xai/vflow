#!/usr/bin/env node
/**
 * vflow — CLI của engine đọc chính tả tiếng Việt chạy trong máy.
 * Mã thoát: 0 thành công, 1 lỗi khi chạy, 2 sai cú pháp.
 */
import fs from 'node:fs';
import fsp from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import { parseArgs } from 'node:util';
import { fileURLToPath } from 'node:url';
import { performance } from 'node:perf_hooks';
import { createStt, vflowHome, DEFAULT_MODEL } from '../engine/stt/index.js';
import { LOCAL_MODELS, findModel } from '../engine/stt/registry.js';
import { listModels, pullModel, verifyModel } from '../engine/stt/models.js';
import { createLocalProvider, loadSherpa } from '../engine/stt/local.js';
import { decodeAudio, toTargetRate } from '../engine/stt/audio.js';
import { createServer, listen, DEFAULT_PORT } from '../engine/server/index.js';
import { ensureToken } from '../engine/server/token.js';
import { scoreBoth } from '../eval/metrics.js';
import { runBench, benchMarkdown } from '../eval/bench.js';
import { findPairs, loadTerms, summarize, evalMarkdown } from '../eval/evaluate.js';

const USAGE = `Cách dùng: vflow <lệnh> [tuỳ chọn]

  transcribe <wav> [--model id] [--json]       nhận dạng một tệp wav (PCM16)
  models list                                  liệt kê model và trạng thái
  models pull <id>                             tải model về ~/.vflow/models/<id>/ (kiểm sha256)
  serve [--port N]                             chạy HTTP cục bộ 127.0.0.1 (mặc định ${DEFAULT_PORT} hoặc VFLOW_PORT)
  snippets list                                liệt kê snippets (~/.vflow/snippets.json)
  snippets add <trigger> <text...>             thêm/thay snippet (text là các từ còn lại, nối bằng dấu cách)
  snippets remove <trigger>                    xoá snippet theo trigger
  settings get                                 in cài đặt hiện tại (JSON)
  settings set <khoá> <giá trị>                đặt một cài đặt (true/false/null/số/chuỗi), ghi ~/.vflow/config.json
  bench <wav|thư mục> [--model id] [--runs N] [--json] [--out tệp.json]
  eval --set <thư mục> [--model id] [--json] [--out tệp.json]   cặp *.wav + *.txt cùng tên
  doctor                                       kiểm nền tảng, RAM, runtime, model
  record-set --prompts <tệp> --out <thư mục> [--device N] [--redo NN,..] [--input-fake [--fake-gain=dB]]
             thu bộ câu NN.wav (16 kHz mono PCM16) + NN.txt, chỉ thu khi bấm Enter; chạy lại = tiếp tục
             quyền micro macOS: Cài đặt hệ thống → Quyền riêng tư & Bảo mật → Micrô → bật cho app terminal
             (xem eval/RECORDING.md)
  record-set --list-devices                    liệt kê thiết bị âm thanh macOS (ffmpeg avfoundation)
  compare --set <thư mục> --models id1,id2[,..] [--out <thư mục>] [--mode normal|clean|email]
          [--dictionary <tệp>] [--synthetic] [--json]   so sánh model; báo cáo mặc định ở <set>/reports/

Biến môi trường: VFLOW_HOME (mặc định ~/.vflow), VFLOW_PORT, VFLOW_REMOTE_TOKEN.`;

class UsageError extends Error {}

const home = vflowHome();
const err = (msg) => process.stderr.write(msg + '\n');
const MB = 1024 * 1024;

/** @returns {Promise<any>} */
async function readConfig() {
  const file = path.join(home, 'config.json');
  try {
    return JSON.parse(await fsp.readFile(file, 'utf8'));
  } catch (e) {
    if (/** @type {any} */ (e).code === 'ENOENT') return {};
    throw new Error(`Không đọc được ${file}: ${/** @type {Error} */ (e).message}`);
  }
}

/** @param {string} file */
async function readWave(file) {
  const bytes = new Uint8Array(await fsp.readFile(file));
  return decodeAudio(bytes, 'audio/wav');
}

const pct = (r) => (r === null ? 'không xác định' : `${(r * 100).toFixed(2)}%`);

async function cmdTranscribe(args) {
  const { values, positionals } = parseArgs({ args, allowPositionals: true, options: { model: { type: 'string' }, json: { type: 'boolean' } } });
  if (positionals.length !== 1) throw new UsageError('transcribe cần đúng một tệp wav');
  const file = positionals[0];
  const config = await readConfig();
  const stt = createStt({ home, config });
  const model = values.model ?? stt.defaultModel;
  if (!findModel(model)) throw new UsageError(`Không có model "${model}"`);
  const wave = await readWave(file);
  const t0 = performance.now();
  await stt.ensure(model);
  const loadMs = Math.round(performance.now() - t0);
  const r = await stt.transcribe(model, { pcm: wave.samples, sampleRate: wave.sampleRate });
  const refFile = file.replace(/\.wav$/i, '.txt');
  const ref = fs.existsSync(refFile) ? (await fsp.readFile(refFile, 'utf8')).trim() : null;
  const scores = ref === null ? null : scoreBoth(ref, r.text);
  const rssPeakMb = Math.round((process.resourceUsage().maxRSS / 1024) * 10) / 10;
  if (values.json) {
    process.stdout.write(JSON.stringify({ file, model, ...r, load_ms: loadMs, rss_peak_mb: rssPeakMb, reference: ref, scores }, null, 2) + '\n');
    return;
  }
  process.stdout.write(`${r.text}\n`);
  err(`[${model}] âm thanh ${r.audio_ms} ms · nhận dạng ${r.stt_ms} ms · RTF ${(r.stt_ms / Math.max(1, r.audio_ms)).toFixed(3)} · tải model ${loadMs} ms · RSS đỉnh ${rssPeakMb} MB`);
  if (ref === null) {
    err(`(không có tham chiếu ${path.basename(refFile)} — WER/CER không xác định)`);
  } else {
    err(`tham chiếu: ${ref}`);
    err(`WER ${pct(scores.tone.wer.rate)} · CER ${pct(scores.tone.cer.rate)} (nhạy dấu thanh) | WER ${pct(scores.no_tone.wer.rate)} · CER ${pct(scores.no_tone.cer.rate)} (không nhạy dấu thanh)`);
  }
}

async function cmdModels(args) {
  const [sub, id, ...rest] = args;
  if (sub === 'list') {
    for (const m of await listModels(home)) {
      const state = m.kind === 'remote' ? 'từ xa' : m.downloaded ? `đã tải (${m.checksum})` : `chưa có (${m.reason})`;
      process.stdout.write(`${m.id.padEnd(28)} ${m.kind.padEnd(7)} ${state}\n    ${m.title}${m.license ? `\n    giấy phép: ${m.license}` : ''}${m.path ? `\n    ${m.path}` : ''}\n`);
    }
    return;
  }
  if (sub === 'pull') {
    if (!id || rest.length) throw new UsageError('models pull cần đúng một id');
    const r = await pullModel(home, id, { log: err });
    for (const w of r.warnings) err(`CẢNH BÁO: ${w}`);
    process.stdout.write(`Đã tải ${id} vào ${r.dir} (${r.manifest.checksum_status})\n`);
    return;
  }
  throw new UsageError('models cần "list" hoặc "pull <id>"');
}

async function cmdServe(args) {
  const { values } = parseArgs({ args, options: { port: { type: 'string' } } });
  const port = Number(values.port ?? process.env.VFLOW_PORT ?? DEFAULT_PORT);
  if (!Number.isInteger(port) || port < 0 || port > 65535) throw new UsageError(`cổng không hợp lệ: ${values.port}`);
  const config = await readConfig();
  const { token, created } = await ensureToken(path.join(home, 'token'));
  // Hậu xử lý thật (engine/post). Không có ⇒ dừng, không chạy với bộ "đồng nhất" giả.
  const { createPostProcessor } = await import('../engine/post/index.js');
  const { createSnippetStore } = await import('../engine/post/snippets.js');
  const { createSettingsStore } = await import('../engine/post/settings.js');
  const snippets = createSnippetStore({ path: path.join(home, 'snippets.json') });
  const settings = createSettingsStore({ configPath: path.join(home, 'config.json') });
  // Lưu ý: createPostProcessor hiện tại có thể chưa nhận snippets/settings (đang ghép dần với
  // worker khác); truyền sẵn để có hiệu lực ngay khi tham số đó được thêm, không gây lỗi nếu chưa.
  const post = createPostProcessor({
    dictionaryPath: path.join(home, 'dictionary.json'), config, fetchImpl: fetch, now: () => new Date(),
    snippets, settings,
  });
  const stt = createStt({ home, config });
  const log = (e) => err(JSON.stringify({ ts: new Date().toISOString(), ...e }));
  const server = createServer({ stt, post, token, snippets, settings, log });
  const real = await listen(server, port);
  err(`vflow engine đang nghe http://127.0.0.1:${real} (token: ${path.join(home, 'token')}${created ? ', vừa tạo' : ''})`);
  try {
    await stt.ensure(stt.defaultModel);
    err(`Đã tải model mặc định ${stt.defaultModel}.`);
  } catch (e) {
    err(`CẢNH BÁO: model mặc định ${stt.defaultModel} chưa dùng được: ${/** @type {Error} */ (e).message}`);
  }
  await new Promise((resolve) => {
    const stop = () => server.close(() => resolve(undefined));
    process.once('SIGINT', stop);
    process.once('SIGTERM', stop);
  });
}

async function cmdSnippets(args) {
  const [sub, ...rest] = args;
  const { createSnippetStore } = await import('../engine/post/snippets.js');
  const store = createSnippetStore({ path: path.join(home, 'snippets.json') });
  if (sub === 'list') {
    const { entries } = store.list();
    if (entries.length === 0) { process.stdout.write('(chưa có snippet nào)\n'); return; }
    for (const e of entries) {
      process.stdout.write(`${e.trigger}\t(dùng ${e.uses} lần${e.last_used ? `, gần nhất ${e.last_used}` : ''})\n`);
    }
    return;
  }
  if (sub === 'add') {
    const [trigger, ...textParts] = rest;
    if (!trigger || textParts.length === 0) throw new UsageError('snippets add cần <trigger> <text>');
    const text = textParts.join(' ');
    const { entries } = store.list();
    store.replaceAll([...entries.filter((e) => e.trigger !== trigger), { trigger, text }]);
    process.stdout.write(`Đã lưu snippet "${trigger}".\n`);
    return;
  }
  if (sub === 'remove') {
    const [trigger] = rest;
    if (!trigger) throw new UsageError('snippets remove cần <trigger>');
    const { entries } = store.list();
    const next = entries.filter((e) => e.trigger !== trigger);
    if (next.length === entries.length) throw new Error(`Không có snippet "${trigger}".`);
    store.replaceAll(next);
    process.stdout.write(`Đã xoá snippet "${trigger}".\n`);
    return;
  }
  throw new UsageError('snippets cần "list", "add <trigger> <text>" hoặc "remove <trigger>"');
}

/** @param {string} s */
function parseSettingValue(s) {
  if (s === 'true') return true;
  if (s === 'false') return false;
  if (s === 'null') return null;
  if (/^-?\d+$/.test(s)) return Number(s);
  return s;
}

async function cmdSettings(args) {
  const [sub, ...rest] = args;
  const { createSettingsStore } = await import('../engine/post/settings.js');
  const store = createSettingsStore({ configPath: path.join(home, 'config.json') });
  if (sub === 'get') {
    process.stdout.write(JSON.stringify(store.get(), null, 2) + '\n');
    return;
  }
  if (sub === 'set') {
    const [key, value] = rest;
    if (!key || value === undefined) throw new UsageError('settings set cần <khoá> <giá trị>');
    const next = store.update({ [key]: parseSettingValue(value) });
    process.stdout.write(JSON.stringify(next, null, 2) + '\n');
    return;
  }
  throw new UsageError('settings cần "get" hoặc "set <khoá> <giá trị>"');
}

/** @param {string} target @returns {Promise<string[]>} */
async function wavFiles(target) {
  const st = await fsp.stat(target);
  if (st.isFile()) return [target];
  const names = (await fsp.readdir(target)).filter((n) => /\.wav$/i.test(n)).sort();
  if (names.length === 0) throw new Error(`Không có tệp .wav trong ${target}`);
  return names.map((n) => path.join(target, n));
}

/** @param {any} out @param {string} md @param {{json?: boolean, out?: string}} values */
async function emit(out, md, values) {
  if (values.out) await fsp.writeFile(values.out, JSON.stringify(out, null, 2) + '\n');
  process.stdout.write((values.json ? JSON.stringify(out, null, 2) : md) + '\n');
}

async function cmdBench(args) {
  const { values, positionals } = parseArgs({
    args, allowPositionals: true,
    options: { model: { type: 'string' }, runs: { type: 'string' }, json: { type: 'boolean' }, out: { type: 'string' } },
  });
  if (positionals.length !== 1) throw new UsageError('bench cần một tệp wav hoặc thư mục');
  const runs = Number(values.runs ?? 10);
  if (!Number.isInteger(runs) || runs < 1) throw new UsageError('--runs phải là số nguyên ≥ 1');
  const model = values.model ?? ((await readConfig()).default_model || DEFAULT_MODEL);
  if (!LOCAL_MODELS.some((m) => m.id === model)) throw new UsageError(`bench chỉ đo model cục bộ; "${model}" không phải`);
  const files = await wavFiles(positionals[0]);
  const parts = [];
  for (const f of files) parts.push(toTargetRate(await readWave(f)));
  const total = parts.reduce((n, p) => n + p.length, 0);
  const source = new Float32Array(total);
  let off = 0;
  for (const p of parts) { source.set(p, off); off += p.length; }
  const provider = createLocalProvider({ home });
  const r = await runBench({ provider, modelId: model, source, runs, log: err });
  await emit({ ...r, files: files.map((f) => path.basename(f)) }, benchMarkdown(r), values);
}

async function cmdEval(args) {
  const { values } = parseArgs({ args, options: { set: { type: 'string' }, model: { type: 'string' }, json: { type: 'boolean' }, out: { type: 'string' } } });
  if (!values.set) throw new UsageError('eval cần --set <thư mục>');
  const config = await readConfig();
  const stt = createStt({ home, config });
  const model = values.model ?? stt.defaultModel;
  if (!findModel(model)) throw new UsageError(`Không có model "${model}"`);
  const { pairs, missingRef } = await findPairs(values.set);
  if (pairs.length === 0) throw new Error(`Không có cặp .wav + .txt nào trong ${values.set}`);
  await stt.ensure(model);
  const items = [];
  for (const p of pairs) {
    const w = await readWave(p.wav);
    const r = await stt.transcribe(model, { pcm: w.samples, sampleRate: w.sampleRate });
    items.push({ name: p.name, ref: p.ref, hyp: r.text, audio_ms: r.audio_ms, stt_ms: r.stt_ms });
  }
  const s = { model, set: values.set, missing_ref: missingRef, ...summarize({ items, terms: await loadTerms() }) };
  await emit(s, evalMarkdown(s), values);
}

async function cmdDoctor() {
  let bad = 0;
  const line = (ok, label, detail) => {
    if (ok === false) bad++;
    process.stdout.write(`${ok === null ? '[ ? ]' : ok ? '[ OK ]' : '[LỖI]'} ${label}: ${detail}\n`);
  };
  line(true, 'Nền tảng', `${process.platform}-${process.arch}, Node ${process.version}, ${os.cpus()[0]?.model ?? 'CPU không xác định'} × ${os.availableParallelism()}`);
  const freeMb = Math.round(os.freemem() / MB);
  line(freeMb >= 1024 ? true : null, 'RAM', `tổng ${Math.round(os.totalmem() / MB)} MB, trống ${freeMb} MB${freeMb < 1024 ? ' (thấp)' : ''}`);
  line(true, 'Thư mục dữ liệu', home);
  try {
    loadSherpa();
    line(true, 'sherpa-onnx-node', 'nạp được');
  } catch (e) {
    line(false, 'sherpa-onnx-node', /** @type {Error} */ (e).message);
  }
  let config = {};
  try { config = await readConfig(); line(true, 'Cấu hình', fs.existsSync(path.join(home, 'config.json')) ? 'đọc được' : 'chưa có (dùng mặc định)'); } catch (e) { line(false, 'Cấu hình', /** @type {Error} */ (e).message); }
  const def = config.default_model || DEFAULT_MODEL;
  for (const m of LOCAL_MODELS) {
    try {
      const v = await verifyModel(home, m.id);
      line(v.ok, `Model ${m.id}`, v.ok ? 'có, checksum tệp khớp manifest' : `checksum lệch: ${v.mismatched.join(', ')}`);
    } catch (e) {
      line(m.id === def ? false : null, `Model ${m.id}`, `${/** @type {Error} */ (e).message}${m.id === def ? ' (model mặc định)' : ''}`);
    }
  }
  const tokenFile = path.join(home, 'token');
  if (fs.existsSync(tokenFile)) {
    const mode = fs.statSync(tokenFile).mode & 0o777;
    line(process.platform === 'win32' ? null : mode === 0o600, 'Token', process.platform === 'win32' ? 'có (Windows: không kiểm quyền 0600)' : `có, quyền ${mode.toString(8)}`);
  } else {
    line(null, 'Token', 'chưa có (sinh khi chạy serve)');
  }
  line(process.env.VFLOW_REMOTE_TOKEN ? true : null, 'VFLOW_REMOTE_TOKEN', process.env.VFLOW_REMOTE_TOKEN ? 'đã đặt (***)' : 'chưa đặt (STT từ xa sẽ báo missing_token)');
  if (bad) throw new Error(`doctor: ${bad} lỗi`);
}

async function cmdRecordSet(args) {
  const { values, positionals } = parseArgs({
    args, allowPositionals: true,
    options: {
      prompts: { type: 'string' }, out: { type: 'string' }, device: { type: 'string' }, redo: { type: 'string' },
      'list-devices': { type: 'boolean' }, 'input-fake': { type: 'boolean' }, 'fake-gain': { type: 'string' },
    },
  });
  if (positionals.length) throw new UsageError('record-set không nhận tham số vị trí');
  const rec = await import('../eval/record.js');
  if (values['list-devices']) {
    const devices = rec.listAudioDevices();
    if (devices.length === 0) throw new Error(`ffmpeg không liệt kê được thiết bị âm thanh nào.\n${rec.MIC_PERMISSION_HELP}`);
    for (const d of devices) process.stdout.write(`[${d.index}] ${d.name}\n`);
    return;
  }
  if (!values.prompts || !values.out) throw new UsageError('record-set cần --prompts <tệp> và --out <thư mục>');
  const device = Number(values.device ?? 0);
  if (!Number.isInteger(device) || device < 0) throw new UsageError(`--device phải là số nguyên ≥ 0: ${values.device}`);
  const fakeGainDb = Number(values['fake-gain'] ?? 0);
  if (!Number.isFinite(fakeGainDb)) throw new UsageError(`--fake-gain phải là số (dB): ${values['fake-gain']}`);
  if (values['fake-gain'] !== undefined && !values['input-fake']) throw new UsageError('--fake-gain chỉ dùng với --input-fake');
  const redo = values.redo ? values.redo.split(',').map((x) => x.trim().padStart(2, '0')) : [];
  const prompts = rec.parsePrompts(await fsp.readFile(values.prompts, 'utf8'));
  const out = path.resolve(values.out);
  const repo = fileURLToPath(new URL('..', import.meta.url)).replace(/[\\/]+$/, '');
  if (out === repo || out.startsWith(repo + path.sep)) throw new UsageError(`Không ghi âm thanh vào trong repo (${repo}); dùng ví dụ ~/.vflow/eval/<tên-bộ>/`);
  if (!values['input-fake']) {
    if (process.platform !== 'darwin') throw new Error('Thu bằng micro chỉ hỗ trợ macOS (avfoundation); dùng --input-fake để thử.');
    const devices = rec.listAudioDevices();
    const d = devices.find((x) => x.index === device);
    if (!d) throw new Error(`Không có thiết bị âm thanh [${device}]. Có: ${devices.map((x) => `[${x.index}] ${x.name}`).join(', ') || 'không có'}\n${rec.MIC_PERMISSION_HELP}`);
    process.stdout.write(`Micro: [${d.index}] ${d.name}\n(Lần đầu thu, macOS sẽ hỏi quyền micro cho ứng dụng terminal; nếu thu ra im lặng hoặc lỗi:)\n${rec.MIC_PERMISSION_HELP}\n`);
  } else {
    process.stdout.write(`Nguồn GIẢ (ffmpeg lavfi sine 440 Hz${fakeGainDb ? `, ${fakeGainDb} dB` : ''}): bộ này sẽ bị đánh dấu synthetic.\n`);
  }
  const r = await rec.recordSession({ prompts, out, device, fake: Boolean(values['input-fake']), fakeGainDb, redo, promptsFile: values.prompts });
  process.stdout.write(`\nKết thúc: lưu ${r.saved.length} câu${r.saved.length ? ` (${r.saved.join(', ')})` : ''}, bỏ qua ${r.skipped.length}, còn thiếu ${r.remaining}/${prompts.length}.${r.remaining ? ' Chạy lại lệnh để tiếp tục.' : ''}\n`);
}

async function cmdCompare(args) {
  const { values, positionals } = parseArgs({
    args, allowPositionals: true,
    options: {
      set: { type: 'string' }, models: { type: 'string' }, out: { type: 'string' }, mode: { type: 'string' },
      dictionary: { type: 'string' }, synthetic: { type: 'boolean' }, json: { type: 'boolean' },
    },
  });
  if (positionals.length) throw new UsageError('compare không nhận tham số vị trí');
  if (!values.set || !values.models) throw new UsageError('compare cần --set <thư mục> và --models id1,id2');
  const models = [...new Set(values.models.split(',').map((x) => x.trim()).filter(Boolean))];
  for (const m of models) if (!findModel(m)) throw new UsageError(`Không có model "${m}"`);
  const mode = values.mode ?? 'normal';
  if (!['normal', 'clean', 'email'].includes(mode)) throw new UsageError(`--mode phải là normal|clean|email: ${mode}`);
  const cmp = await import('../eval/compare.js');
  const setDir = path.resolve(values.set);
  const { pairs, missingRef } = await findPairs(setDir);
  if (pairs.length === 0) throw new Error(`Không có cặp .wav + .txt nào trong ${setDir}`);
  const meta = (await cmp.readSetMeta(setDir)) ?? (values.synthetic ? {} : null);
  if (values.synthetic && meta) meta.synthetic = true;
  const config = await readConfig();
  // Từ điển dùng bản sao trong thư mục tạm: post tăng `uses` và ghi tệp mỗi lần thay, không được đụng
  // ~/.vflow/dictionary.json của người dùng. Không có --dictionary ⇒ chỉ hạt giống.
  const tmp = await fsp.mkdtemp(path.join(os.tmpdir(), 'vflow-compare-'));
  try {
    const dictPath = path.join(tmp, 'dictionary.json');
    if (values.dictionary) await fsp.copyFile(values.dictionary, dictPath);
    const { createPostProcessor } = await import('../engine/post/index.js');
    const post = createPostProcessor({ dictionaryPath: dictPath, config, log: () => {} });
    const stt = createStt({ home, config });
    const runs = await cmp.runCompare({ pairs, models, stt, post, readWave, mode, log: err });
    const report = cmp.buildReport({
      set: setDir, meta, count: pairs.length, missing_ref: missingRef, mode,
      dictionary: values.dictionary ? `bản sao của ${path.basename(values.dictionary)}` : 'chỉ hạt giống config/dictionary.seed.json',
      terms: await loadTerms(), runs,
      host: `${os.hostname().split('.')[0]} (${process.platform}-${process.arch}, ${os.cpus()[0]?.model ?? 'CPU?'})`,
    });
    const md = cmp.compareMarkdown(report);
    const outDir = path.resolve(values.out ?? path.join(setDir, 'reports'));
    await fsp.mkdir(outDir, { recursive: true, mode: 0o700 });
    const stamp = report.date.replace(/[:.]/g, '-');
    const base = path.join(outDir, `compare-${stamp}`);
    await fsp.writeFile(`${base}.json`, JSON.stringify(report, null, 2) + '\n');
    await fsp.writeFile(`${base}.md`, md + '\n');
    process.stdout.write((values.json ? JSON.stringify(report, null, 2) : md) + '\n');
    err(`Báo cáo: ${base}.md và ${base}.json`);
    if (Object.values(report.models).every((s) => s.ok === 0)) throw new Error('Không model nào chạy được clip nào');
  } finally {
    await fsp.rm(tmp, { recursive: true, force: true });
  }
}

async function main(argv) {
  const [cmd, ...args] = argv;
  switch (cmd) {
    case 'transcribe': return cmdTranscribe(args);
    case 'models': return cmdModels(args);
    case 'serve': return cmdServe(args);
    case 'snippets': return cmdSnippets(args);
    case 'settings': return cmdSettings(args);
    case 'bench': return cmdBench(args);
    case 'eval': return cmdEval(args);
    case 'doctor': return cmdDoctor();
    case 'record-set': return cmdRecordSet(args);
    case 'compare': return cmdCompare(args);
    case undefined: case '-h': case '--help': case 'help':
      process.stdout.write(USAGE + '\n');
      if (cmd === undefined) process.exitCode = 2;
      return;
    default: throw new UsageError(`lệnh không biết: ${cmd}`);
  }
}

main(process.argv.slice(2)).catch((e) => {
  if (e instanceof UsageError || e?.code === 'ERR_PARSE_ARGS_UNKNOWN_OPTION' || e?.code === 'ERR_PARSE_ARGS_UNEXPECTED_POSITIONAL') {
    err(`vflow: ${e.message}\n\n${USAGE}`);
    process.exitCode = 2;
    return;
  }
  const code = e?.code && typeof e.code === 'string' ? `[${e.code}${e.reason ? `/${e.reason}` : ''}] ` : '';
  err(`vflow: ${code}${e?.message ?? e}`);
  process.exitCode = 1;
});
