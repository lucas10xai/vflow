import test from 'node:test';
import assert from 'node:assert/strict';
import { buildDiagnostics, redactPaths } from './diagnostics.js';

test('redactPaths: thay đường dẫn dưới home bằng "~"', () => {
  const home = '/Users/example/.vflow';
  assert.equal(redactPaths(`Không tải được model tại ${home}/models/zipformer-vi-30m/encoder.onnx`, home),
    'Không tải được model tại ~/models/zipformer-vi-30m/encoder.onnx');
  assert.equal(redactPaths('không có đường dẫn nào', home), 'không có đường dẫn nào');
  assert.equal(redactPaths(42, home), 42);
});

test('buildDiagnostics: đủ trường theo contract, KHÔNG có khoá "token"/"key" ở bất kỳ đâu', () => {
  const out = buildDiagnostics({
    version: '0.1.0', node: process.version, platform: 'darwin-arm64', uptimeS: 12,
    models: [{ id: 'zipformer-vi-30m', kind: 'local', loaded: true }],
    defaultModel: 'zipformer-vi-30m',
    settings: { cloud_llm: true, llm_model: null, llm_timeout_ms: 3500, actions_enabled: true },
    counts: { dictionary: 3, snippets: 1, history: 10, stats_days: 2 },
    homeBasename: '.vflow',
    recentErrors: [{ at: '2026-10-27T00:00:00.000Z', route: '/v1/transcribe', status: 503, code: 'model_unavailable' }],
    home: '/Users/example/.vflow',
  });
  assert.equal(out.engine_version, '0.1.0');
  assert.equal(out.counts.dictionary, 3);
  assert.equal(out.paths.home_basename, '.vflow');
  assert.equal(out.recent_errors.length, 1);
  const json = JSON.stringify(out).toLowerCase();
  assert.ok(!json.includes('"key"'));
  assert.ok(!json.includes('token'));
});

test('buildDiagnostics: recent_errors tối đa 50 dòng (lấy 50 gần nhất), route được rút gọn đường dẫn nếu có', () => {
  const home = '/Users/example/.vflow';
  const many = Array.from({ length: 80 }, (_, i) => ({ at: `t${i}`, route: `/v1/x?home=${home}`, status: 500, code: `e${i}` }));
  const out = buildDiagnostics({
    version: '0.1.0', node: 'v22', platform: 'darwin-arm64', uptimeS: 1, models: [], defaultModel: 'm',
    settings: {}, counts: { dictionary: 0, snippets: 0, history: 0, stats_days: 0 }, homeBasename: null,
    recentErrors: many, home,
  });
  assert.equal(out.recent_errors.length, 50);
  assert.equal(out.recent_errors[0].code, 'e30', 'phải là 50 mục GẦN NHẤT, không phải 50 mục đầu');
  assert.ok(out.recent_errors.every((e) => !e.route.includes(home)));
});
