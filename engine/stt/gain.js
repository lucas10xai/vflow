// Chế độ "Nói nhỏ" (whisper_mode, contract/engine-api.md mục "Giọng điệu và nói nhỏ"): tự khuếch
// đại âm lượng TRƯỚC khi đưa vào STT, hoàn toàn trong máy (chỉ xử lý PCM trong RAM).
// Chuẩn hoá đỉnh về khoảng -3 dBFS, tăng tối đa +24 dB; cổng nhiễu nhẹ (không cắt hẳn, chỉ giảm
// mềm các khung dưới ngưỡng) để im lặng/nhiễu nền không bị khuếch đại thành tiếng ồn nghe được.

const TARGET_PEAK_DBFS = -3;
const MAX_GAIN_DB = 24;
const NOISE_FLOOR_DBFS = -45;
/** Hệ số giảm tối thiểu cho khung dưới ngưỡng nhiễu (không bao giờ về 0 — "không cắt"). */
const MIN_GATE_FACTOR = 0.15;

const dbToLinear = (db) => Math.pow(10, db / 20);

const TARGET_PEAK = dbToLinear(TARGET_PEAK_DBFS);
const MAX_GAIN = dbToLinear(MAX_GAIN_DB);
const NOISE_FLOOR = dbToLinear(NOISE_FLOOR_DBFS);

/**
 * @param {Float32Array} samples @param {number} sampleRate
 * @param {{ frameMs?: number }} [opts]
 * @returns {Float32Array}
 */
export function applyAutoGain(samples, sampleRate, { frameMs = 30 } = {}) {
  if (samples.length === 0) return samples;

  let peak = 0;
  for (let i = 0; i < samples.length; i++) {
    const a = Math.abs(samples[i]);
    if (a > peak) peak = a;
  }
  if (peak <= 1e-9) return samples; // im lặng tuyệt đối: không có gì để khuếch đại

  const desiredGain = TARGET_PEAK / peak;
  const gain = desiredGain > 1 ? Math.min(desiredGain, MAX_GAIN) : 1;

  const frame = Math.max(1, Math.round(sampleRate * (frameMs / 1000)));
  const out = new Float32Array(samples.length);
  for (let s = 0; s < samples.length; s += frame) {
    const e = Math.min(samples.length, s + frame);
    let sum = 0;
    for (let i = s; i < e; i++) sum += samples[i] * samples[i];
    const rms = Math.sqrt(sum / (e - s));
    // Cổng mềm: khung dưới ngưỡng nhiễu bị giảm theo tỉ lệ rms/ngưỡng (không bao giờ dưới
    // MIN_GATE_FACTOR) — khung có tiếng nói rõ (rms >= ngưỡng) đi qua nguyên vẹn.
    const gate = rms >= NOISE_FLOOR ? 1 : Math.max(MIN_GATE_FACTOR, rms / NOISE_FLOOR);
    for (let i = s; i < e; i++) out[i] = Math.max(-1, Math.min(1, samples[i] * gate * gain));
  }
  return out;
}
