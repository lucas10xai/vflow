#!/usr/bin/env node
/**
 * Đo thật các model ứng viên cho chế độ tidy qua 9Router thật (eval/tidy/cases.json).
 * KHÔNG in khoá ra bất cứ đâu; khoá chỉ đọc bằng mã từ rewrite.key_file.
 * Giới hạn TỔNG số yêu cầu thật ≤ MAX_REQUESTS (mặc định 120): số ca mỗi model = floor(MAX/số model).
 *
 * Chạy: node eval/tidy-bench.js [--out <path>] [--max-requests 120]
 */
import { readFileSync, writeFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { tidyRaw, checkGuard } from '../engine/post/tidy.js';
import { DEFAULT_CONFIG, expandHome } from '../engine/post/config.js';
import { percentile } from './metrics.js';

/**
 * Dò qua eval/tidy/discover-models.js (2026-10-26, v2 — xem eval/tidy/results-2026-10-26-v2.md mục
 * dò model để biết chi tiết đầy đủ, kể cả các model trông như "gọi được" nhưng thật ra chỉ trả một
 * thông báo ngừng hoạt động cố định — KHÔNG phải phản hồi thật): trong ~36 model ứng viên thử, chỉ
 * 3 gọi được thật qua 9Router hiện tại (`ag/gemini-3-flash`, `ag/gemini-3.8-flash-low`,
 * `ag/gemini-3.8-flash`); `ag/gemini-3.8-flash` (không có hậu tố mức suy luận) bị loại khỏi danh
 * sách đo ở đây vì quá chậm dù đã tối ưu (9/30 ca timeout 8s — xem báo cáo), chỉ còn lại 2.
 */
const CANDIDATES = ['ag/gemini-3-flash', 'ag/gemini-3.8-flash-low'];

/** @param {string[]} argv */
function parseArgs(argv) {
  const out = { out: fileURLToPath(new URL('./tidy/results-2026-10-26-v2.md', import.meta.url)), maxRequests: 120 };
  for (let i = 0; i < argv.length; i++) {
    if (argv[i] === '--out') out.out = argv[++i];
    else if (argv[i] === '--max-requests') out.maxRequests = Number(argv[++i]);
  }
  return out;
}

/** @param {string} s @param {string} needle */
const containsFold = (s, needle) => s.toLowerCase().includes(needle.toLowerCase());

/**
 * @param {string} text @param {string[]} expectContains @param {string[]} expectNotContains
 */
function meetsExpectation(text, expectContains, expectNotContains) {
  return expectContains.every((n) => containsFold(text, n)) && !expectNotContains.some((n) => containsFold(text, n));
}

/** @param {number[]} ms */
function fmtLatency(ms) {
  if (ms.length === 0) return 'không có mẫu thành công';
  return `median=${Math.round(percentile(ms, 0.5))}ms p95=${Math.round(percentile(ms, 0.95))}ms (n=${ms.length})`;
}

async function main() {
  const args = parseArgs(process.argv.slice(2));
  const casesPath = fileURLToPath(new URL('./tidy/cases.json', import.meta.url));
  const { cases } = JSON.parse(readFileSync(casesPath, 'utf8'));
  const keyFile = DEFAULT_CONFIG.rewrite.key_file;
  const keyExists = (() => {
    try {
      readFileSync(expandHome(keyFile), 'utf8');
      return true;
    } catch {
      return false;
    }
  })();
  if (!keyExists) {
    console.error(`Không đọc được khoá ở ${keyFile} — không thể chạy đo thật. Dừng.`);
    process.exitCode = 1;
    return;
  }

  const casesPerModel = Math.max(1, Math.min(cases.length, Math.floor(args.maxRequests / CANDIDATES.length)));
  const selected = cases.slice(0, casesPerModel);
  const rewrite = { url: DEFAULT_CONFIG.rewrite.url, model: null, timeout_ms: 8000, key_file: keyFile };
  const guard = DEFAULT_CONFIG.tidy.guard;

  console.log(`9Router: ${rewrite.url}`);
  console.log(`Số model ứng viên: ${CANDIDATES.length}, số ca/model: ${casesPerModel}, tổng yêu cầu thật dự kiến: ${CANDIDATES.length * casesPerModel}`);

  let totalRequests = 0;
  /** @type {Record<string, any>} */
  const results = {};

  for (const model of CANDIDATES) {
    console.log(`\n== ${model} ==`);
    const stat = { model, n: 0, errors: {}, guardPass: 0, expectationPass: 0, answeredQuestion: 0, latenciesOk: [] };
    for (const c of selected) {
      totalRequests++;
      const started = Date.now();
      const r = await tidyRaw({ text: c.input, rewrite: { ...rewrite, model }, fetchImpl: fetch });
      const elapsed = Date.now() - started;
      stat.n++;
      if (r.error !== null) {
        stat.errors[r.error] = (stat.errors[r.error] ?? 0) + 1;
        console.log(`  [${c.id}] lỗi: ${r.error} (${elapsed}ms)`);
        continue;
      }
      stat.latenciesOk.push(elapsed);
      const guardOk = checkGuard(c.input, r.text, guard);
      if (guardOk) stat.guardPass++;
      const meets = guardOk && meetsExpectation(r.text, c.expect_contains, c.expect_not_contains);
      if (meets) stat.expectationPass++;
      if (c.type === 'question' && c.expect_not_contains.some((n) => containsFold(r.text, n))) stat.answeredQuestion++;
      console.log(`  [${c.id}] ${guardOk ? 'guard_ok ' : 'GUARD_REJECTED '}${meets ? 'ĐẠT' : 'chưa đạt'} (${elapsed}ms)`);
    }
    results[model] = stat;
  }

  const lines = [];
  lines.push('# Benchmark model tidy — 2026-10-26');
  lines.push('');
  lines.push(`9Router: \`${rewrite.url}\`. Khoá đọc từ \`${keyFile}\` (không ghi/in ra ở đâu).`);
  lines.push(`Tổng số yêu cầu thật đã dùng: **${totalRequests}** (≤ 120 theo yêu cầu; ${CANDIDATES.length} model × ${casesPerModel}/${cases.length} ca của eval/tidy/cases.json).`);
  lines.push('');
  lines.push('| Model | n | lỗi | qua guard | đạt kỳ vọng | trả lời câu hỏi (sai) | độ trễ |');
  lines.push('|---|---|---|---|---|---|---|');
  /** @type {{model:string, guardRate:number, expRate:number, p95:number|null, qualifies:boolean}[]} */
  const scored = [];
  for (const model of CANDIDATES) {
    const s = results[model];
    const guardRate = s.n > 0 ? s.guardPass / s.n : 0;
    const expRate = s.n > 0 ? s.expectationPass / s.n : 0;
    const p95 = s.latenciesOk.length > 0 ? percentile(s.latenciesOk, 0.95) : null;
    const errStr = Object.entries(s.errors).map(([k, v]) => `${k}×${v}`).join(', ') || '—';
    lines.push(
      `| ${model} | ${s.n} | ${errStr} | ${(guardRate * 100).toFixed(0)}% | ${(expRate * 100).toFixed(0)}% | ${s.answeredQuestion} | ${fmtLatency(s.latenciesOk)} |`,
    );
    scored.push({ model, guardRate, expRate, p95, qualifies: guardRate >= 0.9 && expRate >= 0.8 && p95 !== null && p95 < 3000 });
  }
  lines.push('');
  lines.push(`Tiêu chí chọn mặc định: qua guard ≥ 90%, đạt kỳ vọng ≥ 80%, p95 < 3000ms (xem eval/tidy-bench.js).`);
  const winners = scored.filter((s) => s.qualifies).sort((a, b) => b.expRate - a.expRate || (a.p95 ?? 0) - (b.p95 ?? 0));
  lines.push('');
  if (winners.length > 0) {
    const w = winners[0];
    lines.push(`## Khuyến nghị: \`${w.model}\``);
    lines.push(`qua guard ${(w.guardRate * 100).toFixed(0)}%, đạt kỳ vọng ${(w.expRate * 100).toFixed(0)}%, p95 ${Math.round(w.p95)}ms.`);
  } else {
    lines.push('## Khuyến nghị: KHÔNG có model nào đạt đủ cả ba tiêu chí trong lần đo này.');
    lines.push('Xem bảng trên để chọn đánh đổi (ví dụ model có đạt kỳ vọng cao nhất nhưng p95 vượt ngưỡng).');
  }
  lines.push('');
  lines.push(`## Ca mẫu đã dùng (${casesPerModel}/${cases.length} ca đầu của eval/tidy/cases.json, xem file đó để biết nội dung đầy đủ)`);
  for (const c of selected) lines.push(`- \`${c.id}\` (${c.type})`);
  if (casesPerModel < cases.length) {
    lines.push('');
    lines.push(`Lưu ý: chỉ dùng ${casesPerModel}/${cases.length} ca để giữ tổng yêu cầu thật ≤ ${args.maxRequests}; các ca còn lại chưa được đo.`);
  }
  writeFileSync(args.out, lines.join('\n') + '\n');
  console.log(`\nĐã ghi báo cáo: ${args.out}`);
  console.log(`Tổng số yêu cầu thật đã dùng: ${totalRequests}`);
}

main();
