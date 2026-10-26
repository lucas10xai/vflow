#!/usr/bin/env node
/**
 * Dò nhanh model nào GỌI ĐƯỢC THẬT qua 9Router (contract/remote-stt.md, khoá rewrite.key).
 * Mỗi model: MỘT yêu cầu chat completion cực nhỏ (max_tokens thấp), không phải chỉ tra GET /v1/models
 * (model có trong danh sách chưa chắc gọi được — xem báo cáo E1a: 400 model_not_supported, hết credit).
 * KHÔNG in khoá ra bất cứ đâu. Chạy: node eval/tidy/discover-models.js
 */
import { readFileSync } from 'node:fs';
import { DEFAULT_CONFIG, expandHome } from '../../engine/post/config.js';

/** Tên model ứng viên: ưu tiên nhanh/rẻ/nhỏ (flash/lite/mini/nano/haiku/small/instant...). */
const CANDIDATES = [
  'ag/gemini-3.6-flash',
  'ag/gemini-3.7-flash',
  'ag/gemini-3.5-flash',
  'ag/gemini-3.8-flash',
  'ag/gemini-pro-agent',
  'ag/gemini-3.1-pro-low',
];
/** Vài model trả CỐ ĐỊNH thông báo "model này đã ngừng, dùng model khác" (HTTP 200, có nội dung)
 * thay vì lỗi thật — phải lọc riêng, không tính là "gọi được" (xem báo cáo v2, mục dò model). */
const DEPRECATION_STUB_RE = /no longer available/i;

async function main() {
  const keyFile = DEFAULT_CONFIG.rewrite.key_file;
  const key = readFileSync(expandHome(keyFile), 'utf8').trim();
  const url = `${DEFAULT_CONFIG.rewrite.url.replace(/\/+$/, '')}/chat/completions`;
  console.log(`9Router: ${DEFAULT_CONFIG.rewrite.url} — ${CANDIDATES.length} model dò, 1 yêu cầu/model.\n`);
  /** @type {{model:string, ok:boolean, ms:number, info:string}[]} */
  const results = [];
  for (const model of CANDIDATES) {
    const started = Date.now();
    const controller = new AbortController();
    const timer = setTimeout(() => controller.abort(), 8000);
    try {
      const res = await fetch(url, {
        method: 'POST',
        headers: { 'content-type': 'application/json', authorization: `Bearer ${key}` },
        body: JSON.stringify({ model, temperature: 0, max_tokens: 10, stream: false, messages: [{ role: 'user', content: 'Trả lời đúng một từ: con mèo nói gì?' }] }),
        signal: controller.signal,
      });
      const ms = Date.now() - started;
      if (!res.ok) {
        const body = await res.text().catch(() => '');
        let msg = body.slice(0, 160);
        try { msg = JSON.parse(body)?.error?.message?.slice(0, 160) ?? msg; } catch { /* giữ raw */ }
        results.push({ model, ok: false, ms, info: `HTTP ${res.status}: ${msg}` });
      } else {
        const json = await res.json().catch(() => null);
        const content = json?.choices?.[0]?.message?.content;
        const isStub = typeof content === 'string' && DEPRECATION_STUB_RE.test(content);
        const ok = typeof content === 'string' && content.length > 0 && !isStub;
        results.push({
          model, ok, ms,
          info: isStub ? `STUB NGỪNG HOẠT ĐỘNG (không phải phản hồi thật): ${JSON.stringify(content.slice(0, 60))}`
            : typeof content === 'string' ? `trả: ${JSON.stringify(content.slice(0, 20))}` : 'phản hồi rỗng/không hợp lệ',
        });
      }
    } catch (e) {
      results.push({ model, ok: false, ms: Date.now() - started, info: controller.signal.aborted ? 'timeout' : `network: ${e.message}` });
    } finally {
      clearTimeout(timer);
    }
  }
  console.log('| Model | Gọi được | ms | Ghi chú |');
  console.log('|---|---|---|---|');
  for (const r of results) console.log(`| ${r.model} | ${r.ok ? 'CÓ' : 'không'} | ${r.ms} | ${r.info} |`);
  console.log(`\nTổng yêu cầu thật đã dùng: ${results.length}`);
  console.log(`\nGọi được: ${results.filter((r) => r.ok).map((r) => r.model).join(', ') || '(không có)'}`);
}

main();
