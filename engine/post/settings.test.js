import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdtempSync, rmSync, readFileSync, writeFileSync, statSync, utimesSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { createSettingsStore, DEFAULT_SETTINGS } from './settings.js';

function tmp(t) {
  const dir = mkdtempSync(join(tmpdir(), 'vflow-post-settings-'));
  t.after(() => rmSync(dir, { recursive: true, force: true }));
  return dir;
}

test('chưa có tệp ⇒ mặc định theo contract', (t) => {
  const configPath = join(tmp(t), 'config.json');
  const store = createSettingsStore({ configPath });
  assert.deepEqual(store.get(), DEFAULT_SETTINGS);
});

test('llm_timeout_ms mặc định mới là 3500 (trước là 8000 — quá lâu để chờ)', (t) => {
  const configPath = join(tmp(t), 'config.json');
  const store = createSettingsStore({ configPath });
  assert.equal(store.get().llm_timeout_ms, 3500);
});

test('update: kiểm kiểu/giá trị, từ chối khoá lạ, không ghi gì nếu sai', (t) => {
  const configPath = join(tmp(t), 'config.json');
  const store = createSettingsStore({ configPath });
  store.update({ cloud_llm: false });
  const before = readFileSync(configPath, 'utf8');
  const bad = [
    { cloud_llm: 'yes' },
    { llm_model: 1 },
    { llm_model: 'x'.repeat(201) },
    { llm_timeout_ms: 999 },
    { llm_timeout_ms: 30001 },
    { llm_timeout_ms: 1000.5 },
    { llm_timeout_ms: '8000' },
    { actions_enabled: 1 },
    { stats_enabled: 'yes' },
    { voice_punctuation: 1 },
    { tone: 'angry' },
    { whisper_mode: 'yes' },
    { learn_from_edits: 'yes' },
    { live_preview: 'yes' },
    { silence_stop_seconds: -1 },
    { silence_stop_seconds: 61 },
    { silence_stop_seconds: 1.5 },
    { app_rules: 'x' },
    { app_rules: ['a'] },
    { app_rules: { not_a_bundle_id: 'clean' } },
    { app_rules: { 'com.apple.Terminal': 'auto' } }, // auto không hợp lệ cho app_rules (tránh đệ quy)
    { app_rules: { 'com.apple.Terminal': 'nope' } },
    { app_rules: Object.fromEntries(Array.from({ length: 101 }, (_, i) => [`com.example.app${i}`, 'clean'])) },
    { rewrite: { model: 'm' } },
    { unknown_key: 1 },
    { stt_language: 'fr' },
    { stt_language: 'VI' },
    { stt_language: 1 },
    { translate_target: 'english' },
    { translate_target: '' },
    { translate_target: 1 },
    { translate_formality: 'angry' },
    { translate_formality: 1 },
  ];
  for (const patch of bad) {
    assert.throws(() => store.update(patch), { code: 'bad_request' }, JSON.stringify(patch));
  }
  assert.equal(readFileSync(configPath, 'utf8'), before);
  assert.equal(store.get().cloud_llm, false);
});

test('stt_language/translate_target/translate_formality: mặc định đúng, giá trị hợp lệ được lưu và đọc lại', (t) => {
  const configPath = join(tmp(t), 'config.json');
  const store = createSettingsStore({ configPath });
  assert.equal(store.get().stt_language, 'vi');
  assert.equal(store.get().translate_target, 'en');
  assert.equal(store.get().translate_formality, 'neutral');
  for (const lang of ['vi', 'en', 'auto']) {
    assert.equal(store.update({ stt_language: lang }).stt_language, lang, lang);
  }
  for (const target of ['fr', 'JA', 'zh']) {
    assert.equal(store.update({ translate_target: target }).translate_target, target, target);
  }
  for (const formality of ['neutral', 'formal', 'casual']) {
    assert.equal(store.update({ translate_formality: formality }).translate_formality, formality, formality);
  }
});

test('app_rules: luật hợp lệ được lưu và đọc lại đúng', (t) => {
  const configPath = join(tmp(t), 'config.json');
  const store = createSettingsStore({ configPath });
  const next = store.update({ app_rules: { 'com.apple.Terminal': 'dev', 'com.apple.mail': 'tidy' } });
  assert.deepEqual(next.app_rules, { 'com.apple.Terminal': 'dev', 'com.apple.mail': 'tidy' });
  assert.deepEqual(store.get().app_rules, { 'com.apple.Terminal': 'dev', 'com.apple.mail': 'tidy' });
});

test('update nhận tập con, giữ các khoá khác của tệp (rewrite.*, auto.apps, default_model, …)', (t) => {
  const configPath = join(tmp(t), 'config.json');
  writeFileSync(configPath, JSON.stringify({
    default_model: 'zipformer-vi-30m',
    rewrite: { url: 'http://127.0.0.1:20128/v1', model: 'ag/gemini-3.8-flash', timeout_ms: 8000, key_file: '~/.vflow/rewrite.key' },
    auto: { apps: { 'com.apple.mail': 'email' } },
  }));
  const store = createSettingsStore({ configPath });
  const next = store.update({ llm_model: 'ag/gemini-3.8-flash', llm_timeout_ms: 5000 });
  assert.deepEqual(next, { ...DEFAULT_SETTINGS, llm_model: 'ag/gemini-3.8-flash', llm_timeout_ms: 5000 });
  const raw = JSON.parse(readFileSync(configPath, 'utf8'));
  assert.equal(raw.default_model, 'zipformer-vi-30m');
  assert.deepEqual(raw.rewrite, { url: 'http://127.0.0.1:20128/v1', model: 'ag/gemini-3.8-flash', timeout_ms: 8000, key_file: '~/.vflow/rewrite.key' });
  assert.deepEqual(raw.auto, { apps: { 'com.apple.mail': 'email' } });
  // Không bao giờ ghi/trả khoá bí mật.
  assert.equal(raw.key, undefined);
  assert.ok(!JSON.stringify(raw).toLowerCase().includes('"key":'));
});

test('get() phản ánh update() ngay (không cần khởi động lại)', (t) => {
  const configPath = join(tmp(t), 'config.json');
  const store = createSettingsStore({ configPath });
  assert.equal(store.get().actions_enabled, true);
  store.update({ actions_enabled: false });
  assert.equal(store.get().actions_enabled, false);
  store.update({ actions_enabled: true, llm_model: 'm' });
  assert.deepEqual(store.get(), { ...DEFAULT_SETTINGS, llm_model: 'm' });
});

test('tệp bị sửa tay giữa chừng ⇒ get() thấy giá trị mới (kiểm bằng mtime)', (t) => {
  const configPath = join(tmp(t), 'config.json');
  const store = createSettingsStore({ configPath });
  store.update({ llm_timeout_ms: 9000 });
  assert.equal(store.get().llm_timeout_ms, 9000);
  const raw = JSON.parse(readFileSync(configPath, 'utf8'));
  writeFileSync(configPath, JSON.stringify({ ...raw, llm_timeout_ms: 12000, cloud_llm: false }));
  // Đảm bảo mtime thực sự đổi (một số hệ thống tệp có độ phân giải giây).
  const future = new Date(statSync(configPath).mtimeMs + 2000);
  utimesSync(configPath, future, future);
  assert.equal(store.get().llm_timeout_ms, 12000);
  assert.equal(store.get().cloud_llm, false);
});

test('0600 và nguyên tử: không còn tệp .tmp- rơi lại sau update', (t) => {
  const dir = tmp(t);
  const configPath = join(dir, 'config.json');
  const store = createSettingsStore({ configPath });
  store.update({ cloud_llm: false });
  if (process.platform !== 'win32') assert.equal(statSync(configPath).mode & 0o777, 0o600);
});

test('tệp cấu hình hỏng (JSON sai) ⇒ lỗi rõ ràng, không âm thầm coi là mặc định', (t) => {
  const configPath = join(tmp(t), 'config.json');
  writeFileSync(configPath, '{ "cloud_llm": true,');
  const store = createSettingsStore({ configPath });
  assert.throws(() => store.get(), { code: 'bad_request', message: /JSON hợp lệ/ });
});

test('giá trị settings hỏng trong tệp (ngoài khoảng cho phép) ⇒ lỗi rõ ràng khi get()', (t) => {
  const configPath = join(tmp(t), 'config.json');
  writeFileSync(configPath, JSON.stringify({ llm_timeout_ms: 999999 }));
  const store = createSettingsStore({ configPath });
  assert.throws(() => store.get(), { code: 'bad_request' });
});

test('update từ chối patch không phải object', (t) => {
  const configPath = join(tmp(t), 'config.json');
  const store = createSettingsStore({ configPath });
  for (const bad of [null, 'x', 1, [], ['a']]) {
    assert.throws(() => store.update(bad), { code: 'bad_request' });
  }
});

test('khoá mới (A4/A6): mặc định đúng contract, miền giá trị, ghi bền; vocab_boost đã GỠ ⇒ không còn trong cài đặt và PUT bị từ chối', (t) => {
  const configPath = join(tmp(t), 'config.json');
  const store = createSettingsStore({ configPath });
  const s = store.get();
  // Giá trị viết TAY (không đọc từ DEFAULT_SETTINGS) để đổi mặc định nhầm sẽ làm test đỏ.
  assert.equal(s.context_symbols, true);
  assert.equal(s.audio_history, false); // quyền riêng tư: ghi âm lịch sử mặc định TẮT
  assert.equal(s.audio_history_mb, 200);
  assert.equal(s.audio_history_days, 7);
  for (const ok of [{ audio_history_mb: 50 }, { audio_history_mb: 2000 }, { audio_history_days: 1 }, { audio_history_days: 90 }]) {
    store.update(ok);
  }
  const frozen = readFileSync(configPath, 'utf8');
  for (const bad of [{ audio_history_mb: 49 }, { audio_history_mb: 2001 }, { audio_history_days: 0 }, { audio_history_days: 91 },
    { audio_history_mb: 100.5 }, { audio_history_days: '7' }, { audio_history: 'on' }, { vocab_boost: false }, { context_symbols: 0 }]) {
    assert.throws(() => store.update(bad), undefined, JSON.stringify(bad));
  }
  assert.equal(readFileSync(configPath, 'utf8'), frozen, 'giá trị sai không được ghi gì');
  store.update({ audio_history: true, context_symbols: false });
  const again = createSettingsStore({ configPath }).get();
  assert.ok(!('vocab_boost' in again));
  assert.deepEqual([again.audio_history, again.context_symbols, again.audio_history_mb, again.audio_history_days], [true, false, 2000, 90]);
});
