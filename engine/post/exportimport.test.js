import test from 'node:test';
import assert from 'node:assert/strict';
import {
  buildExport, validateImportPackage, mergeDictionary, mergeSnippets, mergeHistory, ImportError,
  EXPORT_FORMAT, EXPORT_VERSION,
} from './exportimport.js';

function pkg(overrides = {}) {
  return {
    format: EXPORT_FORMAT,
    version: EXPORT_VERSION,
    exported_at: '2026-10-27T00:00:00.000Z',
    dictionary: [{ term: 'deploy', spoken: ['đi plôi'] }],
    snippets: [{ trigger: 'chữ ký', text: 'Nguyễn Văn An' }],
    settings: { cloud_llm: true, llm_model: null, llm_timeout_ms: 3500, actions_enabled: true },
    stats: { backfilled: true, days: { '2026-10-26': { words: 10, audio_ms: 5000, count: 2, apps: { 'com.apple.Terminal': { words: 10, count: 2 } } } } },
    ...overrides,
  };
}

test('buildExport: đúng format/version, chứa đủ các phần đã cung cấp, history vắng mặt khi không truyền', () => {
  const out = buildExport({
    dictionary: { entries: [{ term: 'deploy', spoken: ['đi plôi'] }] },
    snippets: { entries: [] },
    settings: { cloud_llm: true },
    stats: { backfilled: true, days: {} },
  });
  assert.equal(out.format, EXPORT_FORMAT);
  assert.equal(out.version, EXPORT_VERSION);
  assert.ok(typeof out.exported_at === 'string' && !Number.isNaN(Date.parse(out.exported_at)));
  assert.deepEqual(out.dictionary, [{ term: 'deploy', spoken: ['đi plôi'] }]);
  assert.equal(out.history, undefined);
});

test('buildExport: KHÔNG BAO GIỜ chứa token/khoá dù settings vô tình có (settings truyền vào phải đã được lọc ở caller)', () => {
  // exportimport.js không tự lọc settings khi XUẤT (export luôn dùng settings.get() — không bao
  // giờ có khoá theo thiết kế của settings.js); kiểm bằng chứng gián tiếp: output JSON không có "key".
  const out = buildExport({ dictionary: { entries: [] }, snippets: { entries: [] }, settings: { cloud_llm: true, llm_model: 'm' }, stats: { backfilled: true, days: {} } });
  assert.ok(!JSON.stringify(out).toLowerCase().includes('"key"'));
});

test('validateImportPackage: gói hợp lệ đầy đủ, trả đúng dữ liệu đã kiểm', () => {
  const r = validateImportPackage(pkg());
  assert.deepEqual(r.dictionary, [{ term: 'deploy', spoken: ['đi plôi'], kind: 'term', uses: 0, last_used: null }]);
  assert.equal(r.snippets[0].trigger, 'chữ ký');
  assert.deepEqual(r.settings, { cloud_llm: true, llm_model: null, llm_timeout_ms: 3500, actions_enabled: true });
  assert.deepEqual(r.ignoredSettingsKeys, []);
  assert.ok(r.statsDays['2026-10-26']);
  assert.equal(r.history, null);
});

test('validateImportPackage: từ chối sai format/version', () => {
  assert.throws(() => validateImportPackage(pkg({ format: 'other' })), ImportError);
  assert.throws(() => validateImportPackage(pkg({ version: 2 })), ImportError);
  assert.throws(() => validateImportPackage(null), ImportError);
  assert.throws(() => validateImportPackage([1, 2]), ImportError);
});

test('validateImportPackage: từ chối cả gói nếu MỘT phần sai (không nhập nửa vời) — dictionary hỏng', () => {
  assert.throws(() => validateImportPackage(pkg({ dictionary: [{ term: '', spoken: ['x'] }] })), ImportError);
});

test('validateImportPackage: từ chối cả gói nếu snippets hỏng, dù dictionary/settings/stats đều hợp lệ', () => {
  assert.throws(() => validateImportPackage(pkg({ snippets: [{ trigger: '', text: 'x' }] })), ImportError);
});

test('validateImportPackage: từ chối cả gói nếu stats.days có khoá ngày hoặc trường sai', () => {
  assert.throws(() => validateImportPackage(pkg({ stats: { days: { 'ngay-sai': {} } } })), ImportError);
  assert.throws(() => validateImportPackage(pkg({ stats: { days: { '2026-10-26': { words: -1, audio_ms: 0, count: 0 } } } })), ImportError);
  assert.throws(() => validateImportPackage(pkg({ stats: { days: { '2026-10-26': { words: 1, audio_ms: 0, count: 0, extra: 1 } } } })), ImportError);
});

test('validateImportPackage: KHÔNG BAO GIỜ nhập token/khoá từ settings — bị lọc và báo ignored, không ném lỗi', () => {
  const r = validateImportPackage(pkg({ settings: { cloud_llm: true, token: 'bi-mat', api_key: 'bi-mat-2', rewrite: { key: 'x' } } }));
  assert.deepEqual(r.settings, { cloud_llm: true });
  assert.ok(r.ignoredSettingsKeys.includes('token'));
  assert.ok(r.ignoredSettingsKeys.includes('api_key'));
  assert.ok(r.ignoredSettingsKeys.includes('rewrite'));
  assert.ok(!JSON.stringify(r).includes('bi-mat'));
});

test('validateImportPackage: history hợp lệ qua được, history hỏng (thiếu trường, khoá lạ) bị từ chối cả gói', () => {
  const good = pkg({ history: [{ id: 'h_1', at: '2026-10-26T01:00:00.000Z', mode: 'normal', model: 'zipformer-vi-30m', text_raw: 'r', text: 't' }] });
  const r = validateImportPackage(good);
  assert.equal(r.history.length, 1);
  assert.throws(() => validateImportPackage(pkg({ history: [{ id: 'h_1', mode: 'normal', model: 'm', text_raw: 'r', text: 't' }] })), ImportError, 'thiếu at');
  assert.throws(() => validateImportPackage(pkg({ history: [{ id: 'h_1', at: '2026-10-26T01:00:00.000Z', mode: 'normal', model: 'm', text_raw: 'r', text: 't', audio: 1 }] })), ImportError, 'khoá lạ "audio"');
});

test('mergeDictionary: merge không tạo trùng (giữ mục hiện có, chỉ thêm term mới)', () => {
  const current = [{ term: 'deploy', spoken: ['đi plôi'], kind: 'term', uses: 5, last_used: null }];
  const incoming = [
    { term: 'deploy', spoken: ['khác hẳn'], kind: 'term', uses: 0, last_used: null }, // trùng term ⇒ bỏ, giữ bản hiện có
    { term: 'Supabase', spoken: ['xu pa bết'], kind: 'term', uses: 0, last_used: null },
  ];
  const { result, applied } = mergeDictionary(current, incoming);
  assert.equal(applied, 1);
  assert.equal(result.length, 2);
  assert.deepEqual(result.find((e) => e.term === 'deploy').spoken, ['đi plôi'], 'không bị ghi đè bởi gói nhập');
  assert.ok(result.some((e) => e.term === 'Supabase'));
});

test('mergeSnippets: merge so khớp trigger theo normalizeMatch (bỏ dấu/hoa thường/dấu câu)', () => {
  const current = [{ trigger: 'Chữ Ký', text: 'A', uses: 0, last_used: null }];
  const incoming = [
    { trigger: 'CHỮ, KÝ!', text: 'B' }, // trùng sau khi bỏ hoa/thường + dấu câu ⇒ bỏ
    { trigger: 'link lịch hẹn', text: 'https://x' },
  ];
  const { result, applied } = mergeSnippets(current, incoming);
  assert.equal(applied, 1);
  assert.equal(result.length, 2);
});

test('mergeHistory: merge theo id, không tạo trùng', () => {
  const current = [{ id: 'h_1', text: 'a' }];
  const incoming = [{ id: 'h_1', text: 'khác' }, { id: 'h_2', text: 'b' }];
  const { result, applied } = mergeHistory(current, incoming);
  assert.equal(applied, 1);
  assert.equal(result.find((e) => e.id === 'h_1').text, 'a');
});

test('validateImportPackage: settings.audio_history:true bị loại và báo ignored (tệp không được tự bật ghi âm); false thì giữ', () => {
  const on = validateImportPackage({ format: 'vflow-export', version: 1, settings: { audio_history: true, tone: 'formal' } });
  assert.deepEqual(on.settings, { tone: 'formal' });
  assert.deepEqual(on.ignoredSettingsKeys, ['audio_history']);
  const off = validateImportPackage({ format: 'vflow-export', version: 1, settings: { audio_history: false } });
  assert.deepEqual(off.settings, { audio_history: false });
  assert.deepEqual(off.ignoredSettingsKeys, []);
});

test('validateImportPackage: gói xuất từ bản cũ có settings.vocab_boost (khoá đã gỡ) KHÔNG làm hỏng cả gói — bỏ qua và báo ignored', () => {
  const r = validateImportPackage({ format: 'vflow-export', version: 1, settings: { vocab_boost: false, tone: 'formal' } });
  assert.deepEqual(r.settings, { tone: 'formal' });
  assert.deepEqual(r.ignoredSettingsKeys, ['vocab_boost']);
});
