/**
 * Test tích hợp thật cho các route mới (E2): /v1/stats, /v1/export, /v1/import, /v1/diagnostics,
 * /v1/partial, /v1/dictionary/suggestions(+dismiss), app_rules, voice_punctuation, whisper_mode,
 * degraded/degraded_reason. Ghép createPostProcessor + snippets/settings/stats/corrections thật
 * (như bin/vflow.js serve) + STT giả (providerFactory, không cần model thật).
 */
import { test, before, after } from 'node:test';
import assert from 'node:assert/strict';
import http from 'node:http';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { createServer, listen } from './index.js';
import { ensureToken } from './token.js';
import { createStt } from '../stt/index.js';
import { encodeWav } from '../stt/audio.js';
import { createPostProcessor } from '../post/index.js';
import { createSnippetStore } from '../post/snippets.js';
import { createSettingsStore } from '../post/settings.js';
import { createStatsStore } from '../post/stats.js';
import { createCorrectionsStore } from '../post/learn.js';

function request(port, token, { method = 'GET', path: p, body, contentType = 'application/json' } = {}) {
  return new Promise((resolve, reject) => {
    const req = http.request(
      { host: '127.0.0.1', port, method, path: p, headers: { host: `127.0.0.1:${port}`, authorization: `Bearer ${token}`, 'content-type': contentType } },
      (res) => {
        const chunks = [];
        res.on('data', (c) => chunks.push(c));
        res.on('end', () => {
          const text = Buffer.concat(chunks).toString('utf8');
          let json = null;
          try { json = JSON.parse(text); } catch { /* não */ }
          resolve({ status: res.statusCode, json, text });
        });
      },
    );
    req.on('error', reject);
    if (body !== undefined) req.write(body);
    req.end();
  });
}

const sine = (rate, seconds, amp = 0.3) => {
  const x = new Float32Array(Math.round(rate * seconds));
  for (let i = 0; i < x.length; i++) x[i] = amp * Math.sin(2 * Math.PI * 220 * (i / rate));
  return x;
};

let home; let token; let port; let server; let settings; let stats; let sttCalls;

before(async () => {
  home = fs.mkdtempSync(path.join(os.tmpdir(), 'vflow-newroutes-'));
  ({ token } = await ensureToken(path.join(home, 'token')));
  // Tệp từ điển rỗng SẴN để không rơi về hạt giống (config/dictionary.seed.json đã có sẵn nhiều
  // thuật ngữ, trong đó có "Supabase"/"xu pa bết" dùng trong test gợi ý dưới đây).
  fs.writeFileSync(path.join(home, 'dictionary.json'), JSON.stringify({ entries: [] }));
  const snippets = createSnippetStore({ path: path.join(home, 'snippets.json') });
  settings = createSettingsStore({ configPath: path.join(home, 'config.json') });
  stats = createStatsStore({ path: path.join(home, 'stats.json'), historyPath: path.join(home, 'history.jsonl') });
  const corrections = createCorrectionsStore({ path: path.join(home, 'corrections.json') });
  const post = createPostProcessor({ dictionaryPath: path.join(home, 'dictionary.json'), snippets, settings, corrections, log: () => {} });
  sttCalls = [];
  const stt = createStt({
    home, config: { default_model: 'fake' },
    providerFactory: (id) => (id === 'fake' ? {
      loaded: false,
      async loadModel() { this.loaded = true; },
      async transcribe({ pcm, sampleRate }) {
        sttCalls.push({ peak: Math.max(...Array.from(pcm).map(Math.abs)), n: pcm.length });
        // Độ trễ nhỏ CỐ Ý: để test 429 "busy" của /v1/partial không phụ thuộc may rủi thời điểm
        // (hai yêu cầu gửi gần như đồng thời phải chắc chắn chồng lấp ở phía server).
        await new Promise((r) => setTimeout(r, 40));
        return { text: 'gạch dưới a b c một dấu chấm hai dấu chấm', audio_ms: Math.round((pcm.length / sampleRate) * 1000), stt_ms: 5 };
      },
    } : null),
  });
  server = createServer({ stt, post, token, snippets, settings, stats, home, log: () => {} });
  port = await listen(server, 0);
});

after(async () => {
  await new Promise((r) => server.close(r));
  fs.rmSync(home, { recursive: true, force: true });
});

const auth = () => ({ authorization: `Bearer ${token}` });
const wav = (seconds = 1) => encodeWav(sine(16000, seconds), 16000);

test('GET /v1/stats: rỗng ban đầu (enabled:true, since:null); DELETE /v1/stats ⇒ {ok:true}', async () => {
  const r = await request(port, token, { path: '/v1/stats?weeks=4' });
  assert.equal(r.status, 200);
  assert.equal(r.json.enabled, true);
  assert.equal(r.json.since, null);
  assert.equal(r.json.avg_wpm, null);
  const del = await request(port, token, { method: 'DELETE', path: '/v1/stats' });
  assert.deepEqual(del.json, { ok: true });
});

test('GET /v1/stats?weeks=0 hoặc chữ ⇒ bad_request', async () => {
  const r1 = await request(port, token, { path: '/v1/stats?weeks=0' });
  assert.equal(r1.status, 400);
  const r2 = await request(port, token, { path: '/v1/stats?weeks=abc' });
  assert.equal(r2.status, 400);
});

test('/v1/transcribe thành công cộng vào /v1/stats (count/words/audio_ms theo app)', async () => {
  await request(port, token, { method: 'DELETE', path: '/v1/stats' });
  const req = http.request({ host: '127.0.0.1', port, method: 'POST', path: '/v1/transcribe?mode=dev&app=com.apple.Terminal', headers: { host: `127.0.0.1:${port}`, ...auth(), 'content-type': 'audio/wav' } });
  const body = wav(1);
  const res = await new Promise((resolve) => { req.on('response', (r) => { const c = []; r.on('data', (x) => c.push(x)); r.on('end', () => resolve({ status: r.statusCode, json: JSON.parse(Buffer.concat(c).toString()) })); }); req.write(body); req.end(); });
  assert.equal(res.status, 200, JSON.stringify(res));
  const s = await request(port, token, { path: '/v1/stats?weeks=1' });
  assert.equal(s.json.total_count, 1);
  assert.ok(s.json.total_words > 0);
  assert.ok(s.json.top_apps.some((a) => a.app === 'com.apple.Terminal'));
});

test('app_rules (settings) được tra TRƯỚC luật cứng cho mode=auto', async () => {
  await request(port, token, { method: 'PUT', path: '/v1/settings', body: JSON.stringify({ app_rules: { 'com.apple.Terminal': 'normal' } }) });
  const req = http.request({ host: '127.0.0.1', port, method: 'POST', path: '/v1/transcribe?mode=auto&app=com.apple.Terminal', headers: { host: `127.0.0.1:${port}`, ...auth(), 'content-type': 'audio/wav' } });
  const res = await new Promise((resolve) => { req.on('response', (r) => { const c = []; r.on('data', (x) => c.push(x)); r.on('end', () => resolve({ status: r.statusCode, json: JSON.parse(Buffer.concat(c).toString()) })); }); req.write(wav(1)); req.end(); });
  assert.equal(res.json.mode, 'normal', 'app_rules (normal) phải thắng luật cứng auto.apps (Terminal -> dev)');
  await request(port, token, { method: 'PUT', path: '/v1/settings', body: JSON.stringify({ app_rules: {} }) });
});

test('app_rules chọn chế độ đám mây (email) nhưng cloud_llm tắt ⇒ rơi về clean, degraded_reason=cloud_disabled', async () => {
  await request(port, token, { method: 'PUT', path: '/v1/settings', body: JSON.stringify({ app_rules: { 'com.apple.Terminal': 'email' }, cloud_llm: false }) });
  const req = http.request({ host: '127.0.0.1', port, method: 'POST', path: '/v1/transcribe?mode=auto&app=com.apple.Terminal', headers: { host: `127.0.0.1:${port}`, ...auth(), 'content-type': 'audio/wav' } });
  const res = await new Promise((resolve) => { req.on('response', (r) => { const c = []; r.on('data', (x) => c.push(x)); r.on('end', () => resolve({ status: r.statusCode, json: JSON.parse(Buffer.concat(c).toString()) })); }); req.write(wav(1)); req.end(); });
  assert.equal(res.json.mode, 'clean');
  assert.equal(res.json.post.degraded, true);
  assert.equal(res.json.post.degraded_reason, 'cloud_disabled');
  await request(port, token, { method: 'PUT', path: '/v1/settings', body: JSON.stringify({ app_rules: {}, cloud_llm: true }) });
});

test('voice_punctuation: "một dấu chấm hai dấu chấm" ⇒ dấu câu được chèn ở mode=clean; tắt voice_punctuation ⇒ giữ nguyên lời', async () => {
  const reqOn = http.request({ host: '127.0.0.1', port, method: 'POST', path: '/v1/transcribe?mode=clean', headers: { host: `127.0.0.1:${port}`, ...auth(), 'content-type': 'audio/wav' } });
  const resOn = await new Promise((resolve) => { reqOn.on('response', (r) => { const c = []; r.on('data', (x) => c.push(x)); r.on('end', () => resolve({ json: JSON.parse(Buffer.concat(c).toString()) })); }); reqOn.write(wav(1)); reqOn.end(); });
  assert.match(resOn.json.text, /\./);

  await request(port, token, { method: 'PUT', path: '/v1/settings', body: JSON.stringify({ voice_punctuation: false }) });
  const reqOff = http.request({ host: '127.0.0.1', port, method: 'POST', path: '/v1/transcribe?mode=clean', headers: { host: `127.0.0.1:${port}`, ...auth(), 'content-type': 'audio/wav' } });
  const resOff = await new Promise((resolve) => { reqOff.on('response', (r) => { const c = []; r.on('data', (x) => c.push(x)); r.on('end', () => resolve({ json: JSON.parse(Buffer.concat(c).toString()) })); }); reqOff.write(wav(1)); reqOff.end(); });
  assert.ok(!resOff.json.text.includes('.'), `tắt voice_punctuation thì không được có dấu chấm: "${resOff.json.text}"`);
  await request(port, token, { method: 'PUT', path: '/v1/settings', body: JSON.stringify({ voice_punctuation: true }) });
});

test('whisper_mode: PCM đưa vào STT có đỉnh lớn hơn khi bật so với tắt (cùng audio gốc nhỏ)', async () => {
  const quiet = () => encodeWav(sine(16000, 1, 0.01), 16000); // ~-40 dBFS, không im lặng
  await request(port, token, { method: 'PUT', path: '/v1/settings', body: JSON.stringify({ whisper_mode: false }) });
  sttCalls.length = 0;
  const req1 = http.request({ host: '127.0.0.1', port, method: 'POST', path: '/v1/transcribe?mode=normal', headers: { host: `127.0.0.1:${port}`, ...auth(), 'content-type': 'audio/wav' } });
  await new Promise((resolve) => { req1.on('response', (r) => { r.on('data', () => {}); r.on('end', resolve); }); req1.write(quiet()); req1.end(); });
  const peakOff = sttCalls[0].peak;

  await request(port, token, { method: 'PUT', path: '/v1/settings', body: JSON.stringify({ whisper_mode: true }) });
  sttCalls.length = 0;
  const req2 = http.request({ host: '127.0.0.1', port, method: 'POST', path: '/v1/transcribe?mode=normal', headers: { host: `127.0.0.1:${port}`, ...auth(), 'content-type': 'audio/wav' } });
  await new Promise((resolve) => { req2.on('response', (r) => { r.on('data', () => {}); r.on('end', resolve); }); req2.write(quiet()); req2.end(); });
  const peakOn = sttCalls[0].peak;

  assert.ok(peakOn > peakOff * 2, `whisper_mode phải khuếch đại rõ rệt (tắt=${peakOff}, bật=${peakOn})`);
  await request(port, token, { method: 'PUT', path: '/v1/settings', body: JSON.stringify({ whisper_mode: false }) });
});

test('GET /v1/dictionary/suggestions + POST dismiss: học từ POST /v1/corrections rồi gợi ý, dismiss thì hết', async () => {
  for (let i = 0; i < 2; i++) {
    await request(port, token, { method: 'POST', path: '/v1/corrections', body: JSON.stringify({ before: 'xu pa bết', after: 'Supabase' }) });
  }
  const s = await request(port, token, { path: '/v1/dictionary/suggestions' });
  assert.equal(s.status, 200);
  assert.deepEqual(s.json.suggestions.map((x) => x.term), ['Supabase']);
  const d = await request(port, token, { method: 'POST', path: '/v1/dictionary/suggestions/dismiss', body: JSON.stringify({ term: 'Supabase' }) });
  assert.deepEqual(d.json, { ok: true });
  const s2 = await request(port, token, { path: '/v1/dictionary/suggestions' });
  assert.deepEqual(s2.json.suggestions, []);
});

test('GET /v1/export → POST /v1/import (vòng lại): dictionary/snippets/settings/stats khớp, KHÔNG có token/khoá trong gói xuất', async () => {
  await request(port, token, { method: 'PUT', path: '/v1/dictionary', body: JSON.stringify({ entries: [{ term: 'deploy', spoken: ['đi plôi'] }] }) });
  await request(port, token, { method: 'PUT', path: '/v1/snippets', body: JSON.stringify({ entries: [{ trigger: 'chữ ký', text: 'Nguyễn Văn An' }] }) });
  const exp = await request(port, token, { path: '/v1/export' });
  assert.equal(exp.status, 200);
  assert.equal(exp.json.format, 'vflow-export');
  assert.equal(exp.json.history, undefined, 'include_history mặc định 0 ⇒ không có history');
  const dump = JSON.stringify(exp.json).toLowerCase();
  assert.ok(!dump.includes('"token"') && !dump.includes('"key"'), 'gói xuất không được chứa token/khoá');

  // Xoá hết rồi nhập lại từ gói đã xuất, phải khôi phục đúng.
  await request(port, token, { method: 'PUT', path: '/v1/dictionary', body: JSON.stringify({ entries: [] }) });
  await request(port, token, { method: 'PUT', path: '/v1/snippets', body: JSON.stringify({ entries: [] }) });
  const imp = await request(port, token, { method: 'POST', path: '/v1/import', body: JSON.stringify(exp.json) });
  assert.equal(imp.status, 200, JSON.stringify(imp));
  assert.ok(imp.json.ok);
  assert.equal(imp.json.applied.dictionary, 1);
  assert.equal(imp.json.applied.snippets, 1);
  const dict2 = await request(port, token, { path: '/v1/dictionary' });
  assert.ok(dict2.json.entries.some((e) => e.term === 'deploy'));
});

test('POST /v1/import: gói sai (version lạ) ⇒ bad_request, KHÔNG áp dụng gì', async () => {
  await request(port, token, { method: 'PUT', path: '/v1/dictionary', body: JSON.stringify({ entries: [{ term: 'marker-x', spoken: ['mác cơ'] }] }) });
  const bad = await request(port, token, { method: 'POST', path: '/v1/import', body: JSON.stringify({ format: 'vflow-export', version: 99, dictionary: [] }) });
  assert.equal(bad.status, 400);
  const dict = await request(port, token, { path: '/v1/dictionary' });
  assert.ok(dict.json.entries.some((e) => e.term === 'marker-x'), 'gói sai không được xoá dữ liệu hiện có');
});

test('POST /v1/import: từ chối cả gói nếu MỘT phần sai (snippets hỏng) dù dictionary hợp lệ — không nhập nửa vời', async () => {
  const before = await request(port, token, { path: '/v1/dictionary' });
  const pkgBody = JSON.stringify({
    format: 'vflow-export', version: 1,
    dictionary: [{ term: 'brand-new-term', spoken: ['brừn nừ tơm'] }],
    snippets: [{ trigger: '', text: 'x' }],
  });
  const r = await request(port, token, { method: 'POST', path: '/v1/import', body: pkgBody });
  assert.equal(r.status, 400);
  const after = await request(port, token, { path: '/v1/dictionary' });
  assert.deepEqual(after.json, before.json, 'dictionary không được đổi khi snippets trong gói hỏng');
});

test('POST /v1/import: không bao giờ nhập token/khoá dù gói có cố ý nhét vào settings', async () => {
  const r = await request(port, token, {
    method: 'POST', path: '/v1/import',
    body: JSON.stringify({ format: 'vflow-export', version: 1, settings: { cloud_llm: true, token: 'bi-mat', api_key: 'bi-mat-2' } }),
  });
  assert.equal(r.status, 200, JSON.stringify(r));
  assert.ok(r.json.ignored.includes('token'));
  assert.ok(r.json.ignored.includes('api_key'));
});

test('GET /v1/diagnostics: đủ trường, KHÔNG rò token thật/văn bản dictation dù vừa transcribe xong', async () => {
  const realToken = fs.readFileSync(path.join(home, 'token'), 'utf8').trim();
  const req = http.request({ host: '127.0.0.1', port, method: 'POST', path: '/v1/transcribe?mode=normal', headers: { host: `127.0.0.1:${port}`, ...auth(), 'content-type': 'audio/wav' } });
  await new Promise((resolve) => { req.on('response', (r) => { r.on('data', () => {}); r.on('end', resolve); }); req.write(wav(1)); req.end(); });

  const d = await request(port, token, { path: '/v1/diagnostics' });
  assert.equal(d.status, 200);
  assert.equal(d.json.engine_version, '0.1.0');
  assert.ok(typeof d.json.counts.dictionary === 'number');
  assert.ok(Array.isArray(d.json.recent_errors));
  const dump = JSON.stringify(d.json);
  assert.ok(!dump.includes(realToken), 'không được rò token thật');
  assert.ok(!dump.toLowerCase().includes('gạch dưới'), 'không được rò văn bản dictation');
});

test('POST /v1/partial: chỉ từ điển, không ghi history/thống kê, tối đa 1 đồng thời (429 busy)', async () => {
  await request(port, token, { method: 'DELETE', path: '/v1/stats' });
  const statsBefore = await request(port, token, { path: '/v1/stats?weeks=1' });

  const p1 = request(port, token, { method: 'POST', path: '/v1/partial', body: wav(1), contentType: 'audio/wav' });
  const p2 = request(port, token, { method: 'POST', path: '/v1/partial', body: wav(1), contentType: 'audio/wav' });
  const [r1, r2] = await Promise.all([p1, p2]);
  const statuses = [r1.status, r2.status].sort();
  assert.deepEqual(statuses, [200, 429], JSON.stringify([r1, r2]));
  const busy = r1.status === 429 ? r1 : r2;
  assert.equal(busy.json.error.code, 'busy');
  const ok = r1.status === 200 ? r1 : r2;
  assert.ok(typeof ok.json.text === 'string');
  assert.ok(typeof ok.json.audio_ms === 'number');
  assert.ok(typeof ok.json.stt_ms === 'number');

  const statsAfter = await request(port, token, { path: '/v1/stats?weeks=1' });
  assert.deepEqual(statsAfter.json.total_count, statsBefore.json.total_count, '/v1/partial không được ghi thống kê');
});
