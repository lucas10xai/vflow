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

console.log(`VFLOW_SNAPSHOT_SEED_OK ${vflowHome}`);
