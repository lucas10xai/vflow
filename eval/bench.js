/**
 * Đo hiệu năng một model STT cục bộ: thời gian tải, RTF và độ trễ theo câu 3/5/15 s
 * (ghép/cắt từ wav mẫu), RSS đỉnh của tiến trình (lấy mẫu đều trong worker riêng,
 * nên vẫn đo được khi luồng chính đang bận giải mã).
 */
import { Worker } from 'node:worker_threads';
import { performance } from 'node:perf_hooks';
import os from 'node:os';
import { percentile } from './metrics.js';
import { TARGET_RATE } from '../engine/stt/audio.js';

/**
 * Lấy mẫu RSS mỗi `intervalMs` trong một worker; RSS là của cả tiến trình.
 * @param {number} intervalMs
 */
export function startRssSampler(intervalMs = 20) {
  const sab = new SharedArrayBuffer(16);
  const cells = new Float64Array(sab); // [0] = RSS đỉnh (byte), [1] = số mẫu
  cells[0] = process.memoryUsage.rss();
  const worker = new Worker(
    `const { workerData } = require('node:worker_threads');
     const cells = new Float64Array(workerData.sab);
     setInterval(() => {
       const r = process.memoryUsage.rss();
       if (r > cells[0]) cells[0] = r;
       cells[1]++;
     }, workerData.intervalMs);`,
    { eval: true, workerData: { sab, intervalMs } },
  );
  worker.unref();
  // Worker cần vài trăm ms để khởi động trên máy chậm: đợi mẫu đầu tiên rồi mới đo.
  const ready = new Promise((resolve, reject) => {
    worker.once('error', reject);
    const poll = setInterval(() => { if (cells[1] > 0) { clearInterval(poll); resolve(undefined); } }, 5);
  });
  return {
    ready,
    peak: () => Math.max(cells[0], process.memoryUsage.rss()),
    samples: () => cells[1],
    stop: () => worker.terminate(),
  };
}

/**
 * Tạo đoạn dài `seconds` từ nguồn (lặp lại nếu nguồn ngắn hơn), bắt đầu ở `offset`.
 * @param {Float32Array} src 16 kHz mono
 * @param {number} seconds
 * @param {number} offset
 */
export function makeClip(src, seconds, offset = 0) {
  if (src.length === 0) throw new Error('nguồn âm thanh rỗng');
  const n = Math.round(seconds * TARGET_RATE);
  const out = new Float32Array(n);
  let pos = offset % src.length;
  for (let i = 0; i < n; i++) {
    out[i] = src[pos];
    pos = pos + 1 === src.length ? 0 : pos + 1;
  }
  return out;
}

const MB = 1024 * 1024;
const round = (x, d = 3) => (x === null ? null : Math.round(x * 10 ** d) / 10 ** d);

/**
 * @param {{
 *   provider: { loadModel: (id: string) => Promise<any>, transcribe: (x: {pcm: Float32Array, sampleRate: number}) => Promise<{text:string}> },
 *   modelId: string,
 *   source: Float32Array,           16 kHz mono (ghép từ các wav mẫu)
 *   lengths?: number[], runs?: number, intervalMs?: number,
 *   log?: (msg: string) => void,
 * }} opts
 */
export async function runBench({ provider, modelId, source, lengths = [3, 5, 15], runs = 10, intervalMs = 20, log = () => {} }) {
  if (!Number.isInteger(runs) || runs < 1) throw new RangeError('runs phải là số nguyên ≥ 1');
  const sampler = startRssSampler(intervalMs);
  try {
    await sampler.ready;
    const rssStart = process.memoryUsage.rss();
    const t0 = performance.now();
    await provider.loadModel(modelId);
    const loadMs = performance.now() - t0;
    const rssAfterLoad = process.memoryUsage.rss();
    log(`Tải model: ${loadMs.toFixed(0)} ms`);

    const results = [];
    for (const sec of lengths) {
      // 1 lần khởi động, không tính.
      await provider.transcribe({ pcm: makeClip(source, sec, 0), sampleRate: TARGET_RATE });
      const lat = [];
      for (let i = 0; i < runs; i++) {
        const clip = makeClip(source, sec, (i * 7919 * 16) % source.length);
        const s = performance.now();
        await provider.transcribe({ pcm: clip, sampleRate: TARGET_RATE });
        lat.push(performance.now() - s);
      }
      const rtf = lat.map((ms) => ms / (sec * 1000));
      results.push({
        seconds: sec, runs,
        latency_ms: { median: round(percentile(lat, 0.5), 1), p95: round(percentile(lat, 0.95), 1), max: round(Math.max(...lat), 1) },
        rtf: { median: round(percentile(rtf, 0.5)), p95: round(percentile(rtf, 0.95)) },
      });
      log(`  ${sec} s × ${runs}: trung vị ${percentile(lat, 0.5)?.toFixed(0)} ms`);
    }
    const ru = process.resourceUsage();
    return {
      model: modelId,
      platform: `${process.platform}-${process.arch}`,
      cpu: os.cpus()[0]?.model ?? 'không xác định',
      node: process.version,
      source_seconds: round(source.length / TARGET_RATE, 2),
      load_ms: round(loadMs, 0),
      rss_mb: {
        start: round(rssStart / MB, 1),
        after_load: round(rssAfterLoad / MB, 1),
        peak_sampled: round(sampler.peak() / MB, 1),
        // maxRSS của hệ điều hành (KB trên mọi nền tảng theo tài liệu Node).
        peak_os: round(ru.maxRSS / 1024, 1),
      },
      rss_samples: sampler.samples(),
      rss_interval_ms: intervalMs,
      latency_note: 'độ trễ = từ lúc có đủ âm thanh (đoạn đã ở RAM) tới lúc có chữ; RTF = độ trễ / độ dài đoạn',
      results,
    };
  } finally {
    await sampler.stop();
  }
}

/** @param {Awaited<ReturnType<typeof runBench>>} r */
export function benchMarkdown(r) {
  const lines = [
    `### Bench \`${r.model}\` — ${r.platform}, ${r.cpu}, Node ${r.node}`,
    '',
    `- Thời gian tải model: **${r.load_ms} ms**`,
    `- RSS: lúc đầu ${r.rss_mb.start} MB · sau tải ${r.rss_mb.after_load} MB · **đỉnh ${r.rss_mb.peak_sampled} MB** (lấy mẫu ${r.rss_interval_ms} ms, ${r.rss_samples} mẫu) · đỉnh theo HĐH ${r.rss_mb.peak_os} MB`,
    `- Nguồn: ${r.source_seconds} s âm thanh mẫu, ghép/lặp để tạo đoạn`,
    '',
    '| Độ dài | Số lần | Độ trễ trung vị (ms) | Độ trễ p95 (ms) | RTF trung vị | RTF p95 |',
    '|---:|---:|---:|---:|---:|---:|',
    ...r.results.map((x) => `| ${x.seconds} s | ${x.runs} | ${x.latency_ms.median} | ${x.latency_ms.p95} | ${x.rtf.median} | ${x.rtf.p95} |`),
    '',
    `_${r.latency_note}_`,
  ];
  return lines.join('\n');
}
