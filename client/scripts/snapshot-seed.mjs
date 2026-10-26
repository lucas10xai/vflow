#!/usr/bin/env node
// Tạo dữ liệu MẪU (không tên riêng, không khoá thật) cho một VFLOW_HOME cô lập dùng bởi
// `client/scripts/snapshot.sh` — lịch sử nhiều ngày, từ điển, snippets, client.json trỏ repo.
// KHÔNG đụng ~/.vflow thật; không ghi khoá/token thật nào (token do engine tự sinh khi `serve`).
import { mkdirSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';

const [, , vflowHome, repoDir] = process.argv;
if (!vflowHome || !repoDir) {
  console.error('dùng: snapshot-seed.mjs <VFLOW_HOME> <repoDir>');
  process.exit(64);
}
mkdirSync(vflowHome, { recursive: true });

writeFileSync(join(vflowHome, 'client.json'), JSON.stringify({ repo: repoDir, port: 7611 }, null, 2) + '\n');

const dictionary = {
  entries: [
    { term: 'deploy', spoken: ['đi plôi', 'đì ploi'], kind: 'term', uses: 12, last_used: new Date(Date.now() - 2 * 3600_000).toISOString() },
    { term: 'commit', spoken: ['cơ mít'], kind: 'term', uses: 8, last_used: new Date(Date.now() - 86_400_000).toISOString() },
    { term: 'worktree', spoken: ['guốc chi'], kind: 'term', uses: 3, last_used: null },
    { term: 'Orca', spoken: ['oa ca'], kind: 'term', uses: 5, last_used: new Date(Date.now() - 3 * 86_400_000).toISOString() },
  ],
};
writeFileSync(join(vflowHome, 'dictionary.json'), JSON.stringify(dictionary, null, 2) + '\n');

const snippets = {
  entries: [
    { trigger: 'link lịch hẹn', text: 'https://cal.example.com/demo-slot', uses: 3, last_used: new Date(Date.now() - 86_400_000).toISOString() },
    { trigger: 'chữ ký email', text: 'Thân mến,\nvflow demo', uses: 1, last_used: null },
  ],
};
writeFileSync(join(vflowHome, 'snippets.json'), JSON.stringify(snippets, null, 2) + '\n');

// Lịch sử nhiều ngày (hôm nay, hôm qua, 3 ngày trước) — chỉ văn bản, KHÔNG âm thanh (bất biến
// contract/engine-api.md) — khớp định dạng `HistoryStore.encode` (client/Sources/VFlowCore/History.swift).
const now = Date.now();
const day = 86_400_000;

// Gợi ý từ điển mẫu (V2, `GET /v1/dictionary/suggestions`) — khớp định dạng
// `engine/post/learn.js` (`createCorrectionsStore`): mỗi cặp (term, spoken) cần ≥ 2 mục
// trong `entries[]` để tính là "đủ gặp" và CHƯA có trong `dictionary.json` ở trên.
const corrections = {
  version: 1,
  entries: [
    { term: 'Supabase', spoken: 'xu pa bết', at: new Date(now - 2 * day).toISOString() },
    { term: 'Supabase', spoken: 'xu pa bết', at: new Date(now - day).toISOString() },
    { term: 'Supabase', spoken: 'xu pa bết', at: new Date(now - 3600_000).toISOString() },
  ],
  dismissed: [],
};
writeFileSync(join(vflowHome, 'corrections.json'), JSON.stringify(corrections, null, 2) + '\n');
const sample = [
  { offset: 0, mode: 'normal', text: 'Deploy nhánh main lên môi trường staging trước khi họp chiều nay.' },
  { offset: 1 * 3600_000, mode: 'clean', text: 'Nhắc An review pull request trước mười hai giờ trưa.' },
  { offset: day, mode: 'dev', text: 'git_commit_message viết ngắn gọn súc tích.' },
  { offset: day + 2 * 3600_000, mode: 'tidy', text: 'Danh sách việc cần làm hôm nay gồm ba việc chính.' },
  { offset: 3 * day, mode: 'email', text: 'Xin chào, tôi gửi kèm bản tổng hợp tiến độ tuần này.' },
];
const lines = sample.map((s, i) => JSON.stringify({
  id: `h_demo_${i}`,
  at: new Date(now - s.offset).toISOString(),
  mode: s.mode,
  model: 'zipformer-vi-30m',
  text_raw: s.text,
  text: s.text,
  audio_ms: 3000 + i * 500,
  total_ms: 400 + i * 50,
}));
writeFileSync(join(vflowHome, 'history.jsonl'), lines.join('\n') + '\n');

// Thống kê mẫu (V2, client/Sources/VFlow/StatsView.swift) — ~16 tuần (112 ngày) kết thúc HÔM NAY,
// mức hoạt động đa dạng (có ngày 0, thấp, cao, một chuỗi dài) + vài ứng dụng: Safari/Slack thật
// (bundle id đúng), "Zalo" CHỈ là chuỗi minh hoạ hợp lệ reverse-DNS (chưa xác minh đúng bundle id
// Zalo macOS thật — không quan trọng cho ảnh chụp: không cài app đó thì client tự rơi về biểu
// tượng chung, đúng hành vi thật) + "unknown" (app không xác định, theo contract mục Thống kê).
// Định dạng PHẢI khớp `engine/post/stats.js` (`createStatsStore`): `{version,backfilled,days:{
// "YYYY-MM-DD": {words,audio_ms,count,apps:{"<bundleId>":{words,count}}}}}`. Đây là tệp RIÊNG của
// stats (không phải history.jsonl) — nếu thiếu, engine tự backfill từ history.jsonl ở lần chạy đầu;
// ghi sẵn ở đây để ảnh chụp có đủ 16 tuần đa dạng (history mẫu phía trên chỉ có 5 dòng, không đủ).
const STATS_WEEKS = 16;
const STATS_DAYS = STATS_WEEKS * 7;
const APPS = ['com.apple.Safari', 'com.tinyspeck.slackmacgap', 'com.zalo.ZaloApp', 'unknown'];
// LCG nhỏ, seed cố định — "đa dạng" nhưng LẶP LẠI giống nhau mỗi lần chạy (ảnh chụp ổn định để so sánh).
let seed = 20261027;
function rand() {
  seed = (seed * 1103515245 + 12345) & 0x7fffffff;
  return seed / 0x7fffffff;
}
const statsDays = {};
// Nửa đêm THEO ĐỊA PHƯƠNG (không phải UTC) — khớp `dayKey()` (dùng getFullYear/Month/Date local),
// tránh lệch một ngày ở múi giờ sớm hơn UTC (vd. Mỹ) khi cắt theo UTC thay vì local.
const nowLocal = new Date(now);
const todayStart = new Date(nowLocal.getFullYear(), nowLocal.getMonth(), nowLocal.getDate());
// Một chuỗi dài 12 ngày liên tiếp có nói (best_streak) ở tuần thứ 6 kể từ hôm nay (xa chuỗi hiện tại).
const longStreakStartOffsetDays = 6 * 7 + 2;
for (let offset = STATS_DAYS - 1; offset >= 0; offset--) {
  const d = new Date(todayStart.getTime() - offset * day);
  const key = dayKey(d);
  const isRecent5 = offset <= 4; // 5 ngày gần nhất (gồm hôm nay): luôn có nói ⇒ current_streak = 5.
  const inLongStreak = offset >= longStreakStartOffsetDays && offset < longStreakStartOffsetDays + 12;
  const active = isRecent5 || inLongStreak || rand() < 0.55;
  if (!active) {
    statsDays[key] = { words: 0, audio_ms: 0, count: 0, apps: {} };
    continue;
  }
  const sentences = 1 + Math.floor(rand() * 4);
  const words = sentences * (8 + Math.floor(rand() * 25));
  const audioMs = Math.round((words / 2) * 1000); // ~120 wpm cố định, xem ghi chú ở trên.
  const apps = {};
  let remainingWords = words;
  let remainingCount = sentences;
  const appCount = 1 + Math.floor(rand() * Math.min(3, APPS.length));
  const chosen = [...APPS].sort(() => rand() - 0.5).slice(0, appCount);
  for (let i = 0; i < chosen.length; i++) {
    const last = i === chosen.length - 1;
    const w = last ? remainingWords : Math.max(1, Math.round(remainingWords * (0.3 + rand() * 0.4)));
    const c = last ? remainingCount : Math.max(1, Math.round(remainingCount * (0.3 + rand() * 0.4)));
    apps[chosen[i]] = { words: Math.min(w, remainingWords), count: Math.min(c, remainingCount) };
    remainingWords -= apps[chosen[i]].words;
    remainingCount -= apps[chosen[i]].count;
    if (remainingWords <= 0 || remainingCount <= 0) break;
  }
  statsDays[key] = { words, audio_ms: audioMs, count: sentences, apps };
}
function dayKey(d) {
  const y = d.getFullYear();
  const m = String(d.getMonth() + 1).padStart(2, '0');
  const dd = String(d.getDate()).padStart(2, '0');
  return `${y}-${m}-${dd}`;
}
writeFileSync(join(vflowHome, 'stats.json'), JSON.stringify({ version: 1, backfilled: true, days: statsDays }, null, 2) + '\n');

console.log(`VFLOW_SNAPSHOT_SEED_OK ${vflowHome}`);
