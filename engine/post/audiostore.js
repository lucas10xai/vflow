/**
 * A6 (lịch sử âm thanh tuỳ chọn): kho WAV 16 kHz mono 16-bit tại `$VFLOW_HOME/audio/<id>.wav`.
 *
 * SỬA HỢP ĐỒNG (coordinator, 2026-10-26): lịch sử dictation (history.jsonl) là của CLIENT
 * (HistoryStore riêng), engine KHÔNG sở hữu và KHÔNG có GET /v1/history. Engine chỉ giữ MỘT kho âm
 * thanh độc lập, đánh chỉ mục bằng chính `id` dictation (trường `id`/`audio_id` trong phản hồi
 * /v1/transcribe) — client tự lưu `audio_id` vào mục lịch sử của nó và tự gọi DELETE /v1/audio/<id>
 * khi xoá mục. Vì vậy module này KHÔNG đọc history.jsonl, KHÔNG xoá tệp theo history, KHÔNG có khái
 * niệm "mồ côi theo history" — chỉ tự đuổi tệp theo ngân sách MB và hạn ngày (của riêng nó).
 */
import {
  readFileSync, writeFileSync, existsSync, mkdirSync, chmodSync, renameSync, unlinkSync, readdirSync,
  openSync, readSync, closeSync, fstatSync,
} from 'node:fs';
import { join, dirname } from 'node:path';
import { randomBytes } from 'node:crypto';

/** id dictation: chữ/số/gạch dưới/gạch ngang (xem newId() ở engine/server/index.js) — chống path traversal. */
export const ID_RE = /^[A-Za-z0-9_-]+$/;
export const MAX_LIST_ITEMS = 500;

export class AudioStoreError extends Error {
  /** @param {string} message */
  constructor(message) { super(message); this.code = 'internal'; }
}

/** @param {string} path @param {Buffer} buf */
function writePrivateFile(path, buf) {
  const dir = dirname(path);
  mkdirSync(dir, { recursive: true, mode: 0o700 });
  // mkdir không đổi quyền của thư mục ĐÃ có (tạo bởi phiên bản khác/umask lạ): ép 0700 mỗi lần ghi.
  if (process.platform !== 'win32') chmodSync(dir, 0o700);
  const tmp = `${path}.tmp-${process.pid}-${randomBytes(4).toString('hex')}`;
  try {
    writeFileSync(tmp, buf, { mode: 0o600 });
    renameSync(tmp, path);
  } catch (err) {
    try { unlinkSync(tmp); } catch { /* best effort */ }
    throw err;
  }
  if (process.platform !== 'win32') chmodSync(path, 0o600);
}

/** @param {string} path @param {unknown} data */
function writePrivateJson(path, data) {
  writePrivateFile(path, Buffer.from(`${JSON.stringify(data, null, 2)}\n`));
}

/** @param {unknown} e */
function isSaneItem(e) {
  return e !== null && typeof e === 'object' && typeof e.id === 'string' && ID_RE.test(e.id)
    && typeof e.at === 'string' && !Number.isNaN(Date.parse(e.at))
    && Number.isFinite(e.bytes) && e.bytes >= 0 && Number.isFinite(e.audio_ms) && e.audio_ms >= 0;
}

const WAV_NAME_RE = /^([A-Za-z0-9_-]+)\.wav$/u;

/**
 * Phân tích header WAV do engine ghi (PCM 16-bit mono 16 kHz). Không khớp ⇒ null (tệp rác/lạ).
 * @param {Buffer} head vài KB đầu của tệp @param {number} fileSize
 * @returns {{ audio_ms: number }|null}
 */
export function parseWavHeader(head, fileSize) {
  if (head.length < 12 || head.toString('latin1', 0, 4) !== 'RIFF' || head.toString('latin1', 8, 12) !== 'WAVE') return null;
  let p = 12;
  /** @type {{ format: number, channels: number, rate: number, bits: number }|null} */
  let fmt = null;
  while (p + 8 <= head.length) {
    const id = head.toString('latin1', p, p + 4);
    const size = head.readUInt32LE(p + 4);
    if (id === 'fmt ') {
      if (size < 16 || p + 24 > head.length) return null;
      fmt = { format: head.readUInt16LE(p + 8), channels: head.readUInt16LE(p + 10), rate: head.readUInt32LE(p + 12), bits: head.readUInt16LE(p + 22) };
    } else if (id === 'data') {
      if (!fmt || fmt.format !== 1 || fmt.channels !== 1 || fmt.rate !== 16000 || fmt.bits !== 16) return null;
      const len = Math.min(size, Math.max(0, fileSize - (p + 8)));
      return len > 0 ? { audio_ms: Math.round(len / 32) } : null; // 16000 mẫu/s × 2 byte = 32 byte/ms
    }
    p += 8 + size + (size & 1);
  }
  return null;
}

/** Đọc vài KB đầu (không nạp cả tệp). @param {string} path @returns {{ audio_ms: number, size: number, mtimeMs: number }|null} */
function inspectWavFile(path) {
  let fd = -1;
  try {
    fd = openSync(path, 'r');
    const st = fstatSync(fd);
    if (!st.isFile()) return null;
    const head = Buffer.alloc(Math.min(4096, st.size));
    readSync(fd, head, 0, head.length, 0);
    const h = parseWavHeader(head, st.size);
    return h ? { audio_ms: h.audio_ms, size: st.size, mtimeMs: st.mtimeMs } : null;
  } catch {
    return null;
  } finally {
    if (fd >= 0) { try { closeSync(fd); } catch { /* best effort */ } }
  }
}

/**
 * @param {{ home: string, settings: { get: () => Record<string, unknown> }, now?: () => Date, log?: (e: object) => void,
 *           pruneIntervalMs?: number }} opts
 *   pruneIntervalMs: chu kỳ quét hạn/ngân sách khi engine chạy lâu (mặc định 1 giờ; timer unref, không giữ
 *   tiến trình sống). 0 = tắt timer (test).
 */
export function createAudioStore({ home, settings, now = () => new Date(), log = () => {}, pruneIntervalMs = 3600000 }) {
  if (typeof home !== 'string' || home === '') throw new TypeError('cần home');
  const dir = join(home, 'audio');
  const quarantineDir = join(dir, 'quarantine');
  const indexPath = join(dir, 'index.json');
  const filePath = (id) => join(dir, `${id}.wav`);

  /** @type {{id:string, at:string, audio_ms:number, bytes:number, app:string|null, mode:string|null}[]} */
  let items = [];

  // ---- Khởi động: AN TOÀN DỮ LIỆU. Mục lục (index.json) chỉ là bản ghi phụ trợ; nguồn sự thật là các tệp
  // WAV trên đĩa. Mục lục hỏng/rỗng/thiếu mục KHÔNG BAO GIỜ được dẫn tới xoá âm thanh hợp lệ: dựng lại
  // mục lục từ chính các tệp (id từ tên, bytes từ kích thước, audio_ms từ header, at từ mtime); tệp .wav
  // không phân tích được header thì chuyển sang quarantine/ (không xoá, không tính ngân sách).
  /** @type {string|null} lý do mục lục không dùng được (mã, không nội dung), hoặc null */
  let indexProblem = null;
  /** @type {unknown[]|null} */
  let loaded = null;
  if (existsSync(indexPath)) {
    try {
      const raw = JSON.parse(readFileSync(indexPath, 'utf8'));
      if (raw !== null && typeof raw === 'object' && Array.isArray(raw.items)) loaded = raw.items;
      else indexProblem = 'bad_shape';
    } catch (err) {
      indexProblem = err instanceof SyntaxError ? 'invalid_json' : String(/** @type {any} */ (err)?.code ?? 'unreadable');
    }
  }
  let dirty = indexProblem !== null;
  if (loaded) {
    const sane = loaded.filter(isSaneItem);
    if (sane.length !== loaded.length) dirty = true; // mục sai kiểu/thiếu trường: bỏ MỤC đó, tệp của nó sẽ được nhận lại bên dưới
    items = sane.map((e) => ({
      id: e.id, at: e.at, audio_ms: e.audio_ms, bytes: e.bytes,
      app: typeof e.app === 'string' ? e.app : null, mode: typeof e.mode === 'string' ? e.mode : null,
    }));
  }
  // Không để mục lục trỏ tới tệp đã mất: nếu không lọc, GET có thể trả 200 rồi đứt stream và
  // export có thể phát sinh ZIP hỏng.
  {
    const present = items.filter((e) => existsSync(filePath(e.id)));
    if (present.length !== items.length) dirty = true;
    items = present;
  }
  let recovered = 0;
  let quarantinedAtStart = 0;
  if (existsSync(dir)) {
    const names = readdirSync(dir);
    let wavCount = 0;
    for (const name of names) {
      // Tệp tạm do lần ghi bị ngắt giữa chừng (<id>.wav.tmp-…, index.json.tmp-…): bản ghi dở, không
      // phải âm thanh hoàn chỉnh của người dùng ⇒ dọn, nếu không sẽ tồn tại vô thời hạn ngoài ngân sách.
      if (/\.tmp-/u.test(name)) {
        try { unlinkSync(join(dir, name)); } catch { /* best effort */ }
        continue;
      }
      const m = WAV_NAME_RE.exec(name);
      if (!m) continue;
      wavCount++;
      const id = m[1];
      if (items.some((e) => e.id === id)) continue;
      // WAV chưa có trong mục lục (mục lục hỏng/thiếu mục, hoặc ngắt giữa ghi tệp và persist): nhận lại.
      const full = join(dir, name);
      const info = inspectWavFile(full);
      if (info) {
        items.push({ id, at: new Date(info.mtimeMs).toISOString(), audio_ms: info.audio_ms, bytes: info.size, app: null, mode: null });
        recovered++;
        if (process.platform !== 'win32') { try { chmodSync(full, 0o600); } catch { /* best effort */ } } // tệp nhận lại phải 0600 như tệp do engine ghi
        dirty = true;
      } else if (quarantineFile(name)) {
        quarantinedAtStart++;
      }
    }
    if (indexProblem === null && !existsSync(indexPath) && wavCount > 0) indexProblem = 'missing';
  }
  const indexRebuilt = indexProblem !== null;
  if (indexRebuilt || recovered > 0 || quarantinedAtStart > 0) {
    log({ event: 'audio_index_recovered', reason: indexProblem, recovered, quarantined: quarantinedAtStart });
  }

  /** Chuyển tệp .wav không phân tích được vào quarantine/ (0700). KHÔNG xoá. @param {string} name @returns {boolean} */
  function quarantineFile(name) {
    try {
      mkdirSync(quarantineDir, { recursive: true, mode: 0o700 });
      if (process.platform !== 'win32') chmodSync(quarantineDir, 0o700);
      let dest = join(quarantineDir, name);
      if (existsSync(dest)) dest = join(quarantineDir, `${name}.${Date.now()}`);
      renameSync(join(dir, name), dest);
      if (process.platform !== 'win32') { try { chmodSync(dest, 0o600); } catch { /* best effort */ } }
      return true;
    } catch (err) {
      // Không chuyển được thì để nguyên tại chỗ (vẫn không xoá) và thử lại ở lần khởi động sau.
      log({ event: 'audio_quarantine_failed', code: /** @type {any} */ (err)?.code ?? 'unknown' });
      return false;
    }
  }

  /** Số tệp đang nằm trong quarantine/ (không tính vào ngân sách). */
  function quarantineCount() {
    try { return readdirSync(quarantineDir).length; } catch { return 0; }
  }

  function persist() {
    try {
      writePrivateJson(indexPath, { items });
    } catch (err) {
      log({ event: 'audio_index_save_failed', code: /** @type {any} */ (err)?.code ?? 'unknown' });
    }
  }

  function removeFile(id) {
    try { unlinkSync(filePath(id)); } catch { /* tệp có thể đã mất; không phải lỗi cần báo */ }
  }

  const budgetBytes = () => Math.round(Number(settings.get().audio_history_mb) || 200) * 1024 * 1024;
  const retentionDays = () => Math.round(Number(settings.get().audio_history_days) || 7);

  /**
   * Đuổi tệp quá hạn ngày, rồi đuổi tệp CŨ NHẤT tới khi tổng ≤ ngân sách (contract/engine-api.md
   * mục "Lịch sử âm thanh"). Chạy sau mỗi lần ghi VÀ một lần lúc khởi động (không phụ thuộc
   * audio_history đang bật/tắt — tắt chỉ dừng ghi MỚI, không tự xoá cũ ngay khi tắt, nhưng hạn/ngân
   * sách vẫn áp dụng ở lần quét kế tiếp, vd lúc khởi động lại engine).
   */
  function prune() {
    let cutoffMs;
    let budget;
    try {
      cutoffMs = now().getTime() - retentionDays() * 86400000;
      budget = budgetBytes();
    } catch (err) {
      // Không đọc được cài đặt (config.json hỏng): bỏ lần quét này, KHÔNG đoán giá trị rồi xoá nhầm.
      log({ event: 'audio_prune_skipped', code: /** @type {any} */ (err)?.code ?? 'settings_unreadable' });
      return;
    }
    let changed = false;
    items.sort((a, b) => Date.parse(a.at) - Date.parse(b.at)); // cũ -> mới
    const kept = [];
    for (const e of items) {
      if (Date.parse(e.at) < cutoffMs) { removeFile(e.id); changed = true; continue; }
      kept.push(e);
    }
    items = kept;
    let total = items.reduce((s, e) => s + e.bytes, 0);
    while (total > budget && items.length > 0) {
      const oldest = items.shift();
      removeFile(oldest.id);
      total -= oldest.bytes;
      changed = true;
    }
    if (changed) persist();
  }

  if (dirty) persist(); // ghi lại mục lục đã dựng/sửa (nguyên tử) TRƯỚC khi đuổi theo ngân sách/hạn ngày
  prune(); // quét lúc khởi động — item A6 "chạy quét khi khởi động"
  /** @type {NodeJS.Timeout|null} */
  const pruneTimer = pruneIntervalMs > 0 ? setInterval(prune, pruneIntervalMs) : null;
  pruneTimer?.unref();

  return {
    /**
     * Ghi một WAV cho một dictation thành công. Caller (engine/server/index.js) chỉ gọi khi
     * settings.audio_history === true VÀ dictation không rỗng/không lỗi.
     * @param {{ id: string, wav: Buffer, audioMs: number, app?: string|null, mode?: string|null }} args
     * @returns {boolean} true CHỈ khi tệp đã ghi VÀ còn tồn tại sau lần quét ngân sách (một tệp đơn lẻ
     *   lớn hơn cả ngân sách bị đuổi ngay ⇒ false, để caller không trả `audio_id` trỏ vào tệp đã mất)
     */
    write({ id, wav, audioMs, app = null, mode = null }) {
      if (!ID_RE.test(id)) { log({ event: 'audio_write_bad_id' }); return false; }
      try {
        writePrivateFile(filePath(id), wav);
      } catch (err) {
        log({ event: 'audio_write_failed', code: /** @type {any} */ (err)?.code ?? 'unknown' });
        return false;
      }
      items = items.filter((e) => e.id !== id);
      items.push({
        id, at: now().toISOString(), audio_ms: Math.max(0, Math.round(audioMs) || 0), bytes: wav.length,
        app: typeof app === 'string' ? app : null, mode: typeof mode === 'string' ? mode : null,
      });
      persist();
      prune();
      return items.some((e) => e.id === id);
    },

    /** GET /v1/audio (contract/engine-api.md): mới nhất trước, tối đa MAX_LIST_ITEMS mục. */
    list() {
      prune(); // engine chạy lâu: hạn ngày phải đúng cả khi chưa tới chu kỳ timer
      const sorted = [...items].sort((a, b) => Date.parse(b.at) - Date.parse(a.at));
      return {
        enabled: settings.get().audio_history === true,
        count: items.length,
        bytes: items.reduce((s, e) => s + e.bytes, 0),
        budget_bytes: budgetBytes(),
        days: retentionDays(),
        index_rebuilt: indexRebuilt,
        recovered,
        quarantined: quarantineCount(),
        items: sorted.slice(0, MAX_LIST_ITEMS).map((e) => ({ id: e.id, bytes: e.bytes, audio_ms: e.audio_ms, at: e.at })),
      };
    },

    /** Đường dẫn tệp WAV cho GET /v1/audio/<id>, hoặc null nếu id không hợp lệ/không có. @param {string} id */
    pathFor(id) {
      if (!ID_RE.test(id)) return null;
      return items.some((e) => e.id === id) ? filePath(id) : null;
    },

    /** DELETE /v1/audio/<id>. @param {string} id @returns {{ok:boolean}} */
    remove(id) {
      if (!ID_RE.test(id)) return { ok: false };
      const before = items.length;
      items = items.filter((e) => e.id !== id);
      if (items.length === before) return { ok: false };
      removeFile(id);
      persist();
      return { ok: true };
    },

    /** DELETE /v1/audio (xoá tất cả). @returns {{ok:true, deleted:number}} */
    removeAll() {
      const n = items.length;
      for (const e of items) removeFile(e.id);
      items = [];
      persist();
      // Xoá tất cả = xoá cả tệp đã cách ly (có thể vẫn chứa giọng người dùng); chỉ khi NGƯỜI DÙNG yêu cầu.
      try {
        for (const name of readdirSync(quarantineDir)) unlinkSync(join(quarantineDir, name));
      } catch { /* chưa có quarantine/ hoặc đã trống */ }
      return { ok: true, deleted: n };
    },

    /** Danh sách cho GET /v1/audio/export (KHÔNG có text — engine không có văn bản lịch sử, xem đầu tệp). */
    exportEntries() {
      return items.map((e) => ({ id: e.id, at: e.at, audio_ms: e.audio_ms, app: e.app, mode: e.mode, path: filePath(e.id) }));
    },

    /** Dừng timer quét định kỳ (test/tắt máy chủ). */
    close() { clearInterval(pruneTimer); },
  };
}
