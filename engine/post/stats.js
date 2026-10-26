// Thống kê dictation: CHỈ bộ đếm (không văn bản, không âm thanh). Lưu $VFLOW_HOME/stats.json
// (0600), ghi nguyên tử tmp+rename (contract/engine-api.md mục Thống kê).
//
// Lần đầu chạy (chưa có stats.json) backfill từ history.jsonl của client (cùng cách đếm); sau đó
// stats.json là nguồn sự thật duy nhất — history bị xoá/tắt không ảnh hưởng gì tới thống kê đã có.
import { readFileSync, existsSync } from 'node:fs';
import { writePrivateJson } from './dictionary.js';

export const STATS_VERSION = 1;

export class StatsError extends Error {
  /** @param {string} message */
  constructor(message) {
    super(message);
    this.code = 'internal';
  }
}

/**
 * "từ": token cách bởi khoảng trắng có ít nhất một chữ cái/chữ số Unicode (tiếng Việt: mỗi âm
 * tiết là một từ, vì âm tiết cách nhau bằng khoảng trắng trong chữ Quốc ngữ).
 * @param {unknown} text
 */
export function countWords(text) {
  if (typeof text !== 'string') return 0;
  const t = text.trim();
  if (t === '') return 0;
  let n = 0;
  for (const w of t.split(/\s+/u)) if (/[\p{L}\p{N}]/u.test(w)) n++;
  return n;
}

/** "YYYY-MM-DD" từ các thành phần lịch (năm/tháng/ngày) LOCAL của `d`. */
export function dayKey(d) {
  const y = d.getFullYear();
  const m = String(d.getMonth() + 1).padStart(2, '0');
  const day = String(d.getDate()).padStart(2, '0');
  return `${y}-${m}-${day}`;
}

/**
 * "Chỉ số ngày" (số ngày từ mốc UTC) từ khoá "YYYY-MM-DD" — dùng CHỈ để so sánh/khoảng cách lịch,
 * không gắn với múi giờ thật nào (tránh lỗi DST/nhuận khi cộng trừ bằng epoch giây/ms).
 * @param {string} key
 */
function dateIndex(key) {
  const [y, m, d] = key.split('-').map(Number);
  return Math.round(Date.UTC(y, m - 1, d) / 86400000);
}

/** @param {number} idx */
function keyFromIndex(idx) {
  const dt = new Date(idx * 86400000);
  return `${dt.getUTCFullYear()}-${String(dt.getUTCMonth() + 1).padStart(2, '0')}-${String(dt.getUTCDate()).padStart(2, '0')}`;
}

/** 0=Chủ nhật..6=Thứ Bảy, theo lịch thuần (không múi giờ thật). @param {number} idx */
function dowFromIndex(idx) {
  return new Date(idx * 86400000).getUTCDay();
}

/** @param {unknown} v */
function num(v) {
  return Number.isFinite(v) && v >= 0 ? v : 0;
}

/** Làm sạch `days` đọc từ tệp: bỏ khoá không phải object hợp lệ, ép số âm/NaN về 0. */
function sanitizeDays(raw) {
  /** @type {Record<string, {words:number, audio_ms:number, count:number, apps:Record<string,{words:number,count:number}>}>} */
  const out = {};
  for (const [key, v] of Object.entries(raw)) {
    if (!/^\d{4}-\d{2}-\d{2}$/.test(key) || v === null || typeof v !== 'object') continue;
    const apps = {};
    if (v.apps && typeof v.apps === 'object') {
      for (const [app, a] of Object.entries(v.apps)) {
        if (a === null || typeof a !== 'object') continue;
        apps[app] = { words: num(a.words), count: num(a.count) };
      }
    }
    out[key] = { words: num(v.words), audio_ms: num(v.audio_ms), count: num(v.count), apps };
  }
  return out;
}

/**
 * Một dòng history.jsonl (định dạng client/Sources/VFlowCore/History.swift) hợp lệ để backfill,
 * hay bị bỏ (hỏng/thiếu trường ⇒ corrupt; Command Mode/rỗng ⇒ hợp lệ nhưng không tính vào thống kê).
 * @param {string} line
 */
function parseHistoryLine(line) {
  let obj;
  try {
    obj = JSON.parse(line);
  } catch {
    return { ok: false };
  }
  if (!obj || typeof obj !== 'object' || Array.isArray(obj)) return { ok: false };
  const { at, mode, text } = obj;
  if (typeof at !== 'string' || Number.isNaN(Date.parse(at))) return { ok: false };
  if (typeof mode !== 'string' || mode === '') return { ok: false };
  if (typeof text !== 'string') return { ok: false };
  // Command Mode ghi mode "command:edit"/"command:draft" (xem AppController.swift) — không tính.
  if (mode.startsWith('command')) return { ok: true, skip: true };
  if (text.trim() === '') return { ok: true, skip: true };
  const audioMs = Number.isInteger(obj.audio_ms) ? num(obj.audio_ms) : 0;
  const app = typeof obj.app === 'string' && obj.app !== '' ? obj.app : 'unknown';
  return { ok: true, skip: false, at: new Date(at), text, audioMs, app };
}

/** @param {string|undefined} historyPath */
function backfillFromHistory(historyPath) {
  /** @type {{at: Date, text: string, audioMs: number, app: string}[]} */
  const entries = [];
  let corrupt = 0;
  if (!historyPath || !existsSync(historyPath)) return { entries, corrupt };
  let raw;
  try {
    raw = readFileSync(historyPath, 'utf8');
  } catch {
    return { entries, corrupt };
  }
  for (const rawLine of raw.split('\n')) {
    const line = rawLine.trim();
    if (line === '') continue;
    const r = parseHistoryLine(line);
    if (!r.ok) {
      corrupt++;
      continue;
    }
    if (r.skip) continue;
    entries.push(r);
  }
  return { entries, corrupt };
}

/**
 * @param {{ path: string, historyPath?: string, now?: () => Date, log?: (e: object) => void }} opts
 */
export function createStatsStore({ path, historyPath, now = () => new Date(), log = () => {} }) {
  if (typeof path !== 'string' || path === '') throw new TypeError('cần path');

  /** @type {{ version: number, backfilled: boolean, days: Record<string, any> }} */
  let data;
  if (existsSync(path)) {
    let raw;
    try {
      raw = readFileSync(path, 'utf8');
    } catch (err) {
      throw new StatsError(`không đọc được tệp thống kê (${/** @type {any} */ (err).code ?? 'lỗi'})`);
    }
    let json;
    try {
      json = JSON.parse(raw);
    } catch {
      throw new StatsError('tệp thống kê hỏng (JSON không hợp lệ)');
    }
    if (!json || typeof json !== 'object' || Array.isArray(json) || typeof json.days !== 'object' || json.days === null) {
      throw new StatsError('tệp thống kê hỏng (sai cấu trúc)');
    }
    data = { version: STATS_VERSION, backfilled: json.backfilled === true, days: sanitizeDays(json.days) };
  } else {
    data = { version: STATS_VERSION, backfilled: false, days: {} };
  }

  function addEntry(at, text, audioMs, app) {
    const key = dayKey(at);
    const day = data.days[key] ?? (data.days[key] = { words: 0, audio_ms: 0, count: 0, apps: {} });
    const words = countWords(text);
    day.words += words;
    day.audio_ms += num(audioMs);
    day.count += 1;
    const a = day.apps[app] ?? (day.apps[app] = { words: 0, count: 0 });
    a.words += words;
    a.count += 1;
  }

  function persist() {
    try {
      writePrivateJson(path, data);
    } catch (err) {
      log({ event: 'stats_save_failed', code: /** @type {any} */ (err)?.code ?? 'unknown' });
    }
  }

  if (!data.backfilled) {
    const bf = backfillFromHistory(historyPath);
    if (bf.corrupt > 0) log({ event: 'stats_backfill_corrupt_lines', count: bf.corrupt });
    for (const e of bf.entries) addEntry(e.at, e.text, e.audioMs, e.app);
    data.backfilled = true;
    persist();
  }

  return {
    /**
     * Ghi nhận một lần dictation THÀNH CÔNG. Không bao giờ ném lỗi (dictation vẫn phải dùng được
     * dù ghi thống kê thất bại) — lỗi chỉ log.
     * @param {{ text: string, audioMs?: number, app?: string|null }} args
     */
    record({ text, audioMs = 0, app }) {
      try {
        addEntry(now(), text, audioMs, app || 'unknown');
        persist();
      } catch (err) {
        log({ event: 'stats_record_failed', code: /** @type {any} */ (err)?.code ?? 'unknown' });
      }
    },

    /**
     * @param {{ weeks?: number }} [args]
     */
    summary({ weeks = 16 } = {}) {
      const todayKey = dayKey(now());
      const todayIdx = dateIndex(todayKey);
      const mondayIdx = todayIdx - ((dowFromIndex(todayIdx) + 6) % 7);
      const windowStartIdx = mondayIdx - (weeks - 1) * 7;
      const windowEndIdx = Math.min(mondayIdx + 6, todayIdx);

      const days = [];
      for (let idx = windowStartIdx; idx <= windowEndIdx; idx++) {
        const key = keyFromIndex(idx);
        const d = data.days[key];
        days.push({ date: key, words: d?.words ?? 0, count: d?.count ?? 0, audio_ms: d?.audio_ms ?? 0 });
      }

      const sortedKeys = Object.keys(data.days).sort();
      const since = sortedKeys.length > 0 ? sortedKeys[0] : null;
      let total_words = 0;
      let total_count = 0;
      let total_audio_ms = 0;
      /** @type {Map<string, {words:number, count:number}>} */
      const appTotals = new Map();
      for (const k of sortedKeys) {
        const d = data.days[k];
        total_words += d.words;
        total_count += d.count;
        total_audio_ms += d.audio_ms;
        for (const [app, a] of Object.entries(d.apps ?? {})) {
          const t = appTotals.get(app) ?? { words: 0, count: 0 };
          t.words += a.words;
          t.count += a.count;
          appTotals.set(app, t);
        }
      }
      const avg_wpm = total_audio_ms >= 60000 ? Math.round(total_words / (total_audio_ms / 60000)) : null;

      const hasWords = (idx) => (data.days[keyFromIndex(idx)]?.words ?? 0) > 0;
      let current_streak = 0;
      let startIdx = null;
      if (hasWords(todayIdx)) startIdx = todayIdx;
      else if (hasWords(todayIdx - 1)) startIdx = todayIdx - 1;
      if (startIdx !== null) {
        let i = startIdx;
        while (hasWords(i)) {
          current_streak++;
          i--;
        }
      }

      const activeIdx = sortedKeys.filter((k) => (data.days[k].words ?? 0) > 0).map(dateIndex).sort((a, b) => a - b);
      let best_streak = 0;
      let run = 0;
      let prev = null;
      for (const idx of activeIdx) {
        run = prev !== null && idx === prev + 1 ? run + 1 : 1;
        if (run > best_streak) best_streak = run;
        prev = idx;
      }

      const top_apps = [...appTotals.entries()]
        .map(([app, t]) => ({ app, words: t.words, count: t.count }))
        .sort((a, b) => b.words - a.words || b.count - a.count || a.app.localeCompare(b.app))
        .slice(0, 10);

      return {
        since, weeks, week_start: 'monday', today: todayKey,
        total_words, total_count, total_audio_ms, avg_wpm,
        current_streak, best_streak, days, top_apps,
      };
    },

    /** Xoá toàn bộ; đặt backfilled:true để KHÔNG tự backfill lại từ history. */
    clear() {
      data = { version: STATS_VERSION, backfilled: true, days: {} };
      persist();
      return { ok: true };
    },

    /** Số ngày thực sự có dữ liệu (dùng cho GET /v1/diagnostics counts.stats_days). */
    daysCount() {
      return Object.keys(data.days).length;
    },

    /** Bản sao `{ backfilled, days }` để xuất (GET /v1/export, item 2). KHÔNG chứa văn bản/âm thanh. */
    exportDays() {
      return { backfilled: data.backfilled, days: structuredClone(data.days) };
    },

    /**
     * Nhập `days` (đã kiểm nghiêm ở caller — engine/post/exportimport.js): `merge` cộng dồn bộ đếm
     * theo ngày, `replace` thay toàn bộ `days` bằng gói nhập.
     * @param {Record<string, any>} days @param {'merge'|'replace'} mode
     */
    importDays(days, mode) {
      if (mode === 'replace') {
        data = { version: STATS_VERSION, backfilled: true, days: sanitizeDays(days) };
      } else {
        const incoming = sanitizeDays(days);
        for (const [key, day] of Object.entries(incoming)) {
          const base = data.days[key] ?? { words: 0, audio_ms: 0, count: 0, apps: {} };
          const merged = { words: base.words + day.words, audio_ms: base.audio_ms + day.audio_ms, count: base.count + day.count, apps: { ...base.apps } };
          for (const [app, a] of Object.entries(day.apps)) {
            const baseApp = merged.apps[app] ?? { words: 0, count: 0 };
            merged.apps[app] = { words: baseApp.words + a.words, count: baseApp.count + a.count };
          }
          data.days[key] = merged;
        }
      }
      persist();
      return Object.keys(days).length;
    },
  };
}
