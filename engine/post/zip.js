/**
 * Bộ ghi ZIP tối giản kiểu "store" (KHÔNG nén) bằng thư viện chuẩn Node, dùng data descriptor
 * (cờ bit 3) để ghi CRC32/kích thước SAU khi đã stream dữ liệu — không cần biết trước hay nạp cả
 * tệp vào RAM (contract/engine-api.md mục "Xuất âm thanh (export)"). Chỉ dùng cho GET /v1/audio/export.
 */
import { createReadStream } from 'node:fs';

/** @type {Uint32Array} */
const CRC_TABLE = (() => {
  const t = new Uint32Array(256);
  for (let n = 0; n < 256; n++) {
    let c = n;
    for (let k = 0; k < 8; k++) c = (c & 1) !== 0 ? (0xedb88320 ^ (c >>> 1)) : (c >>> 1);
    t[n] = c >>> 0;
  }
  return t;
})();

/** @param {Uint8Array} buf @param {number} crc CRC32 đang chạy (chưa đảo bit, 0xFFFFFFFF lúc bắt đầu) */
export function crc32Update(buf, crc = 0xffffffff) {
  let c = crc;
  for (let i = 0; i < buf.length; i++) c = CRC_TABLE[(c ^ buf[i]) & 0xff] ^ (c >>> 8);
  return c >>> 0;
}
/** @param {number} crc */
export const crc32Final = (crc) => (crc ^ 0xffffffff) >>> 0;

/** @param {Date} date */
function dosDateTime(date) {
  const time = ((date.getHours() & 0x1f) << 11) | ((date.getMinutes() & 0x3f) << 5) | ((Math.floor(date.getSeconds() / 2)) & 0x1f);
  const d = ((Math.max(0, date.getFullYear() - 1980) & 0x7f) << 9) | (((date.getMonth() + 1) & 0xf) << 5) | (date.getDate() & 0x1f);
  return { time, d };
}

/**
 * @param {Buffer} nameBuf @param {Date} date
 */
function localHeader(nameBuf, date) {
  const { time, d } = dosDateTime(date);
  const b = Buffer.alloc(30);
  b.writeUInt32LE(0x04034b50, 0);
  b.writeUInt16LE(20, 4); // version needed to extract
  b.writeUInt16LE(0x0008, 6); // flags: bit 3 = data descriptor theo sau dữ liệu
  b.writeUInt16LE(0, 8); // method: 0 = store (không nén)
  b.writeUInt16LE(time, 10);
  b.writeUInt16LE(d, 12);
  b.writeUInt32LE(0, 14); // crc32 (0 — giá trị thật ở data descriptor)
  b.writeUInt32LE(0, 18); // compressed size (như trên)
  b.writeUInt32LE(0, 22); // uncompressed size (như trên)
  b.writeUInt16LE(nameBuf.length, 26);
  b.writeUInt16LE(0, 28); // extra field length
  return b;
}

/** @param {number} crc @param {number} size */
function dataDescriptor(crc, size) {
  const b = Buffer.alloc(16);
  b.writeUInt32LE(0x08074b50, 0);
  b.writeUInt32LE(crc, 4);
  b.writeUInt32LE(size, 8);
  b.writeUInt32LE(size, 12);
  return b;
}

/**
 * @param {{ nameBuf: Buffer, crc: number, size: number, localOffset: number, date: Date }} e
 */
function centralHeader(e) {
  const { time, d } = dosDateTime(e.date);
  const b = Buffer.alloc(46);
  b.writeUInt32LE(0x02014b50, 0);
  b.writeUInt16LE(20, 4); // version made by
  b.writeUInt16LE(20, 6); // version needed
  b.writeUInt16LE(0x0008, 8); // flags
  b.writeUInt16LE(0, 10); // method
  b.writeUInt16LE(time, 12);
  b.writeUInt16LE(d, 14);
  b.writeUInt32LE(e.crc, 16);
  b.writeUInt32LE(e.size, 20);
  b.writeUInt32LE(e.size, 24);
  b.writeUInt16LE(e.nameBuf.length, 28);
  b.writeUInt16LE(0, 30); // extra length
  b.writeUInt16LE(0, 32); // comment length
  b.writeUInt16LE(0, 34); // disk number start
  b.writeUInt16LE(0, 36); // internal attrs
  b.writeUInt32LE(0, 38); // external attrs
  b.writeUInt32LE(e.localOffset, 42);
  return b;
}

/**
 * @param {{ write: (buf: Buffer) => void }} sink thường là `http.ServerResponse` (có .write()).
 */
export function createZipWriter(sink) {
  let offset = 0;
  /** @type {{ nameBuf: Buffer, crc: number, size: number, localOffset: number, date: Date }[]} */
  const central = [];
  /** @param {Buffer} buf @returns {boolean} false khi bộ đệm của sink đầy (cần chờ 'drain') */
  function put(buf) { const ok = sink.write(buf); offset += buf.length; return ok !== false; }

  return {
    /** Thêm một tệp nhỏ đã có sẵn trong RAM (vd index.json). @param {string} name @param {Buffer} buf @param {Date} [date] */
    addBuffer(name, buf, date = new Date()) {
      const nameBuf = Buffer.from(name, 'utf8');
      const localOffset = offset;
      put(localHeader(nameBuf, date));
      put(nameBuf);
      put(buf);
      const crc = crc32Final(crc32Update(buf));
      put(dataDescriptor(crc, buf.length));
      central.push({ nameBuf, crc, size: buf.length, localOffset, date });
    },

    /** Thêm một tệp từ đĩa, STREAM từng khối (không nạp cả tệp vào RAM). @param {string} name @param {string} filePath @param {Date} [date] */
    async addFile(name, filePath, date = new Date()) {
      const nameBuf = Buffer.from(name, 'utf8');
      const localOffset = offset;
      put(localHeader(nameBuf, date));
      put(nameBuf);
      let crc = 0xffffffff;
      let size = 0;
      await new Promise((resolve, reject) => {
        const rs = createReadStream(filePath);
        // Backpressure: máy khách tải chậm KHÔNG được làm RAM engine phình tới cỡ cả kho âm thanh
        // (ngân sách có thể tới 2000 MB). Sink đầy ⇒ tạm dừng đọc tới 'drain'; sink đóng (máy khách
        // bỏ tải) ⇒ dừng hẳn và báo lỗi thay vì treo vĩnh viễn chờ 'drain'.
        const onDrain = () => rs.resume();
        const onClose = () => { rs.destroy(); reject(new Error('sink đã đóng trước khi ghi xong ZIP')); };
        sink.on?.('drain', onDrain);
        sink.once?.('close', onClose);
        const cleanup = () => { sink.off?.('drain', onDrain); sink.off?.('close', onClose); };
        rs.on('data', (chunk) => {
          crc = crc32Update(chunk, crc); size += chunk.length;
          if (!put(chunk)) rs.pause();
        });
        rs.on('end', () => { cleanup(); resolve(undefined); });
        rs.on('error', (err) => { cleanup(); reject(err); });
      });
      const finalCrc = crc32Final(crc);
      put(dataDescriptor(finalCrc, size));
      central.push({ nameBuf, crc: finalCrc, size, localOffset, date });
    },

    /** Ghi central directory + end record; gọi đúng một lần sau khi đã add hết. */
    finish() {
      const centralStart = offset;
      for (const e of central) {
        put(centralHeader(e));
        put(e.nameBuf);
      }
      const centralSize = offset - centralStart;
      const end = Buffer.alloc(22);
      end.writeUInt32LE(0x06054b50, 0);
      end.writeUInt16LE(0, 4); // disk number
      end.writeUInt16LE(0, 6); // disk with central dir
      end.writeUInt16LE(central.length, 8);
      end.writeUInt16LE(central.length, 10);
      end.writeUInt32LE(centralSize, 12);
      end.writeUInt32LE(centralStart, 16);
      end.writeUInt16LE(0, 20); // comment length
      put(end);
    },
  };
}
