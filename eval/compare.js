/**
 * So sánh model STT trên một bộ câu (`NN.wav` + `NN.txt`): văn bản thô và sau engine/post,
 * WER/CER (nhạy và không nhạy dấu thanh) cho cả hai dạng, bắt thuật ngữ tiếng Anh kèm bảng thuật ngữ sót
 * (thuật ngữ → các cách model đã nghe ra), độ trễ/RTF, và KẾT LUẬN theo tiêu chí trong
 * docs/specs/2026-10-26-vflow-design.md. Lỗi một clip không làm sập lần chạy; clip lỗi KHÔNG được tính là 0.
 */
import fsp from 'node:fs/promises';
import path from 'node:path';
import { performance } from 'node:perf_hooks';
import { aggregate, containsTerm, normalizeText, percentile, scoreBoth } from './metrics.js';

/** Tiêu chí chọn model mặc định (docs/specs/2026-10-26-vflow-design.md). */
export const CRITERIA = Object.freeze({ rtfMax: 0.3, p95Ms5s: 1500, band5s: [4000, 6000], minClips: 30 });

/**
 * Căn hàng mức từ (Levenshtein có truy vết). Ưu tiên khớp/thay trước xoá/chèn khi bằng chi phí.
 * @param {string[]} ref @param {string[]} hyp
 * @returns {{ op: 'eq'|'sub'|'del'|'ins', r?: number, h?: number }[]}
 */
export function alignWords(ref, hyp) {
  const n = ref.length;
  const m = hyp.length;
  const d = Array.from({ length: n + 1 }, (_, i) => {
    const row = new Uint32Array(m + 1);
    row[0] = i;
    return row;
  });
  for (let j = 0; j <= m; j++) d[0][j] = j;
  for (let i = 1; i <= n; i++) {
    for (let j = 1; j <= m; j++) {
      d[i][j] = Math.min(d[i - 1][j - 1] + (ref[i - 1] === hyp[j - 1] ? 0 : 1), d[i - 1][j] + 1, d[i][j - 1] + 1);
    }
  }
  /** @type {{ op: 'eq'|'sub'|'del'|'ins', r?: number, h?: number }[]} */
  const ops = [];
  let i = n;
  let j = m;
  while (i > 0 || j > 0) {
    if (i > 0 && j > 0 && d[i][j] === d[i - 1][j - 1] + (ref[i - 1] === hyp[j - 1] ? 0 : 1)) {
      ops.push({ op: ref[i - 1] === hyp[j - 1] ? 'eq' : 'sub', r: i - 1, h: j - 1 });
      i--; j--;
    } else if (i > 0 && d[i][j] === d[i - 1][j] + 1) {
      ops.push({ op: 'del', r: i - 1 });
      i--;
    } else {
      ops.push({ op: 'ins', h: j - 1 });
      j--;
    }
  }
  return ops.reverse();
}

/**
 * Đoạn văn bản model đã nghe ra ở vị trí của thuật ngữ trong tham chiếu (lần xuất hiện đầu).
 * Gồm các từ khớp/thay/chèn trong khoảng thuật ngữ và các từ chèn liền kề hai bên.
 * Thuật ngữ không có trong tham chiếu ⇒ null; model bỏ hẳn ⇒ "".
 * @param {string} ref @param {string} hyp @param {string} term
 * @returns {string|null}
 */
export function heardAt(ref, hyp, term) {
  const rt = normalizeText(ref).split(' ').filter(Boolean);
  const ht = normalizeText(hyp).split(' ').filter(Boolean);
  const tt = normalizeText(term).split(' ').filter(Boolean);
  if (tt.length === 0) return null;
  let start = -1;
  for (let k = 0; k + tt.length <= rt.length; k++) {
    if (tt.every((t, x) => rt[k + x] === t)) { start = k; break; }
  }
  if (start < 0) return null;
  const end = start + tt.length - 1;
  const ops = alignWords(rt, ht);
  let i0 = ops.findIndex((o) => o.r === start);
  let i1 = ops.findLastIndex((o) => o.r === end);
  while (i0 > 0 && ops[i0 - 1].op === 'ins') i0--;
  while (i1 < ops.length - 1 && ops[i1 + 1].op === 'ins') i1++;
  return ops.slice(i0, i1 + 1).filter((o) => o.h !== undefined).map((o) => ht[/** @type {number} */ (o.h)]).join(' ');
}

/**
 * @typedef {{ name: string, ref: string, audio_ms?: number, stt_ms?: number,
 *             raw?: string, post?: string, error?: { code: string, reason?: string|null, message: string } }} ClipResult
 */

/**
 * Bắt thuật ngữ: mỗi (clip, thuật ngữ có trong tham chiếu) tính một lần. Chỉ clip thành công.
 * Sót = không có trong văn bản sau post; "nghe ra" lấy từ văn bản THÔ (thứ từ điển phải khớp).
 * @param {ClipResult[]} items @param {string[]} terms
 */
export function termReport(items, terms) {
  /** @type {Record<string, { expected: number, hit_raw: number, hit_post: number, missed: { clip: string, heard: string|null }[] }>} */
  const per = {};
  let expected = 0; let hitRaw = 0; let hitPost = 0;
  for (const it of items) {
    if (it.error || typeof it.raw !== 'string' || typeof it.post !== 'string') continue;
    for (const term of terms) {
      if (!containsTerm(it.ref, term)) continue;
      const t = (per[term] ??= { expected: 0, hit_raw: 0, hit_post: 0, missed: [] });
      t.expected++; expected++;
      if (containsTerm(it.raw, term)) { t.hit_raw++; hitRaw++; }
      if (containsTerm(it.post, term)) { t.hit_post++; hitPost++; } else t.missed.push({ clip: it.name, heard: heardAt(it.ref, it.raw, term) });
    }
  }
  const rate = (/** @type {number} */ h) => (expected === 0 ? null : h / expected);
  return { expected, hit_raw: hitRaw, hit_post: hitPost, rate_raw: rate(hitRaw), rate_post: rate(hitPost), per_term: per };
}

/**
 * Tổng hợp một model. Điểm chỉ tính trên clip thành công; số clip lỗi ghi riêng.
 * Không có clip thành công ⇒ mọi tỉ lệ là null (không xác định), không phải 0.
 * @param {ClipResult[]} items @param {string[]|null} terms
 */
export function summarizeModel(items, terms) {
  const ok = items.filter((it) => !it.error);
  const failed = items.filter((it) => it.error);
  const raw = ok.map((it) => scoreBoth(it.ref, /** @type {string} */ (it.raw)));
  const post = ok.map((it) => scoreBoth(it.ref, /** @type {string} */ (it.post)));
  const agg = (/** @type {ReturnType<typeof scoreBoth>[]} */ s) => (s.length === 0 ? null : {
    tone: aggregate(s.map((x) => x.tone)), no_tone: aggregate(s.map((x) => x.no_tone)),
  });
  const lat = ok.map((it) => /** @type {number} */ (it.stt_ms));
  const rtf = ok.filter((it) => (it.audio_ms ?? 0) > 0).map((it) => /** @type {number} */ (it.stt_ms) / /** @type {number} */ (it.audio_ms));
  const [lo, hi] = CRITERIA.band5s;
  const band = ok.filter((it) => (it.audio_ms ?? 0) >= lo && (it.audio_ms ?? 0) <= hi).map((it) => /** @type {number} */ (it.stt_ms));
  return {
    clips: items.length,
    ok: ok.length,
    failed: failed.length,
    errors: failed.map((it) => ({ clip: it.name, code: it.error?.code, reason: it.error?.reason ?? null })),
    raw: agg(raw),
    post: agg(post),
    latency_ms: { median: percentile(lat, 0.5), p95: percentile(lat, 0.95) },
    rtf: { median: percentile(rtf, 0.5), p95: percentile(rtf, 0.95) },
    latency_5s: { band_ms: [lo, hi], clips: band.length, median: percentile(band, 0.5), p95: percentile(band, 0.95) },
    audio_ms_total: ok.reduce((s, it) => s + (it.audio_ms ?? 0), 0),
    terms: terms === null ? null : termReport(items, terms),
  };
}

/**
 * Cảnh báo "KHÔNG ĐẠI DIỆN" cho bộ nhỏ, giọng tổng hợp, hoặc không rõ nguồn (thiếu set.json ⇒ synthetic null).
 * @param {{ count: number, synthetic: boolean|null, voice?: string|null }} set
 */
export function representativeness({ count, synthetic, voice = null }) {
  const reasons = [];
  if (synthetic === null) reasons.push('không có set.json: KHÔNG xác định được bộ là giọng thật hay tổng hợp');
  else if (synthetic) reasons.push(`bộ mẫu là GIỌNG TỔNG HỢP${voice ? ` (${voice})` : ''}, không phải giọng người dùng`);
  if (count < CRITERIA.minClips) reasons.push(`bộ mẫu chỉ có ${count} câu (< ${CRITERIA.minClips})`);
  return { representative: reasons.length === 0, reasons };
}

/**
 * KẾT LUẬN theo tiêu chí: WER thấp nhất (văn bản sau post, nhạy dấu thanh) trong các model
 * có RTF trung vị < 0,3 và p95 độ trễ câu ~5 s < 1,5 s, không có clip lỗi.
 * Thiếu số liệu ⇒ model "không xác định", không bao giờ coi là đạt.
 * @param {Record<string, ReturnType<typeof summarizeModel> & { load_error?: any }>} models
 * @param {{ representative: boolean, reasons: string[] }} rep
 */
export function verdict(models, rep) {
  /** @type {Record<string, { eligible: boolean, reasons: string[] }>} */
  const checks = {};
  for (const [id, s] of Object.entries(models)) {
    const reasons = [];
    if (s.load_error) reasons.push(`không chạy được (${s.load_error.code}${s.load_error.reason ? `/${s.load_error.reason}` : ''})`);
    if (s.failed > 0) reasons.push(`${s.failed}/${s.clips} clip lỗi`);
    const wer = s.post?.tone.wer.rate ?? null;
    if (wer === null) reasons.push('WER không xác định');
    if (s.rtf.median === null) reasons.push('RTF không xác định');
    else if (!(s.rtf.median < CRITERIA.rtfMax)) reasons.push(`RTF trung vị ${s.rtf.median.toFixed(3)} ≥ ${CRITERIA.rtfMax}`);
    if (s.latency_5s.p95 === null) reasons.push(`không có clip ${CRITERIA.band5s[0] / 1000}–${CRITERIA.band5s[1] / 1000} s để đo p95 độ trễ câu 5 s`);
    else if (!(s.latency_5s.p95 < CRITERIA.p95Ms5s)) reasons.push(`p95 độ trễ câu 5 s ${Math.round(s.latency_5s.p95)} ms ≥ ${CRITERIA.p95Ms5s} ms`);
    checks[id] = { eligible: reasons.length === 0, reasons };
  }
  const eligible = Object.keys(models).filter((id) => checks[id].eligible)
    .sort((a, b) => /** @type {number} */ (models[a].post?.tone.wer.rate) - /** @type {number} */ (models[b].post?.tone.wer.rate));
  const best = eligible[0] ?? null;
  let text;
  if (best === null) text = 'Không model nào đạt tiêu chí (WER thấp nhất với RTF < 0,3 và p95 độ trễ câu 5 s < 1,5 s).';
  else {
    const w = /** @type {number} */ (models[best].post?.tone.wer.rate);
    const tie = eligible.filter((id) => models[id].post?.tone.wer.rate === w);
    text = tie.length > 1
      ? `Hoà: ${tie.join(', ')} cùng WER ${pctStr(w)} và đều đạt RTF/độ trễ.`
      : `${best} đạt tiêu chí với WER thấp nhất ${pctStr(w)} (sau post, nhạy dấu thanh).`;
  }
  if (!rep.representative) text += ` KHÔNG ĐẠI DIỆN (${rep.reasons.join('; ')}): KHÔNG dùng kết luận này để chọn model mặc định.`;
  return { best: rep.representative ? best : null, best_on_this_set: best, text, checks };
}

/** @param {number|null|undefined} r */
const pctStr = (r) => (r === null || r === undefined ? 'không xác định' : `${(r * 100).toFixed(2)}%`);

/**
 * Chạy mọi model trên mọi clip. Model không tải được ⇒ ghi `load_error`, mọi clip của nó là lỗi.
 * @param {{ pairs: { name: string, wav: string, ref: string }[], models: string[],
 *           stt: { ensure: (id: string) => Promise<any>, transcribe: (id: string, input: any) => Promise<{ text: string, audio_ms: number, stt_ms: number }> },
 *           post: { process: (a: { textRaw: string, mode: string }) => Promise<{ text: string }> },
 *           readWave: (file: string) => Promise<{ samples: Float32Array, sampleRate: number }>,
 *           mode?: string, warmup?: boolean, log?: (s: string) => void }} o
 */
export async function runCompare({ pairs, models, stt, post, readWave, mode = 'normal', warmup = true, log = () => {} }) {
  /** @type {Record<string, { load_error: any, load_ms: number|null, items: ClipResult[] }>} */
  const out = {};
  for (const id of models) {
    /** @type {ClipResult[]} */
    const items = [];
    let loadError = null;
    let loadMs = null;
    const t0 = performance.now();
    try {
      await stt.ensure(id);
      loadMs = Math.round(performance.now() - t0);
    } catch (e) {
      loadError = errInfo(e);
      log(`[${id}] không tải được: ${loadError.code}${loadError.reason ? `/${loadError.reason}` : ''}`);
    }
    if (!loadError && warmup && pairs.length) {
      // Lượt khởi động (không tính số): tránh lần gọi đầu chậm vì cấp phát/kết nối.
      try { const w = await readWave(pairs[0].wav); await stt.transcribe(id, { pcm: w.samples, sampleRate: w.sampleRate }); } catch { /* clip lỗi sẽ hiện ở lượt đo */ }
    }
    for (const p of pairs) {
      if (loadError) { items.push({ name: p.name, ref: p.ref, error: loadError }); continue; }
      try {
        const w = await readWave(p.wav);
        const r = await stt.transcribe(id, { pcm: w.samples, sampleRate: w.sampleRate });
        const pp = await post.process({ textRaw: r.text, mode });
        items.push({ name: p.name, ref: p.ref, audio_ms: r.audio_ms, stt_ms: r.stt_ms, raw: r.text, post: pp.text });
      } catch (e) {
        const info = errInfo(e);
        items.push({ name: p.name, ref: p.ref, error: info });
        log(`[${id}] ${p.name}: lỗi ${info.code}${info.reason ? `/${info.reason}` : ''}`);
      }
    }
    log(`[${id}] xong ${items.filter((x) => !x.error).length}/${items.length} clip`);
    out[id] = { load_error: loadError, load_ms: loadMs, items };
  }
  return out;
}

/** @param {unknown} e */
function errInfo(e) {
  const x = /** @type {any} */ (e);
  return { code: typeof x?.code === 'string' ? x.code : 'internal', reason: typeof x?.reason === 'string' ? x.reason : null, message: String(x?.message ?? x) };
}

/**
 * Báo cáo đầy đủ (JSON) từ kết quả chạy.
 * @param {{ set: string, meta: any|null, count: number, missing_ref: string[], mode: string, dictionary: string,
 *           terms: string[]|null, runs: Awaited<ReturnType<typeof runCompare>>, host?: string, date?: string }} o
 */
export function buildReport(o) {
  // Thiếu set.json hoặc thiếu cờ ⇒ null (không xác định), KHÔNG mặc định là giọng thật.
  const synthetic = typeof o.meta?.synthetic === 'boolean' ? o.meta.synthetic : null;
  const rep = representativeness({ count: o.count, synthetic, voice: o.meta?.voice ?? null });
  /** @type {Record<string, any>} */
  const models = {};
  for (const [id, r] of Object.entries(o.runs)) {
    models[id] = { ...summarizeModel(r.items, o.terms), load_error: r.load_error, load_ms: r.load_ms };
  }
  return {
    date: o.date ?? new Date().toISOString(),
    host: o.host ?? null,
    set: o.set,
    count: o.count,
    missing_ref: o.missing_ref,
    synthetic,
    mode: o.mode,
    dictionary: o.dictionary,
    representative: rep,
    criteria: CRITERIA,
    models,
    verdict: verdict(models, rep),
    clips: Object.fromEntries(Object.entries(o.runs).map(([id, r]) => [id, r.items])),
  };
}

const ms = (/** @type {number|null} */ v) => (v === null ? 'không xác định' : `${Math.round(v)}`);
const fx = (/** @type {number|null} */ v) => (v === null ? 'không xác định' : v.toFixed(3));
const cell = (/** @type {any} */ e) => (e ? `${pctStr(e.rate)} (${e.errors}/${e.ref_len})` : 'không xác định');
const esc = (/** @type {string} */ s) => String(s).replace(/\|/g, '\\|').replace(/\n/g, ' ');

/** @param {ReturnType<typeof buildReport>} r */
export function compareMarkdown(r) {
  const ids = Object.keys(r.models);
  const L = [];
  if (!r.representative.representative) {
    L.push(`> **⚠ KHÔNG ĐẠI DIỆN** — ${r.representative.reasons.join('; ')}. Số liệu dưới đây chỉ kiểm đường ống, KHÔNG dùng để chọn model.`, '');
  }
  L.push(`# So sánh model STT — bộ \`${r.set}\``, '',
    `Ngày ${r.date}${r.host ? ` · máy ${r.host}` : ''} · ${r.count} câu · chế độ post \`${r.mode}\` · từ điển: ${r.dictionary}`, '');
  if (r.missing_ref.length) L.push(`Wav thiếu .txt (không chấm): ${r.missing_ref.join(', ')}`, '');
  L.push(`**KẾT LUẬN:** ${r.verdict.text}`, '');
  for (const id of ids) {
    const c = r.verdict.checks[id];
    L.push(`- \`${id}\`: ${c.eligible ? 'đạt điều kiện RTF/độ trễ' : `không đạt/không xác định — ${c.reasons.join('; ')}`}`);
  }
  L.push('', '## Bảng tổng hợp', '',
    `| Chỉ số | ${ids.map((id) => `\`${id}\``).join(' | ')} |`, `|---|${ids.map(() => '---:').join('|')}|`);
  const row = (/** @type {string} */ label, /** @type {(s:any)=>string} */ f) => L.push(`| ${label} | ${ids.map((id) => f(r.models[id])).join(' | ')} |`);
  row('Clip thành công / lỗi', (s) => `${s.ok}/${s.clips} · lỗi ${s.failed}`);
  row('WER thô (nhạy dấu)', (s) => cell(s.raw?.tone.wer));
  row('WER thô (không dấu thanh)', (s) => cell(s.raw?.no_tone.wer));
  row('WER sau post (nhạy dấu)', (s) => cell(s.post?.tone.wer));
  row('WER sau post (không dấu thanh)', (s) => cell(s.post?.no_tone.wer));
  row('CER thô (nhạy dấu)', (s) => cell(s.raw?.tone.cer));
  row('CER thô (không dấu thanh)', (s) => cell(s.raw?.no_tone.cer));
  row('CER sau post (nhạy dấu)', (s) => cell(s.post?.tone.cer));
  row('CER sau post (không dấu thanh)', (s) => cell(s.post?.no_tone.cer));
  row('Thuật ngữ đúng: thô', (s) => (s.terms ? `${s.terms.hit_raw}/${s.terms.expected} (${pctStr(s.terms.rate_raw)})` : 'không có terms.json'));
  row('Thuật ngữ đúng: sau post', (s) => (s.terms ? `${s.terms.hit_post}/${s.terms.expected} (${pctStr(s.terms.rate_post)})` : 'không có terms.json'));
  row('Độ trễ stt trung vị / p95 (ms)', (s) => `${ms(s.latency_ms.median)} / ${ms(s.latency_ms.p95)}`);
  row(`Độ trễ câu ${r.criteria.band5s[0] / 1000}–${r.criteria.band5s[1] / 1000} s: số clip · p95 (ms)`, (s) => `${s.latency_5s.clips} · ${ms(s.latency_5s.p95)}`);
  row('RTF trung vị / p95', (s) => `${fx(s.rtf.median)} / ${fx(s.rtf.p95)}`);
  row('Tải model (ms)', (s) => (s.load_error ? `lỗi ${s.load_error.code}${s.load_error.reason ? `/${s.load_error.reason}` : ''}` : ms(s.load_ms)));
  L.push('', 'Độ trễ stt = thời gian từ lúc gửi âm thanh tới lúc có chữ thô, đo trên máy chạy lệnh (model từ xa gồm cả mạng/tunnel), không gồm post. WER/CER = tổng lỗi / tổng độ dài tham chiếu, chỉ trên clip thành công.');

  for (const id of ids) {
    const s = r.models[id];
    if (s.errors.length) L.push('', `Clip lỗi \`${id}\`: ${s.errors.map((/** @type {any} */ e) => `${e.clip} (${e.code}${e.reason ? `/${e.reason}` : ''})`).join(', ')}`);
  }

  L.push('', '## Thuật ngữ bị sót (sau post) — model đã nghe ra gì (văn bản THÔ ở vị trí tương ứng)', '');
  const terms = new Set(ids.flatMap((id) => Object.keys(r.models[id].terms?.per_term ?? {})));
  const missRows = [];
  for (const term of terms) {
    for (const id of ids) {
      const t = r.models[id].terms?.per_term?.[term];
      if (!t || t.missed.length === 0) continue;
      /** @type {Map<string, string[]>} */
      const heard = new Map();
      for (const m of t.missed) {
        const k = m.heard === null ? '(không định vị được)' : m.heard === '' ? '∅ (bỏ mất)' : m.heard;
        heard.set(k, [...(heard.get(k) ?? []), m.clip]);
      }
      missRows.push(`| ${esc(term)} | \`${id}\` | ${t.missed.length}/${t.expected} | ${[...heard].map(([k, c]) => `${esc(k)} (${c.join(',')})`).join('; ')} |`);
    }
  }
  if (missRows.length) L.push('| Thuật ngữ | Model | Sót | Nghe ra (clip) |', '|---|---|---:|---|', ...missRows);
  else L.push('Không có thuật ngữ nào bị sót (hoặc không có số liệu thuật ngữ).');

  L.push('', '## Từng clip', '');
  for (const id of ids) {
    L.push(`### \`${id}\``, '', '| Clip | ms âm thanh | ms stt | Thô | Sau post |', '|---|---:|---:|---|---|');
    for (const it of r.clips[id]) {
      L.push(it.error
        ? `| ${it.name} | — | — | LỖI ${esc(it.error.code)}${it.error.reason ? `/${esc(it.error.reason)}` : ''} | — |`
        : `| ${it.name} | ${it.audio_ms} | ${it.stt_ms} | ${esc(/** @type {string} */ (it.raw))} | ${esc(/** @type {string} */ (it.post))} |`);
    }
    L.push('');
  }
  return L.join('\n');
}

/** Đọc `set.json` của bộ (nếu có). Hỏng ⇒ ném lỗi (không đoán là giọng thật). @param {string} dir */
export async function readSetMeta(dir) {
  try {
    return JSON.parse(await fsp.readFile(path.join(dir, 'set.json'), 'utf8'));
  } catch (e) {
    if (/** @type {any} */ (e).code === 'ENOENT') return null;
    throw new Error(`${path.join(dir, 'set.json')} hỏng: ${/** @type {Error} */ (e).message}`);
  }
}
