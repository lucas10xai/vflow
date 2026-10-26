// GET /v1/diagnostics (item 3, contract/engine-api.md mục "Chẩn đoán"): trạng thái gọn để debug,
// KHÔNG BAO GIỜ chứa token/khoá 9Router hay văn bản người dùng (dictation). `settings` phải là kết
// quả settings.get() (schema cố định của engine/post/settings.js không có khoá bí mật nào — không
// cần lọc lại ở đây). `recentErrors` chỉ là {at,route,status,code} (không có message tự do).
import { homedir } from 'node:os';

/** Rút gọn mọi đường dẫn dưới `home`/homedir xuất hiện trong `message` thành "~". */
export function redactPaths(message, home) {
  if (typeof message !== 'string') return message;
  let out = message;
  if (home) out = out.split(home).join('~');
  const hd = homedir();
  if (hd && hd !== home) out = out.split(hd).join('~');
  return out;
}

/**
 * @param {{ version: string, node: string, platform: string, uptimeS: number,
 *           models: unknown[], defaultModel: string, settings: Record<string, unknown>,
 *           counts: { dictionary: number, snippets: number, history: number, stats_days: number },
 *           homeBasename: string|null,
 *           recentErrors: { at: string, route: string, status: number, code: string }[],
 *           home?: string }} args
 */
export function buildDiagnostics({ version, node, platform, uptimeS, models, defaultModel, settings, counts, homeBasename, recentErrors, home }) {
  return {
    engine_version: version,
    node,
    platform,
    uptime_s: uptimeS,
    model: { default: defaultModel, status: models },
    stt: { default: defaultModel },
    settings,
    counts,
    paths: { home_basename: homeBasename },
    recent_errors: recentErrors.slice(-50).map((e) => ({ ...e, route: redactPaths(e.route, home) })),
  };
}
