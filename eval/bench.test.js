import { test } from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { makeClip, runBench, benchMarkdown, startRssSampler } from './bench.js';
import { findPairs, loadTerms, summarize, evalMarkdown } from './evaluate.js';

test('makeClip: đúng độ dài, lặp nguồn ngắn, bắt đầu ở offset', () => {
  const src = Float32Array.from([1, 2, 3]);
  const c = makeClip(src, 5 / 16000, 1);
  assert.deepEqual(Array.from(c), [2, 3, 1, 2, 3]);
  assert.equal(makeClip(new Float32Array(16000), 3).length, 48000);
  assert.throws(() => makeClip(new Float32Array(0), 1));
});

test('startRssSampler: đo được RSS đỉnh khi luồng chính bị chặn đồng bộ', async () => {
  const s = startRssSampler(5);
  await s.ready;
  const startSamples = s.samples();
  const before = s.peak();
  const until = Date.now() + 150;
  let spin = 0;
  while (Date.now() < until) spin++; // chặn event loop, không cấp phát
  const samples = s.samples() - startSamples;
  await s.stop();
  assert.ok(samples >= 5, `worker phải lấy mẫu trong lúc luồng chính bận (được ${samples})`);
  assert.ok(s.peak() >= before && spin > 0);
});

test('runBench: đủ số lần mỗi độ dài, RTF = độ trễ / độ dài, có thời gian tải', async () => {
  const seen = [];
  const provider = {
    async loadModel() { await new Promise((r) => setTimeout(r, 20)); },
    async transcribe({ pcm }) { seen.push(pcm.length); await new Promise((r) => setTimeout(r, 5)); return { text: 'x' }; },
  };
  const r = await runBench({ provider, modelId: 'fake', source: new Float32Array(16000), lengths: [3, 5], runs: 4 });
  assert.equal(seen.length, 2 * (4 + 1), 'mỗi độ dài: 1 lần khởi động + 4 lần đo');
  assert.deepEqual([...new Set(seen)], [48000, 80000]);
  assert.ok(r.load_ms >= 15);
  for (const x of r.results) {
    assert.equal(x.runs, 4);
    assert.ok(x.latency_ms.median >= 4);
    assert.ok(Math.abs(x.rtf.median - x.latency_ms.median / (x.seconds * 1000)) < 0.002);
    assert.ok(x.latency_ms.p95 >= x.latency_ms.median);
  }
  assert.ok(r.rss_mb.peak_sampled >= r.rss_mb.start);
  assert.match(benchMarkdown(r), /\| 5 s \| 4 \|/);
  await assert.rejects(runBench({ provider, modelId: 'fake', source: new Float32Array(10), runs: 0 }), RangeError);
});

test('findPairs/summarize: wav thiếu .txt được liệt kê; terms.json vắng ⇒ không xác định; có ⇒ đếm', async (t) => {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'vflow-eval-test-'));
  t.after(() => fs.rmSync(dir, { recursive: true, force: true }));
  for (const n of ['a.wav', 'b.WAV', 'c.wav']) fs.writeFileSync(path.join(dir, n), '');
  fs.writeFileSync(path.join(dir, 'a.txt'), 'deploy bản mới\n');
  fs.writeFileSync(path.join(dir, 'b.txt'), 'xin chào');
  const { pairs, missingRef } = await findPairs(dir);
  assert.deepEqual(pairs.map((p) => [p.name, p.ref]), [['a', 'deploy bản mới'], ['b', 'xin chào']]);
  assert.deepEqual(missingRef, ['c.wav']);

  assert.equal(await loadTerms(path.join(dir, 'khong-co.json')), null);
  fs.writeFileSync(path.join(dir, 'terms.json'), '{"deploy":1}');
  await assert.rejects(loadTerms(path.join(dir, 'terms.json')), /mảng chuỗi/);
  fs.writeFileSync(path.join(dir, 'terms.json'), '["deploy","commit"]');
  const terms = await loadTerms(path.join(dir, 'terms.json'));

  const items = [{ name: 'a', ref: 'deploy bản mới', hyp: 'đi plôi bản mới' }, { name: 'b', ref: 'xin chào', hyp: 'xin chào' }];
  const none = summarize({ items, terms: null });
  assert.equal(none.terms.rate, null);
  const s = summarize({ items, terms });
  assert.deepEqual([s.terms.hit, s.terms.expected], [0, 1]);
  assert.equal(s.tone.wer.errors, 2);
  assert.equal(s.tone.wer.ref_len, 5);
  const md = evalMarkdown({ ...s, model: 'm', set: dir, missing_ref: missingRef });
  assert.match(md, /40\.00% \(2\/5\)/);
  assert.match(md, /c\.wav/);
});
