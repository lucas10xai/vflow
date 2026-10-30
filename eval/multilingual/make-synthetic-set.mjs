/** Tạo WAV tổng hợp 16 kHz mono vào thư mục được truyền bằng --out. */
import { spawn } from 'node:child_process';
import fs from 'node:fs/promises';
import path from 'node:path';
import corpus from './corpus.json' with { type: 'json' };

const i = process.argv.indexOf('--out');
if (i < 0 || !process.argv[i + 1]) throw new Error('Thiếu --out');
const out = path.resolve(process.argv[i + 1]);
if (out.startsWith(path.resolve('eval') + path.sep)) throw new Error('Không ghi WAV tổng hợp vào repo');
await fs.mkdir(out, { recursive: true });
function run(bin, args) { return new Promise((resolve, reject) => { const p = spawn(bin, args, { stdio: 'inherit' }); p.on('error', reject); p.on('exit', (c) => c === 0 ? resolve() : reject(new Error(`${bin} thoát ${c}`))); }); }
for (const item of corpus) {
  const aiff = path.join(out, `${item.id}.aiff`); const wav = path.join(out, `${item.id}.wav`);
  await run('say', ['-v', item.voice, '-o', aiff, item.text]);
  await run('afconvert', ['-f', 'WAVE', '-d', 'LEI16@16000', '-c', '1', aiff, wav]);
  await fs.writeFile(path.join(out, `${item.id}.txt`), `${item.text}\n`);
  await fs.rm(aiff, { force: true });
}
await fs.writeFile(path.join(out, 'set.json'), JSON.stringify({ synthetic: true, voices: ['Linh', 'Samantha'], items: corpus.length }, null, 2) + '\n');
