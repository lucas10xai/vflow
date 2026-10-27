/**
 * Test tích hợp cho /v1/teach (A1) và lịch sử âm thanh /v1/audio* + `audio_id` (A6): ghép server thật +
 * hậu xử lý/settings/stats/kho âm thanh thật trên VFLOW_HOME tạm, STT giả (không cần model).
 */
import { test, before, after, beforeEach } from 'node:test';
import assert from 'node:assert/strict';
import http from 'node:http';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { crc32 } from 'node:zlib';
import { createServer, listen } from './index.js';
import { ensureToken } from './token.js';
import { createStt } from '../stt/index.js';
import { encodeWav } from '../stt/audio.js';
import { createPostProcessor } from '../post/index.js';
import { createSnippetStore } from '../post/snippets.js';
import { createSettingsStore } from '../post/settings.js';
import { createStatsStore } from '../post/stats.js';
import { createAudioStore } from '../post/audiostore.js';

function request(port, token, { method = 'GET', path: p, body, contentType = 'application/json', auth = true } = {}) {
  return new Promise((resolve, reject) => {
    const headers = { host: `127.0.0.1:${port}`, 'content-type': contentType };
    if (auth) headers.authorization = `Bearer ${token}`;
    const req = http.request({ host: '127.0.0.1', port, method, path: p, headers }, (res) => {
      const chunks = [];
      res.on('data', (c) => chunks.push(c));
      res.on('end', () => {
        const buf = Buffer.concat(chunks);
        let json = null;
        try { json = JSON.parse(buf.toString('utf8')); } catch { /* nhị phân */ }
        resolve({ status: res.statusCode, headers: res.headers, buf, json, text: buf.toString('utf8') });
      });
    });
    req.on('error', reject);
    if (body !== undefined) req.write(body);
    req.end();
  });
}

const tone = (rate, seconds, amp = 0.3, channels = 1) => {
  const x = new Float32Array(Math.round(rate * seconds) * channels);
  for (let i = 0; i < x.length; i++) x[i] = amp * Math.sin(2 * Math.PI * 220 * (Math.floor(i / channels) / rate));
  return x;
};

let home; let token; let port; let server; let settings; let stats; let audio; let sttText; let sttDelay; let logs;
/** Ghi đè cài đặt CHỈ cho kho âm thanh (miền thật của audio_history_mb là 50–2000 MB, quá lớn để vượt bằng audio thử). */
let budgetOverride = {};

before(async () => {
  home = fs.mkdtempSync(path.join(os.tmpdir(), 'vflow-audio-it-'));
  ({ token } = await ensureToken(path.join(home, 'token')));
  fs.writeFileSync(path.join(home, 'dictionary.json'), JSON.stringify({ entries: [{ term: 'deploy', spoken: ['đi plôi'], kind: 'term' }] }));
  const snippets = createSnippetStore({ path: path.join(home, 'snippets.json') });
  settings = createSettingsStore({ configPath: path.join(home, 'config.json') });
  stats = createStatsStore({ path: path.join(home, 'stats.json'), historyPath: path.join(home, 'history.jsonl') });
  audio = createAudioStore({ home, settings: { get: () => ({ ...settings.get(), ...budgetOverride }) }, pruneIntervalMs: 0 });
  logs = [];
  const post = createPostProcessor({ dictionaryPath: path.join(home, 'dictionary.json'), snippets, settings, log: () => {} });
  sttText = 'ĐI PLÔI LÊN STAGING';
  sttDelay = 0;
  const stt = createStt({
    home, config: { default_model: 'fake' },
    providerFactory: (id) => (id === 'fake' ? {
      loaded: false,
      async loadModel() { this.loaded = true; },
      async transcribe({ pcm, sampleRate }) {
        if (sttDelay) await new Promise((r) => setTimeout(r, sttDelay));
        return { text: sttText, audio_ms: Math.round((pcm.length / sampleRate) * 1000), stt_ms: 7 };
      },
    } : null),
  });
  server = createServer({ stt, post, token, snippets, settings, stats, audio, home, log: (e) => logs.push(e) });
  port = await listen(server, 0);
});

after(async () => {
  audio.close();
  await new Promise((r) => server.close(r));
  fs.rmSync(home, { recursive: true, force: true });
});

beforeEach(async () => {
  sttText = 'ĐI PLÔI LÊN STAGING';
  sttDelay = 0;
  budgetOverride = {};
  settings.update({ audio_history: false, whisper_mode: false, audio_history_mb: 200, audio_history_days: 7 });
  audio.removeAll();
});

const dictate = (samples, rate = 16000, channels = 1, query = 'mode=normal') =>
  request(port, token, { method: 'POST', path: `/v1/transcribe?${query}`, contentType: 'audio/wav', body: encodeWav(samples, rate, channels) });

/** Phân tích header WAV độc lập với encodeWav. */
function parseWav(buf) {
  assert.equal(buf.toString('latin1', 0, 4), 'RIFF');
  assert.equal(buf.toString('latin1', 8, 12), 'WAVE');
  assert.equal(buf.toString('latin1', 12, 16), 'fmt ');
  const fmt = { format: buf.readUInt16LE(20), channels: buf.readUInt16LE(22), rate: buf.readUInt32LE(24), byteRate: buf.readUInt32LE(28), blockAlign: buf.readUInt16LE(32), bits: buf.readUInt16LE(34) };
  assert.equal(buf.toString('latin1', 36, 40), 'data');
  const dataLen = buf.readUInt32LE(40);
  assert.equal(buf.readUInt32LE(4), 36 + dataLen, 'kích thước RIFF');
  assert.equal(buf.length, 44 + dataLen, 'độ dài tệp = header + dữ liệu');
  return { ...fmt, dataLen, samples: new Int16Array(buf.buffer.slice(buf.byteOffset + 44, buf.byteOffset + 44 + dataLen)) };
}

// ---------------------------------------------------------------- /v1/teach

test('/v1/teach: trả CHỮ THÔ (chữ thường) đúng schema, KHÔNG qua từ điển, KHÔNG ghi thống kê/âm thanh/history', async () => {
  settings.update({ audio_history: true }); // dù bật lịch sử âm thanh, teach KHÔNG được ghi
  const before = await request(port, token, { path: '/v1/stats' });
  const r = await request(port, token, { method: 'POST', path: '/v1/teach', contentType: 'audio/wav', body: encodeWav(tone(16000, 2), 16000) });
  assert.equal(r.status, 200);
  assert.deepEqual(Object.keys(r.json).sort(), ['audio_ms', 'heard', 'stt_ms']);
  assert.equal(r.json.heard, 'đi plôi lên staging'); // từ điển sẽ đổi "đi plôi" ⇒ "deploy": teach thì không
  assert.equal(r.json.audio_ms, 2000);
  assert.equal(r.json.stt_ms, 7);
  const after = await request(port, token, { path: '/v1/stats' });
  assert.equal(after.json.total_count, before.json.total_count);
  assert.equal((await request(port, token, { path: '/v1/audio' })).json.count, 0);
  assert.ok(!fs.existsSync(path.join(home, 'history.jsonl')));
  // so sánh: cùng audio qua /v1/transcribe thì từ điển có áp
  sttText = 'đi plôi lên staging';
  const t = await dictate(tone(16000, 2));
  assert.equal(t.json.text, 'deploy lên staging');
});

test('/v1/teach: âm thanh > 15 s ⇒ 413 too_long (KHÔNG cắt); đúng 15 s vẫn nhận; im lặng ⇒ heard rỗng', async () => {
  const long = await request(port, token, { method: 'POST', path: '/v1/teach', contentType: 'audio/wav', body: encodeWav(tone(16000, 15.5), 16000) });
  assert.equal(long.status, 413);
  assert.equal(long.json.error.code, 'too_long');
  const edge = await request(port, token, { method: 'POST', path: '/v1/teach', contentType: 'audio/wav', body: encodeWav(tone(16000, 15), 16000) });
  assert.equal(edge.status, 200);
  const quiet = await request(port, token, { method: 'POST', path: '/v1/teach', contentType: 'audio/wav', body: encodeWav(new Float32Array(16000), 16000) });
  assert.equal(quiet.status, 200);
  assert.equal(quiet.json.heard, '');
  assert.equal(quiet.json.stt_ms, 0);
});

test('/v1/teach: yêu cầu thứ hai khi đang bận ⇒ 429 busy; xong thì nhận lại được; sai định dạng/GET/thiếu token bị từ chối', async () => {
  sttDelay = 120;
  const body = encodeWav(tone(16000, 1), 16000);
  const [a, b] = await Promise.all([
    request(port, token, { method: 'POST', path: '/v1/teach', contentType: 'audio/wav', body }),
    request(port, token, { method: 'POST', path: '/v1/teach', contentType: 'audio/wav', body }),
  ]);
  assert.deepEqual([a.status, b.status].sort(), [200, 429]);
  const busy = a.status === 429 ? a : b;
  assert.equal(busy.json.error.code, 'busy');
  sttDelay = 0;
  assert.equal((await request(port, token, { method: 'POST', path: '/v1/teach', contentType: 'audio/wav', body })).status, 200);

  const bad = await request(port, token, { method: 'POST', path: '/v1/teach', contentType: 'audio/wav', body: 'không phải wav' });
  assert.equal(bad.status, 400);
  assert.equal(bad.json.error.code, 'bad_audio');
  // lỗi định dạng không được làm kẹt cờ busy
  assert.equal((await request(port, token, { method: 'POST', path: '/v1/teach', contentType: 'audio/wav', body })).status, 200);
  assert.equal((await request(port, token, { method: 'GET', path: '/v1/teach' })).status, 405);
  const noAuth = await request(port, token, { method: 'POST', path: '/v1/teach', contentType: 'audio/wav', body, auth: false });
  assert.equal(noAuth.status, 401);
});

// ---------------------------------------------------------------- audio_id + kho WAV

test('audio_id: VẮNG khi audio_history tắt (mặc định), CÓ khi bật và trỏ tới WAV tải được; GET /v1/audio liệt kê khớp', async () => {
  assert.equal(settings.get().audio_history, false);
  const off = await dictate(tone(16000, 1));
  assert.equal(off.status, 200);
  assert.ok(!('audio_id' in off.json));
  assert.equal((await request(port, token, { path: '/v1/audio' })).json.count, 0);
  assert.ok(!fs.existsSync(path.join(home, 'audio')) || fs.readdirSync(path.join(home, 'audio')).filter((f) => f.endsWith('.wav')).length === 0);

  settings.update({ audio_history: true });
  const on = await dictate(tone(16000, 1));
  assert.equal(on.status, 200);
  assert.equal(on.json.audio_id, on.json.id);
  const list = await request(port, token, { path: '/v1/audio' });
  assert.equal(list.json.enabled, true);
  assert.equal(list.json.count, 1);
  assert.equal(list.json.items[0].id, on.json.audio_id);
  assert.equal(list.json.items[0].audio_ms, 1000);
  assert.deepEqual(Object.keys(list.json.items[0]).sort(), ['at', 'audio_ms', 'bytes', 'id']);
  assert.equal(list.json.budget_bytes, 200 * 1024 * 1024);
  assert.equal(list.json.days, 7);
  assert.deepEqual([list.json.index_rebuilt, list.json.recovered, list.json.quarantined], [false, 0, 0]); // kho lành: không có gì được dựng lại/cách ly
  const got = await request(port, token, { path: `/v1/audio/${on.json.audio_id}` });
  assert.equal(got.status, 200);
  assert.equal(got.headers['content-type'], 'audio/wav');
  assert.equal(got.buf.length, list.json.items[0].bytes);
});

test('audio_id: im lặng / văn bản rỗng / lỗi KHÔNG tạo audio_id và không ghi tệp', async () => {
  settings.update({ audio_history: true });
  const silent = await dictate(new Float32Array(16000));
  assert.equal(silent.status, 200);
  assert.equal(silent.json.silence, true);
  assert.ok(!('audio_id' in silent.json));
  sttText = ''; // STT trả rỗng với tiếng có thật
  const empty = await dictate(tone(16000, 1));
  assert.equal(empty.status, 200);
  assert.ok(!('audio_id' in empty.json));
  sttText = 'ừm ừm'; // STT có chữ nhưng chế độ clean bỏ hết từ đệm ⇒ text cuối rỗng ⇒ không phải dictation thành công
  const filler = await dictate(tone(16000, 1), 16000, 1, 'mode=clean');
  assert.equal(filler.status, 200);
  assert.equal(filler.json.text, '');
  assert.ok(!('audio_id' in filler.json));
  const bad = await request(port, token, { method: 'POST', path: '/v1/transcribe', contentType: 'audio/wav', body: 'rác' });
  assert.equal(bad.status, 400);
  assert.equal((await request(port, token, { path: '/v1/audio' })).json.count, 0);
});

test('WAV lưu hợp lệ: header PCM 16 kHz mono 16-bit, độ dài khớp; đầu vào 44,1 kHz stereo được đổi về 16 kHz mono', async () => {
  settings.update({ audio_history: true });
  const r = await dictate(tone(44100, 2, 0.5, 2), 44100, 2);
  assert.equal(r.status, 200);
  const got = await request(port, token, { path: `/v1/audio/${r.json.audio_id}` });
  const w = parseWav(got.buf);
  assert.equal(w.format, 1);
  assert.equal(w.channels, 1);
  assert.equal(w.rate, 16000);
  assert.equal(w.bits, 16);
  assert.equal(w.blockAlign, 2);
  assert.equal(w.byteRate, 32000);
  assert.ok(Math.abs(w.samples.length - 32000) <= 2, `số mẫu ${w.samples.length}`);
  const peak = Math.max(...w.samples.map(Math.abs));
  assert.ok(peak > 0.45 * 32767 && peak < 0.55 * 32767, `đỉnh ${peak}`);
});

test('whisper_mode khuếch đại chỉ để nhận dạng: WAV lưu là âm thanh GỐC, không bị khuếch đại', async () => {
  settings.update({ audio_history: true, whisper_mode: true });
  const r = await dictate(tone(16000, 1, 0.02));
  const w = parseWav((await request(port, token, { path: `/v1/audio/${r.json.audio_id}` })).buf);
  const peak = Math.max(...w.samples.map(Math.abs));
  assert.ok(peak < 0.03 * 32767, `đỉnh ${peak} — bị khuếch đại?`);
});

test('vượt ngân sách trong server: tệp cũ nhất bị đuổi (id cũ ⇒ 404), hai tệp mới nhất tải được, tổng ≤ ngân sách', async () => {
  settings.update({ audio_history: true });
  budgetOverride = { audio_history_mb: 1 };
  const ids = [];
  for (let i = 0; i < 3; i++) ids.push((await dictate(tone(16000, 14))).json.audio_id); // 3 × ~448 KB > 1 MB
  assert.ok(ids.every(Boolean));
  assert.equal((await request(port, token, { path: `/v1/audio/${ids[0]}` })).status, 404);
  assert.equal((await request(port, token, { path: `/v1/audio/${ids[1]}` })).status, 200);
  assert.equal((await request(port, token, { path: `/v1/audio/${ids[2]}` })).status, 200);
  const list = (await request(port, token, { path: '/v1/audio' })).json;
  assert.equal(list.count, 2);
  assert.ok(list.bytes <= 1024 * 1024);
  assert.deepEqual(fs.readdirSync(path.join(home, 'audio')).filter((f) => f.endsWith('.wav')).sort(), [`${ids[1]}.wav`, `${ids[2]}.wav`].sort());
});

test('một dictation lớn hơn cả ngân sách bị đuổi ngay ⇒ phản hồi KHÔNG có audio_id (không trỏ vào tệp đã mất), dictation vẫn thành công', async () => {
  settings.update({ audio_history: true });
  budgetOverride = { audio_history_mb: 0.4 }; // làm tròn về 0 byte: mọi tệp đều vượt
  const r = await dictate(tone(16000, 1));
  assert.equal(r.status, 200);
  assert.equal(r.json.text, 'Deploy LÊN STAGING');
  assert.ok(!('audio_id' in r.json));
  assert.equal((await request(port, token, { path: '/v1/audio' })).json.count, 0);
});

// ---------------------------------------------------------------- xoá / xuất / bảo mật

test('DELETE /v1/audio/<id>: xoá đúng một tệp (404 nếu không có/đã xoá); DELETE /v1/audio xoá hết', async () => {
  settings.update({ audio_history: true });
  const a = (await dictate(tone(16000, 1))).json.audio_id;
  const b = (await dictate(tone(16000, 1))).json.audio_id;
  const d = await request(port, token, { method: 'DELETE', path: `/v1/audio/${a}` });
  assert.equal(d.status, 200);
  assert.deepEqual(d.json, { ok: true, deleted: 1 });
  assert.equal((await request(port, token, { method: 'DELETE', path: `/v1/audio/${a}` })).status, 404);
  assert.equal((await request(port, token, { path: `/v1/audio/${a}` })).status, 404);
  assert.equal((await request(port, token, { path: `/v1/audio/${b}` })).status, 200);
  const all = await request(port, token, { method: 'DELETE', path: '/v1/audio' });
  assert.deepEqual(all.json, { ok: true, deleted: 1 });
  assert.equal((await request(port, token, { path: `/v1/audio/${b}` })).status, 404);
  assert.deepEqual(fs.readdirSync(path.join(home, 'audio')).filter((f) => f.endsWith('.wav')), []);
});

test('path traversal: id chứa ../ hoặc %2e%2e không đọc/xoá được tệp ngoài thư mục audio (token vẫn còn nguyên)', async () => {
  const tokenBefore = fs.readFileSync(path.join(home, 'token'), 'utf8');
  for (const evil of ['..%2ftoken', '..%2f..%2ftoken', '%2e%2e%2ftoken', '..', '.%2e', 'a%2fb', 'a%5cb', '..%5ctoken']) {
    const g = await request(port, token, { path: `/v1/audio/${evil}` });
    assert.ok([404, 400].includes(g.status), `GET ${evil} ⇒ ${g.status}`);
    assert.ok(!g.text.includes(tokenBefore.trim()), `GET ${evil} lộ token`);
    const d = await request(port, token, { method: 'DELETE', path: `/v1/audio/${evil}` });
    assert.ok([404, 400].includes(d.status), `DELETE ${evil} ⇒ ${d.status}`);
  }
  assert.equal(fs.readFileSync(path.join(home, 'token'), 'utf8'), tokenBefore);
});

test('mọi route âm thanh cần token (không token ⇒ 401)', async () => {
  for (const [method, p] of [['GET', '/v1/audio'], ['DELETE', '/v1/audio'], ['GET', '/v1/audio/export'], ['GET', '/v1/audio/tr_x'], ['DELETE', '/v1/audio/tr_x']]) {
    const r = await request(port, token, { method, path: p, auth: false });
    assert.equal(r.status, 401, `${method} ${p}`);
  }
});

/** Đọc ZIP (store, data descriptor) từ central directory, kiểm CRC bằng zlib.crc32. */
function unzip(buf) {
  const eocd = buf.lastIndexOf(Buffer.from([0x50, 0x4b, 0x05, 0x06]));
  assert.ok(eocd >= 0);
  const count = buf.readUInt16LE(eocd + 10);
  let p = buf.readUInt32LE(eocd + 16);
  const out = {};
  for (let i = 0; i < count; i++) {
    const crc = buf.readUInt32LE(p + 16); const size = buf.readUInt32LE(p + 24); const nlen = buf.readUInt16LE(p + 28);
    const local = buf.readUInt32LE(p + 42);
    const name = buf.toString('utf8', p + 46, p + 46 + nlen);
    const start = local + 30 + buf.readUInt16LE(local + 26) + buf.readUInt16LE(local + 28);
    const data = buf.subarray(start, start + size);
    assert.equal(crc32(data), crc, `CRC ${name}`);
    out[name] = data;
    p += 46 + nlen;
  }
  return out;
}

test('GET /v1/audio/export: ZIP hợp lệ, có index.json (chỉ id/at/audio_ms/app/mode — KHÔNG có văn bản) và từng WAV đúng byte', async () => {
  settings.update({ audio_history: true });
  const r1 = await dictate(tone(16000, 1), 16000, 1, 'mode=clean&app=com.apple.Terminal');
  const r2 = await dictate(tone(16000, 2));
  const z = await request(port, token, { path: '/v1/audio/export' });
  assert.equal(z.status, 200);
  assert.equal(z.headers['content-type'], 'application/zip');
  const files = unzip(z.buf);
  assert.deepEqual(Object.keys(files).sort(), ['index.json', `${r1.json.audio_id}.wav`, `${r2.json.audio_id}.wav`].sort());
  const index = JSON.parse(files['index.json'].toString());
  assert.equal(index.length, 2);
  for (const e of index) assert.deepEqual(Object.keys(e).sort(), ['app', 'at', 'audio_ms', 'id', 'mode']);
  assert.equal(index.find((e) => e.id === r1.json.audio_id).app, 'com.apple.Terminal');
  assert.equal(index.find((e) => e.id === r1.json.audio_id).mode, 'clean');
  assert.ok(!files['index.json'].toString().includes('deploy'), 'index không được chứa văn bản dictation');
  const one = await request(port, token, { path: `/v1/audio/${r1.json.audio_id}` });
  assert.ok(files[`${r1.json.audio_id}.wav`].equals(one.buf));
  // kho rỗng ⇒ ZIP hợp lệ chỉ có index.json = []
  audio.removeAll();
  const empty = unzip((await request(port, token, { path: '/v1/audio/export' })).buf);
  assert.deepEqual(Object.keys(empty), ['index.json']);
  assert.deepEqual(JSON.parse(empty['index.json'].toString()), []);
});

test('BẤT BIẾN: âm thanh/đường dẫn kho KHÔNG xuất hiện trong /v1/export, /v1/diagnostics, log; log không có văn bản giọng nói', async () => {
  settings.update({ audio_history: true });
  logs.length = 0;
  sttText = 'MẬT KHẨU CỦA TÔI LÀ CÂU BÍ MẬT';
  const r = await dictate(tone(16000, 1));
  const id = r.json.audio_id;
  assert.ok(id);
  await request(port, token, { path: `/v1/audio/${id}` });
  const checkNoAudioTraces = (name, res) => {
    assert.equal(res.status, 200, name);
    for (const needle of [id, 'khong-co', 'index.json', '.wav', path.join(home, 'audio'), home]) {
      assert.ok(!res.text.includes(needle), `${name} chứa "${needle}"`);
    }
    assert.ok(!/RIFF/.test(res.text), `${name} chứa dữ liệu WAV`);
  };
  // (1) khi âm thanh ĐANG tồn tại: export/diagnostics không có dấu vết
  checkNoAudioTraces('export', await request(port, token, { path: '/v1/export?include_history=1' }));
  checkNoAudioTraces('diagnostics(1)', await request(port, token, { path: '/v1/diagnostics' }));
  // (2) 404 với id thật (đã xoá) và id lạ rơi vào recent_errors: route không được mang id
  await request(port, token, { method: 'DELETE', path: `/v1/audio/${id}` });
  assert.equal((await request(port, token, { path: `/v1/audio/${id}` })).status, 404);
  assert.equal((await request(port, token, { path: '/v1/audio/khong-co' })).status, 404);
  const diag = await request(port, token, { path: '/v1/diagnostics' });
  checkNoAudioTraces('diagnostics(2)', diag);
  assert.ok(diag.json.recent_errors.some((e) => e.route === '/v1/audio/:id' && e.code === 'not_found'));
  const logText = JSON.stringify(logs);
  assert.ok(!/bí mật|BÍ MẬT|mật khẩu|MẬT KHẨU/i.test(logText), 'log chứa văn bản giọng nói');
  assert.ok(!logText.includes(home), 'log chứa đường dẫn VFLOW_HOME');
  assert.ok(!logText.includes('RIFF'));
});

test('PUT /v1/settings: khoá audio/context_symbols đúng miền giá trị; ngoài miền hoặc khoá đã gỡ (vocab_boost) ⇒ 400, giá trị cũ giữ nguyên', async () => {
  const put = (obj) => request(port, token, { method: 'PUT', path: '/v1/settings', body: JSON.stringify(obj) });
  assert.equal((await put({ audio_history_mb: 50, audio_history_days: 1, audio_history: true, context_symbols: false })).status, 200);
  assert.equal((await put({ audio_history_mb: 2000, audio_history_days: 90 })).status, 200);
  for (const bad of [{ audio_history_mb: 49 }, { audio_history_mb: 2001 }, { audio_history_mb: 100.5 }, { audio_history_mb: '200' },
    { audio_history_days: 0 }, { audio_history_days: 91 }, { audio_history_days: 1.5 }, { audio_history: 'true' }, { vocab_boost: 1 }, { context_symbols: null }]) {
    const r = await put(bad);
    assert.equal(r.status, 400, JSON.stringify(bad));
  }
  const now = (await request(port, token, { path: '/v1/settings' })).json;
  assert.ok(!('vocab_boost' in now));
  assert.equal(now.audio_history_mb, 2000);
  assert.equal(now.audio_history_days, 90);
  assert.equal(now.context_symbols, false);
  settings.update({ context_symbols: true });
});

test('POST /v1/import: gói chứa audio_history:true KHÔNG được bật ghi âm (báo ignored); audio_history:false vẫn áp dụng', async () => {
  settings.update({ audio_history: false });
  const on = await request(port, token, { method: 'POST', path: '/v1/import', body: JSON.stringify({ format: 'vflow-export', version: 1, settings: { audio_history: true, tone: 'formal' } }) });
  assert.equal(on.status, 200, on.text);
  assert.deepEqual(on.json.ignored, ['audio_history']);
  assert.equal(settings.get().audio_history, false);
  assert.equal(settings.get().tone, 'formal');
  settings.update({ audio_history: true, tone: 'neutral' });
  const off = await request(port, token, { method: 'POST', path: '/v1/import', body: JSON.stringify({ format: 'vflow-export', version: 1, settings: { audio_history: false } }) });
  assert.equal(off.status, 200);
  assert.equal(settings.get().audio_history, false);
});
