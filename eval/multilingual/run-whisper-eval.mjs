/**
 * Đo Whisper sherpa-onnx trên bộ WAV tổng hợp tạm thời.
 * Không ghi âm thanh hay model vào repo; đối số --set/--model-dir phải ở ngoài repo.
 */
import fs from 'node:fs/promises';
import path from 'node:path';
import { performance } from 'node:perf_hooks';
import { createRequire } from 'node:module';
import { scoreBoth, aggregate, percentile } from '../metrics.js';

const require = createRequire(import.meta.url);
const sherpa = require('sherpa-onnx-node');

function arg(name) {
  const i = process.argv.indexOf(name);
  if (i < 0 || !process.argv[i + 1]) throw new Error(`Thiếu ${name}`);
  return process.argv[i + 1];
}

async function readWav(file) {
  const b = await fs.readFile(file);
  if (b.toString('ascii', 0, 4) !== 'RIFF' || b.toString('ascii', 8, 12) !== 'WAVE') throw new Error(`WAV không hợp lệ: ${file}`);
  let p = 12; let channels; let rate; let bits; let data;
  while (p + 8 <= b.length) {
    const tag = b.toString('ascii', p, p + 4); const n = b.readUInt32LE(p + 4); p += 8;
    if (tag === 'fmt ') { channels = b.readUInt16LE(p + 2); rate = b.readUInt32LE(p + 4); bits = b.readUInt16LE(p + 14); }
    if (tag === 'data') data = b.subarray(p, p + n);
    p += n + (n % 2);
  }
  if (channels !== 1 || rate !== 16000 || bits !== 16 || !data) throw new Error(`Cần WAV PCM 16-bit mono 16 kHz: ${file}`);
  const a = new Float32Array(data.length / 2);
  for (let i = 0; i < a.length; i++) a[i] = data.readInt16LE(i * 2) / 32768;
  return a;
}

function median(a) { return percentile(a, 0.5); }
function p95(a) { return percentile(a, 0.95); }

const set = arg('--set');
const modelDir = arg('--model-dir');
const language = arg('--language');
const model = arg('--model');
const encoder = path.join(modelDir, `${model}-encoder.int8.onnx`);
const decoder = path.join(modelDir, `${model}-decoder.int8.onnx`);
const tokens = path.join(modelDir, `${model}-tokens.txt`);
await Promise.all([encoder, decoder, tokens].map((f) => fs.access(f)));
const t0 = performance.now();
const recognizer = await sherpa.OfflineRecognizer.createAsync({
  featConfig: { sampleRate: 16000, featureDim: 80 },
  modelConfig: { whisper: { encoder, decoder, language, task: 'transcribe', tailPaddings: -1 }, tokens, numThreads: 2, provider: 'cpu', debug: 0 },
  decodingMethod: 'greedy_search',
});
const loadMs = performance.now() - t0;
const rssAfterLoad = process.memoryUsage.rss();
const files = (await fs.readdir(set)).filter((x) => x.endsWith('.wav')).sort();
const byGroup = new Map();
let peakRss = rssAfterLoad;
for (const wav of files) {
  const base = wav.slice(0, -4); const ref = (await fs.readFile(path.join(set, `${base}.txt`), 'utf8')).trim();
  const pcm = await readWav(path.join(set, wav));
  const s = recognizer.createStream(); s.acceptWaveform({ samples: pcm, sampleRate: 16000 });
  const start = performance.now(); await recognizer.decodeAsync(s); const ms = performance.now() - start;
  peakRss = Math.max(peakRss, process.memoryUsage.rss());
  const result = recognizer.getResult(s); const group = base.split('-')[0];
  if (!byGroup.has(group)) byGroup.set(group, []);
  byGroup.get(group).push({ name: base, ref, hyp: String(result.text ?? '').trim(), audio_ms: pcm.length / 16, stt_ms: ms, scores: scoreBoth(ref, String(result.text ?? '').trim()) });
}
const groups = {};
for (const [group, items] of byGroup) {
  const tone = aggregate(items.map((x) => x.scores.tone)); const noTone = aggregate(items.map((x) => x.scores.no_tone));
  const lat = items.map((x) => x.stt_ms); const rtf = items.map((x) => x.stt_ms / x.audio_ms);
  groups[group] = { count: items.length, wer: tone.wer.rate, cer: tone.cer.rate, wer_no_tone: noTone.wer.rate, cer_no_tone: noTone.cer.rate, latency_ms: { median: median(lat), p95: p95(lat) }, rtf: { median: median(rtf), p95: p95(rtf) }, items };
}
console.log(JSON.stringify({ model, language, load_ms: loadMs, rss_after_load_mb: rssAfterLoad / 1048576, peak_rss_sampled_mb: peakRss / 1048576, groups }, null, 2));
