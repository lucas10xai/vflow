import { test } from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { listModels, pullModel, resolveModelFiles } from './models.js';
import { createStt } from './index.js';
import { createLocalProvider } from './local.js';
import { LOCAL_MODELS } from './registry.js';

const tmpHome = () => fs.mkdtempSync(path.join(os.tmpdir(), 'vflow-models-test-'));

test('resolveModelFiles: lý do rõ cho từng tình trạng hỏng', async (t) => {
  const home = tmpHome();
  t.after(() => fs.rmSync(home, { recursive: true, force: true }));
  await assert.rejects(resolveModelFiles(home, 'zipformer-vi-30m'), { code: 'model_unavailable', reason: 'not_downloaded' });
  await assert.rejects(resolveModelFiles(home, 'khong-co'), { code: 'model_unavailable', reason: 'unknown_model' });
  const dir = path.join(home, 'models', 'zipformer-vi-30m');
  fs.mkdirSync(dir, { recursive: true });
  fs.writeFileSync(path.join(dir, 'manifest.json'), '{hỏng');
  await assert.rejects(resolveModelFiles(home, 'zipformer-vi-30m'), { reason: 'manifest_corrupt' });
  const files = { encoder: { path: 'e.onnx' }, decoder: { path: 'd.onnx' }, joiner: { path: 'j.onnx' }, tokens: { path: 'tokens.txt' } };
  fs.writeFileSync(path.join(dir, 'manifest.json'), JSON.stringify({ files }));
  for (const f of ['e.onnx', 'd.onnx', 'tokens.txt']) fs.writeFileSync(path.join(dir, f), 'x');
  await assert.rejects(resolveModelFiles(home, 'zipformer-vi-30m'), { reason: 'files_missing', message: /j\.onnx/ });
  fs.writeFileSync(path.join(dir, 'j.onnx'), '');
  await assert.rejects(resolveModelFiles(home, 'zipformer-vi-30m'), { reason: 'files_missing' }, 'tệp rỗng coi như thiếu');
  fs.writeFileSync(path.join(dir, 'j.onnx'), 'x');
  const ok = await resolveModelFiles(home, 'zipformer-vi-30m');
  assert.equal(ok.files.joiner, path.join(dir, 'j.onnx'));
  // Manifest trỏ ra ngoài thư mục model bị từ chối.
  fs.writeFileSync(path.join(dir, 'manifest.json'), JSON.stringify({ files: { ...files, tokens: { path: '../../../etc/passwd' } } }));
  await assert.rejects(resolveModelFiles(home, 'zipformer-vi-30m'), { reason: 'manifest_corrupt' });
});

test('pullModel: sai sha256 ⇒ huỷ, không để lại thư mục model hay tệp tạm', async (t) => {
  const home = tmpHome();
  t.after(() => fs.rmSync(home, { recursive: true, force: true }));
  const fakeFetch = async () => new Response(new Uint8Array([1, 2, 3, 4]), { status: 200 });
  await assert.rejects(
    pullModel(home, 'zipformer-vi-30m-streaming', { fetchImpl: /** @type {any} */ (fakeFetch) }),
    { message: /Sai sha256/ },
  );
  assert.deepEqual(fs.readdirSync(path.join(home, 'models')), []);
  // Có sẵn bản cũ: tải hỏng không được phá bản cũ.
  const old = path.join(home, 'models', 'zipformer-vi-30m');
  fs.mkdirSync(old, { recursive: true });
  fs.writeFileSync(path.join(old, 'marker'), 'cũ');
  await assert.rejects(pullModel(home, 'zipformer-vi-30m', { fetchImpl: /** @type {any} */ (fakeFetch) }), { message: /Sai sha256/ });
  assert.deepEqual(fs.readdirSync(path.join(home, 'models')), ['zipformer-vi-30m']);
  assert.equal(fs.readFileSync(path.join(old, 'marker'), 'utf8'), 'cũ');
});

test('pullModel: HTTP lỗi ⇒ báo lỗi; id lạ hoặc model từ xa ⇒ bad_request', async (t) => {
  const home = tmpHome();
  t.after(() => fs.rmSync(home, { recursive: true, force: true }));
  const notFound = async () => new Response('x', { status: 404 });
  await assert.rejects(pullModel(home, 'zipformer-vi-30m', { fetchImpl: /** @type {any} */ (notFound) }), { message: /HTTP 404/ });
  await assert.rejects(pullModel(home, 'khong-co'), { code: 'bad_request' });
  await assert.rejects(pullModel(home, 'phowhisper-large'), { code: 'bad_request' });
});

test('listModels: chưa tải ⇒ downloaded:false kèm reason', async (t) => {
  const home = tmpHome();
  t.after(() => fs.rmSync(home, { recursive: true, force: true }));
  const l = await listModels(home);
  const z = l.find((m) => m.id === 'zipformer-vi-30m');
  assert.equal(z.downloaded, false);
  assert.equal(z.reason, 'not_downloaded');
  assert.ok(l.some((m) => m.id === 'phowhisper-large' && m.kind === 'remote'));
  // Chưa có checksum đã xác minh ⇒ báo đúng lý do (không gợi ý "models pull" vô ích như not_downloaded).
  const sv = l.find((m) => m.id === 'sense-voice-multilingual');
  assert.equal(sv.downloaded, false);
  assert.equal(sv.reason, 'checksum_unverified');
});

test('local provider: runtime thiếu ⇒ model_unavailable/runtime_missing; addon ném lỗi ⇒ load_failed', async (t) => {
  const home = tmpHome();
  t.after(() => fs.rmSync(home, { recursive: true, force: true }));
  const dir = path.join(home, 'models', 'zipformer-vi-30m');
  fs.mkdirSync(dir, { recursive: true });
  const files = {};
  for (const [role, n] of [['encoder', 'e.onnx'], ['decoder', 'd.onnx'], ['joiner', 'j.onnx'], ['tokens', 'tokens.txt']]) {
    fs.writeFileSync(path.join(dir, n), 'x');
    files[role] = { path: n };
  }
  fs.writeFileSync(path.join(dir, 'manifest.json'), JSON.stringify({ files }));
  const missing = () => { throw Object.assign(new Error('không nạp được'), { code: 'model_unavailable', reason: 'runtime_missing' }); };
  await assert.rejects(createLocalProvider({ home, sherpa: missing }).loadModel('zipformer-vi-30m'), { reason: 'runtime_missing' });
  const throwing = () => ({ OfflineRecognizer: { createAsync: async () => { throw new Error('Invalid model'); } } });
  const p = createLocalProvider({ home, sherpa: throwing });
  await assert.rejects(p.loadModel('zipformer-vi-30m'), { code: 'model_unavailable', reason: 'load_failed' });
  assert.equal(p.loaded, false);
  await assert.rejects(p.transcribe({ pcm: new Float32Array(10), sampleRate: 16000 }), { reason: 'not_loaded' });
});

test('bộ quản lý STT: model được yêu cầu hỏng ⇒ lỗi, KHÔNG dùng model khác đã tải; healthz ghi lý do', async () => {
  const used = [];
  const factory = (id) => {
    if (id === 'zipformer-vi-30m-streaming') {
      return { loaded: false, loadModel: async () => { throw Object.assign(new Error('hỏng'), { code: 'model_unavailable', reason: 'load_failed' }); } };
    }
    const p = { loaded: false, async loadModel() { p.loaded = true; }, async transcribe() { used.push(id); return { text: 'ok', audio_ms: 1, stt_ms: 1 }; } };
    return p;
  };
  const stt = createStt({ home: os.tmpdir(), providerFactory: factory });
  await stt.transcribe('zipformer-vi-30m', { pcm: new Float32Array(16), sampleRate: 16000 });
  await assert.rejects(stt.transcribe('zipformer-vi-30m-streaming', { pcm: new Float32Array(16), sampleRate: 16000 }), { code: 'model_unavailable' });
  assert.deepEqual(used, ['zipformer-vi-30m']);
  const st = await stt.status();
  assert.deepEqual(st.find((m) => m.id === 'zipformer-vi-30m'), { id: 'zipformer-vi-30m', kind: 'local', loaded: true, languages: ['vi'], auto_detect: false });
  assert.deepEqual(st.find((m) => m.id === 'zipformer-vi-30m-streaming'), { id: 'zipformer-vi-30m-streaming', kind: 'local', loaded: false, reason: 'load_failed', languages: ['vi'], auto_detect: false });
});

test('registry: whisper tiny có checksum thật (vflow tự tải và băm); sense-voice chưa có nên bị models pull chặn', async (t) => {
  const whisper = LOCAL_MODELS.find((m) => m.id === 'whisper-tiny-multilingual');
  assert.deepEqual(whisper.languages.slice(0, 2), ['vi', 'en']);
  assert.equal(whisper.autoDetect, true);
  assert.match(whisper.source.file.sha256, /^[0-9a-f]{64}$/, 'phải là sha256 thật, không phải ngụy tạo');
  assert.match(whisper.source.file.sha256Source, /vflow-pinned/);

  const senseVoice = LOCAL_MODELS.find((m) => m.id === 'sense-voice-multilingual');
  assert.equal(senseVoice.source.file.sha256, null, 'gói ~1 GB, chưa tự tải để băm trong giới hạn RAM/thời gian ⇒ chưa có checksum đã xác minh');
  const home = tmpHome();
  t.after(() => fs.rmSync(home, { recursive: true, force: true }));
  await assert.rejects(
    pullModel(home, 'sense-voice-multilingual'),
    { code: 'model_unavailable', reason: 'checksum_unverified' },
    'models pull phải từ chối, không được bỏ qua kiểm toàn vẹn',
  );
  assert.ok(!fs.existsSync(path.join(home, 'models')), 'không tạo thư mục/tệp tạm nào khi bị chặn trước khi tải');
});
