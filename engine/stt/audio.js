/**
 * Giải mã âm thanh đầu vào (WAV PCM16 / L16 thô) về Float32 mono 16 kHz, hoàn toàn trong RAM.
 * Không có hàm nào ở đây ghi xuống đĩa.
 */
import { badAudio } from './errors.js';

export const TARGET_RATE = 16000;
const MIN_RATE = 8000;
const MAX_RATE = 192000;
const MAX_CHANNELS = 8;

/**
 * @typedef {{ samples: Float32Array, sampleRate: number }} Waveform  mono, giá trị [-1, 1)
 */

/**
 * @param {Uint8Array} bytes
 * @param {number} offset
 * @param {number} byteLength số byte (chẵn)
 * @param {number} channels
 * @returns {Float32Array} mono
 */
function pcm16leToMono(bytes, offset, byteLength, channels) {
  const view = new DataView(bytes.buffer, bytes.byteOffset + offset, byteLength);
  const frames = Math.floor(byteLength / (2 * channels));
  const out = new Float32Array(frames);
  if (channels === 1) {
    for (let i = 0; i < frames; i++) out[i] = view.getInt16(i * 2, true) / 32768;
    return out;
  }
  for (let i = 0; i < frames; i++) {
    let sum = 0;
    const base = i * 2 * channels;
    for (let c = 0; c < channels; c++) sum += view.getInt16(base + c * 2, true);
    out[i] = sum / channels / 32768;
  }
  return out;
}

/** @param {number} rate @param {number} channels */
function checkFormat(rate, channels) {
  if (!Number.isInteger(rate) || rate < MIN_RATE || rate > MAX_RATE) {
    throw badAudio(`Tần số lấy mẫu không hỗ trợ: ${rate} Hz (cần ${MIN_RATE}–${MAX_RATE} Hz).`);
  }
  if (!Number.isInteger(channels) || channels < 1 || channels > MAX_CHANNELS) {
    throw badAudio(`Số kênh không hỗ trợ: ${channels}.`);
  }
}

/**
 * Đọc WAV RIFF PCM 16-bit (WAVE_FORMAT_PCM hoặc EXTENSIBLE với subformat PCM), mọi tần số 8–192 kHz,
 * 1–8 kênh; trộn về mono. Định dạng khác (float, 8/24/32-bit, nén) ⇒ `bad_audio`.
 * @param {Uint8Array} bytes
 * @returns {Waveform & { channels: number }}
 */
export function parseWav(bytes) {
  if (!(bytes instanceof Uint8Array)) throw badAudio('Dữ liệu âm thanh không hợp lệ.');
  const ascii = (o) => String.fromCharCode(bytes[o], bytes[o + 1], bytes[o + 2], bytes[o + 3]);
  if (bytes.length < 12 || ascii(0) !== 'RIFF' || ascii(8) !== 'WAVE') {
    throw badAudio('Không phải tệp WAV (thiếu tiêu đề RIFF/WAVE).');
  }
  const view = new DataView(bytes.buffer, bytes.byteOffset, bytes.byteLength);
  let pos = 12;
  /** @type {{format:number, channels:number, rate:number, bits:number, blockAlign:number}|null} */
  let fmt = null;
  while (pos + 8 <= bytes.length) {
    const id = ascii(pos);
    const size = view.getUint32(pos + 4, true);
    const body = pos + 8;
    if (id === 'fmt ') {
      if (size < 16 || body + 16 > bytes.length) throw badAudio('Khối fmt của WAV bị hỏng.');
      let format = view.getUint16(body, true);
      const channels = view.getUint16(body + 2, true);
      const rate = view.getUint32(body + 4, true);
      const blockAlign = view.getUint16(body + 12, true);
      const bits = view.getUint16(body + 14, true);
      if (format === 0xfffe) {
        // WAVE_FORMAT_EXTENSIBLE: 2 byte đầu của GUID subformat là mã định dạng thật.
        if (size < 40 || body + 26 > bytes.length) throw badAudio('Khối fmt EXTENSIBLE của WAV bị hỏng.');
        format = view.getUint16(body + 24, true);
      }
      fmt = { format, channels, rate, bits, blockAlign };
    } else if (id === 'data') {
      if (!fmt) throw badAudio('WAV có khối data trước khối fmt.');
      if (fmt.format !== 1) throw badAudio(`WAV không phải PCM (mã định dạng ${fmt.format}); chỉ nhận PCM 16-bit.`);
      if (fmt.bits !== 16) throw badAudio(`WAV ${fmt.bits}-bit không hỗ trợ; chỉ nhận PCM 16-bit.`);
      checkFormat(fmt.rate, fmt.channels);
      if (fmt.blockAlign !== 2 * fmt.channels) throw badAudio('WAV có blockAlign không khớp số kênh.');
      // Kích thước khai báo có thể lớn hơn thực tế (WAV ghi dạng luồng): lấy phần thực có.
      const available = Math.min(size, bytes.length - body);
      const usable = available - (available % fmt.blockAlign);
      return {
        samples: pcm16leToMono(bytes, body, usable, fmt.channels),
        sampleRate: fmt.rate,
        channels: fmt.channels,
      };
    }
    pos = body + size + (size % 2); // khối lẻ có 1 byte đệm
  }
  throw badAudio(fmt ? 'WAV không có khối data.' : 'WAV không có khối fmt.');
}

/**
 * Đọc PCM thô int16 little-endian (theo contract, dù RFC 2586 là big-endian).
 * @param {Uint8Array} bytes
 * @param {number} rate
 * @param {number} channels
 * @returns {Waveform}
 */
export function parseL16(bytes, rate, channels) {
  checkFormat(rate, channels);
  if (bytes.length % (2 * channels) !== 0) {
    throw badAudio('Độ dài PCM thô không chia hết cho kích thước khung (int16 × số kênh).');
  }
  return { samples: pcm16leToMono(bytes, 0, bytes.length, channels), sampleRate: rate };
}

/**
 * Phân tích Content-Type và giải mã thân yêu cầu.
 * @param {Uint8Array} bytes
 * @param {string|undefined} contentType
 * @returns {Waveform}
 */
export function decodeAudio(bytes, contentType) {
  const [mimeRaw, ...params] = String(contentType ?? '').split(';');
  const mime = mimeRaw.trim().toLowerCase();
  if (mime === 'audio/wav' || mime === 'audio/x-wav' || mime === 'audio/wave') return parseWav(bytes);
  if (mime === 'audio/l16') {
    /** @type {Record<string,string>} */
    const p = {};
    for (const kv of params) {
      const i = kv.indexOf('=');
      if (i > 0) p[kv.slice(0, i).trim().toLowerCase()] = kv.slice(i + 1).trim();
    }
    const rate = p.rate === undefined ? TARGET_RATE : Number(p.rate);
    const channels = p.channels === undefined ? 1 : Number(p.channels);
    return parseL16(bytes, rate, channels);
  }
  throw badAudio(`Content-Type không hỗ trợ: "${mime || '(trống)'}". Dùng audio/wav hoặc audio/L16; rate=16000; channels=1.`);
}

/**
 * Lấy mẫu lại bằng sinc có cửa sổ Blackman, có lọc chống chồng phổ khi hạ tần số.
 * Độ lệch so với tín hiệu lý tưởng được kiểm trong audio.test.js.
 * @param {Float32Array} input
 * @param {number} fromRate
 * @param {number} toRate
 * @param {{ zeroCrossings?: number, rolloff?: number }} [opts]
 * @returns {Float32Array}
 */
export function resample(input, fromRate, toRate, opts = {}) {
  if (!(fromRate > 0) || !(toRate > 0)) throw new RangeError('tần số lấy mẫu phải dương');
  if (fromRate === toRate) return Float32Array.from(input);
  const n = input.length;
  const ratio = toRate / fromRate;
  const outLen = Math.round(n * ratio);
  const out = new Float32Array(outLen);
  if (n === 0) return out;
  const zc = opts.zeroCrossings ?? 16;
  const rolloff = opts.rolloff ?? 0.94;
  // Tần số cắt (theo chu kỳ/mẫu đầu vào × 2): 1 = Nyquist đầu vào.
  const cutoff = Math.min(1, ratio) * rolloff;
  const half = zc / cutoff; // nửa bề rộng nhân tính bằng mẫu đầu vào
  for (let j = 0; j < outLen; j++) {
    const t = j / ratio; // vị trí trên trục đầu vào
    const lo = Math.max(0, Math.ceil(t - half));
    const hi = Math.min(n - 1, Math.floor(t + half));
    let acc = 0;
    let wsum = 0;
    for (let i = lo; i <= hi; i++) {
      const x = i - t;
      const u = x / half; // [-1, 1]
      const win = 0.42 + 0.5 * Math.cos(Math.PI * u) + 0.08 * Math.cos(2 * Math.PI * u);
      const arg = Math.PI * cutoff * x;
      const sinc = arg === 0 ? 1 : Math.sin(arg) / arg;
      const w = sinc * win;
      acc += input[i] * w;
      wsum += w;
    }
    // Chuẩn hoá theo tổng trọng số: giữ đúng mức DC kể cả ở hai đầu tín hiệu.
    out[j] = wsum === 0 ? 0 : acc / wsum;
  }
  return out;
}

/**
 * @param {Waveform} wave
 * @returns {Float32Array} mono 16 kHz
 */
export function toTargetRate(wave) {
  return resample(wave.samples, wave.sampleRate, TARGET_RATE);
}

/**
 * Chuẩn hoá PCM từ provider: Int16Array hoặc Float32Array → Float32Array.
 * @param {Int16Array|Float32Array} pcm
 * @returns {Float32Array}
 */
export function toFloat32(pcm) {
  if (pcm instanceof Float32Array) return pcm;
  if (pcm instanceof Int16Array) {
    const out = new Float32Array(pcm.length);
    for (let i = 0; i < pcm.length; i++) out[i] = pcm[i] / 32768;
    return out;
  }
  throw badAudio('pcm phải là Int16Array hoặc Float32Array.');
}

/**
 * Float32 [-1,1] → Int16Array (dùng khi gửi L16 cho STT từ xa).
 * @param {Float32Array} samples
 */
export function toInt16(samples) {
  const out = new Int16Array(samples.length);
  for (let i = 0; i < samples.length; i++) {
    const v = Math.max(-1, Math.min(1, samples[i]));
    out[i] = v < 0 ? Math.round(v * 32768) : Math.round(v * 32767);
  }
  return out;
}

/** Ngưỡng im lặng: khung 30 ms to nhất vẫn dưới -50 dBFS RMS. */
export const SILENCE_DBFS = -50;

/**
 * Im lặng nếu rỗng hoặc mọi khung 30 ms đều có RMS dưới ngưỡng.
 * @param {Float32Array} samples
 * @param {number} sampleRate
 * @param {number} [thresholdDbfs]
 */
export function isSilence(samples, sampleRate, thresholdDbfs = SILENCE_DBFS) {
  if (samples.length === 0) return true;
  const frame = Math.max(1, Math.round(sampleRate * 0.03));
  const thr = Math.pow(10, thresholdDbfs / 20);
  const thr2 = thr * thr;
  for (let s = 0; s < samples.length; s += frame) {
    const e = Math.min(samples.length, s + frame);
    let sum = 0;
    for (let i = s; i < e; i++) sum += samples[i] * samples[i];
    if (sum / (e - s) >= thr2) return false;
  }
  return true;
}

/** @param {number} samples @param {number} rate */
export const durationMs = (samples, rate) => Math.round((samples / rate) * 1000);

/**
 * Tạo WAV PCM16 trong RAM (dùng cho test và bench; không ghi đĩa).
 * @param {Float32Array|Int16Array} samples mono hoặc xen kẽ theo `channels`
 * @param {number} sampleRate
 * @param {number} [channels]
 * @returns {Uint8Array}
 */
export function encodeWav(samples, sampleRate, channels = 1) {
  const pcm = samples instanceof Int16Array ? samples : toInt16(samples);
  const dataBytes = pcm.length * 2;
  const buf = new Uint8Array(44 + dataBytes);
  const v = new DataView(buf.buffer);
  const w = (o, s) => { for (let i = 0; i < 4; i++) buf[o + i] = s.charCodeAt(i); };
  w(0, 'RIFF'); v.setUint32(4, 36 + dataBytes, true); w(8, 'WAVE');
  w(12, 'fmt '); v.setUint32(16, 16, true); v.setUint16(20, 1, true); v.setUint16(22, channels, true);
  v.setUint32(24, sampleRate, true); v.setUint32(28, sampleRate * channels * 2, true);
  v.setUint16(32, channels * 2, true); v.setUint16(34, 16, true);
  w(36, 'data'); v.setUint32(40, dataBytes, true);
  for (let i = 0; i < pcm.length; i++) v.setInt16(44 + i * 2, pcm[i], true);
  return buf;
}
