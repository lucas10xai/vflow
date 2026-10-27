import { test } from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { EventEmitter } from 'node:events';
import { crc32 } from 'node:zlib';
import { createZipWriter } from './zip.js';

/** Bộ đọc ZIP độc lập (chỉ từ central directory) — KHÔNG dùng lại mã của zip.js để không kiểm chính nó. */
function readZip(buf) {
  const eocd = buf.lastIndexOf(Buffer.from([0x50, 0x4b, 0x05, 0x06]));
  assert.ok(eocd >= 0, 'thiếu end-of-central-directory');
  const count = buf.readUInt16LE(eocd + 10);
  const cdSize = buf.readUInt32LE(eocd + 12);
  const cdOff = buf.readUInt32LE(eocd + 16);
  assert.equal(cdOff + cdSize, eocd, 'central directory phải liền kề end record');
  const out = {};
  let p = cdOff;
  for (let i = 0; i < count; i++) {
    assert.equal(buf.readUInt32LE(p), 0x02014b50);
    const method = buf.readUInt16LE(p + 10);
    const crc = buf.readUInt32LE(p + 16);
    const csize = buf.readUInt32LE(p + 20);
    const usize = buf.readUInt32LE(p + 24);
    const nlen = buf.readUInt16LE(p + 28);
    const local = buf.readUInt32LE(p + 42);
    const name = buf.subarray(p + 46, p + 46 + nlen).toString('utf8');
    assert.equal(method, 0, 'chỉ "store"');
    assert.equal(csize, usize);
    assert.equal(buf.readUInt32LE(local), 0x04034b50);
    const lnlen = buf.readUInt16LE(local + 26);
    const lxlen = buf.readUInt16LE(local + 28);
    const dataStart = local + 30 + lnlen + lxlen;
    const data = buf.subarray(dataStart, dataStart + usize);
    assert.equal(crc32(data), crc, `CRC ${name}`);
    // data descriptor ngay sau dữ liệu phải khớp central directory
    assert.equal(buf.readUInt32LE(dataStart + usize), 0x08074b50);
    assert.equal(buf.readUInt32LE(dataStart + usize + 4), crc);
    assert.equal(buf.readUInt32LE(dataStart + usize + 8), usize);
    out[name] = data;
    p += 46 + nlen;
  }
  return out;
}

const collector = () => { const chunks = []; return { chunks, write(b) { chunks.push(Buffer.from(b)); return true; }, buf: () => Buffer.concat(chunks) }; };

test('ZIP: buffer + tệp trên đĩa (nhiều khối, nhiều tệp) đọc lại đúng nội dung và CRC; tên UTF-8 giữ nguyên', async () => {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'vflow-zip-'));
  try {
    const big = Buffer.alloc(300_000);
    for (let i = 0; i < big.length; i++) big[i] = (i * 31 + 7) & 0xff; // > nhiều khối 64 KB của createReadStream
    fs.writeFileSync(path.join(dir, 'big.bin'), big);
    fs.writeFileSync(path.join(dir, 'empty.bin'), '');
    const sink = collector();
    const zip = createZipWriter(sink);
    zip.addBuffer('index.json', Buffer.from('[{"id":"a"}]\n'));
    await zip.addFile('big.wav', path.join(dir, 'big.bin'), new Date('2026-10-26T10:00:00Z'));
    await zip.addFile('trống.wav', path.join(dir, 'empty.bin'));
    zip.finish();
    const files = readZip(sink.buf());
    assert.deepEqual(Object.keys(files), ['index.json', 'big.wav', 'trống.wav']);
    assert.equal(files['index.json'].toString(), '[{"id":"a"}]\n');
    assert.ok(files['big.wav'].equals(big));
    assert.equal(files['trống.wav'].length, 0);
  } finally { fs.rmSync(dir, { recursive: true, force: true }); }
});

test('ZIP rỗng (chỉ index.json) vẫn hợp lệ', () => {
  const sink = collector();
  const zip = createZipWriter(sink);
  zip.addBuffer('index.json', Buffer.from('[]\n'));
  zip.finish();
  assert.deepEqual(Object.keys(readZip(sink.buf())), ['index.json']);
});

test('backpressure: sink đầy ⇒ dừng đọc tới "drain"; không ghi thêm khi chưa drain, ZIP cuối vẫn đủ byte', async () => {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'vflow-zip-'));
  try {
    const big = Buffer.alloc(1_000_000, 3);
    fs.writeFileSync(path.join(dir, 'f.bin'), big);
    const sink = new EventEmitter();
    const chunks = [];
    let blocked = false;
    let writesWhileBlocked = 0;
    sink.write = (b) => {
      if (blocked) writesWhileBlocked++;
      chunks.push(Buffer.from(b));
      if (b.length >= 16_384 && !blocked) { blocked = true; return false; } // khối dữ liệu đầu tiên làm đầy bộ đệm
      return true;
    };
    const zip = createZipWriter(sink);
    const done = zip.addFile('f.wav', path.join(dir, 'f.bin'));
    await new Promise((r) => setTimeout(r, 150)); // cho luồng đọc cơ hội chạy tiếp nếu không biết dừng
    assert.equal(blocked, true);
    const bytesWhileBlocked = chunks.reduce((s, c) => s + c.length, 0);
    assert.ok(bytesWhileBlocked < 300_000, `đã ghi ${bytesWhileBlocked} B dù sink đầy`);
    assert.equal(writesWhileBlocked, 0);
    // drain lần lượt cho tới hết
    const pump = setInterval(() => { blocked = false; sink.emit('drain'); }, 5);
    await done;
    clearInterval(pump);
    zip.finish();
    assert.ok(readZip(Buffer.concat(chunks))['f.wav'].equals(big));
  } finally { fs.rmSync(dir, { recursive: true, force: true }); }
});

test('sink đóng giữa chừng (client bỏ tải) ⇒ addFile báo lỗi, không treo chờ drain mãi mãi', async () => {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'vflow-zip-'));
  try {
    fs.writeFileSync(path.join(dir, 'f.bin'), Buffer.alloc(1_000_000, 1));
    const sink = new EventEmitter();
    sink.write = () => false; // luôn đầy
    const zip = createZipWriter(sink);
    const p = zip.addFile('f.wav', path.join(dir, 'f.bin'));
    setTimeout(() => sink.emit('close'), 50);
    await assert.rejects(p, /sink đã đóng/);
  } finally { fs.rmSync(dir, { recursive: true, force: true }); }
});
