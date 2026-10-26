import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdtempSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { loadConfig, DEFAULT_CONFIG } from './config.js';

function tmp(t) {
  const dir = mkdtempSync(join(tmpdir(), 'vflow-post-config-'));
  t.after(() => rmSync(dir, { recursive: true, force: true }));
  return dir;
}

test('không có tệp ⇒ mặc định theo contract', (t) => {
  const c = loadConfig(join(tmp(t), 'không-có.json'));
  assert.equal(c.rewrite.url, 'http://127.0.0.1:20128/v1');
  assert.equal(c.rewrite.timeout_ms, 8000);
  assert.equal(c.rewrite.model, null);
  assert.equal(c.auto.apps['com.apple.mail'], 'email');
  assert.equal(c.auto.apps['com.googlecode.iterm2'], 'clean');
  assert.equal(c.auto.apps['com.google.Chrome'], undefined);
  assert.deepEqual(loadConfig(), loadConfig(join(tmp(t), 'x.json')));
});

test('trộn với mặc định, giữ khoá lạ ở cấp trên, không làm hỏng DEFAULT_CONFIG', (t) => {
  const p = join(tmp(t), 'c.json');
  writeFileSync(p, JSON.stringify({ rewrite: { model: 'm', timeout_ms: 1000 }, auto: { apps: { 'a.b': 'clean' } }, server: { port: 1 } }));
  const c = loadConfig(p);
  assert.equal(c.rewrite.model, 'm');
  assert.equal(c.rewrite.url, DEFAULT_CONFIG.rewrite.url);
  assert.equal(c.auto.apps['a.b'], 'clean');
  assert.equal(c.auto.apps['com.apple.mail'], 'email');
  assert.deepEqual(c.server, { port: 1 });
  assert.equal(DEFAULT_CONFIG.auto.apps['a.b'], undefined);
});

test('sai schema ⇒ ConfigError bad_config', (t) => {
  const p = join(tmp(t), 'c.json');
  const bad = [
    [],
    { rewrite: 'x' },
    { rewrite: { url: 'ftp://x' } },
    { rewrite: { timeout_ms: 0 } },
    { rewrite: { timeout_ms: '8000' } },
    { rewrite: { model: '' } },
    { rewrite: { key_file: 5 } },
    { auto: { apps: { 'com.apple.mail': 'loud' } } },
    { auto: { apps: [] } },
    { remote: { phowhisper: { url: 7 } } },
    { default_model: '' },
  ];
  for (const b of bad) {
    writeFileSync(p, JSON.stringify(b));
    assert.throws(() => loadConfig(p), { code: 'bad_config' }, JSON.stringify(b));
  }
  writeFileSync(p, '{ hỏng');
  assert.throws(() => loadConfig(p), { code: 'bad_config', message: 'tệp cấu hình không phải JSON hợp lệ' });
});

test('từ chối khoá dán thẳng trong cấu hình', (t) => {
  const p = join(tmp(t), 'c.json');
  for (const k of ['key', 'api_key', 'apiKey', 'token']) {
    writeFileSync(p, JSON.stringify({ rewrite: { [k]: 'abc' } }));
    assert.throws(() => loadConfig(p), { code: 'bad_config', message: /key_file/ });
  }
});
