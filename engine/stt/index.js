/**
 * Bộ quản lý STT: chọn provider theo id model, tải lười, báo trạng thái cho /healthz.
 * Model yêu cầu không dùng được ⇒ `model_unavailable` có lý do; KHÔNG tự chuyển sang model khác.
 */
import { DEFAULT_MODEL, LOCAL_MODELS, REMOTE_MODELS, findModel } from './registry.js';
import { createLocalProvider, loadSherpa } from './local.js';
import { createRemoteProvider } from './remote.js';
import { resolveModelFiles } from './models.js';
import { SttError } from './errors.js';

export { SttError } from './errors.js';
export { DEFAULT_MODEL, ALL_MODEL_IDS, vflowHome } from './registry.js';

/**
 * @param {{ home: string, config?: any, env?: NodeJS.ProcessEnv, fetchImpl?: typeof fetch,
 *           sherpa?: () => any, numThreads?: number,
 *           providerFactory?: (id: string) => any }} opts
 *   `providerFactory` thay provider thật (dùng trong test server).
 */
export function createStt({ home, config = {}, env = process.env, fetchImpl, sherpa = loadSherpa, numThreads, providerFactory }) {
  /** @type {Map<string, any>} */
  const providers = new Map();
  /** @type {Map<string, Promise<any>>} */
  const loading = new Map();
  /** @type {Map<string, {reason:string, message:string}>} */
  const lastError = new Map();

  const defaultModel = typeof config.default_model === 'string' ? config.default_model : DEFAULT_MODEL;

  /** @param {string} id */
  function providerFor(id) {
    let p = providers.get(id);
    if (p) return p;
    if (providerFactory) {
      p = providerFactory(id);
    } else {
      const spec = findModel(id);
      if (!spec) return null;
      if (spec.kind === 'local') {
        p = createLocalProvider({ home, sherpa, ...(numThreads ? { numThreads } : {}) });
      } else {
        const url = config?.remote?.[spec.configKey]?.url ?? spec.defaultUrl;
        p = createRemoteProvider({ id, url, token: env.VFLOW_REMOTE_TOKEN || null, fetchImpl });
      }
    }
    if (p) providers.set(id, p);
    return p;
  }

  /** @param {string} id */
  async function ensure(id) {
    const p = providerFor(id);
    if (!p) throw new SttError('bad_request', `Không có model "${id}".`);
    if (p.loaded) return p;
    let pending = loading.get(id);
    if (!pending) {
      pending = p.loadModel(id).then(
        () => { lastError.delete(id); return p; },
        (err) => {
          lastError.set(id, { reason: err?.reason ?? 'load_failed', message: err?.message ?? String(err) });
          throw err;
        },
      ).finally(() => loading.delete(id));
      loading.set(id, pending);
    }
    return pending;
  }

  return {
    defaultModel,
    /** @param {string} id */
    isKnown: (id) => providerFor(id) !== null,
    ensure,

    /**
     * @param {string} id
     * @param {{ pcm: Int16Array|Float32Array, sampleRate: number }} input
     */
    async transcribe(id, input) {
      const p = await ensure(id);
      return p.transcribe(input);
    },

    /** Trạng thái từng model; `loaded:false` luôn kèm `reason`. */
    async status() {
      const out = [];
      for (const spec of LOCAL_MODELS) {
        const p = providers.get(spec.id);
        if (p?.loaded) { out.push({ id: spec.id, kind: 'local', loaded: true }); continue; }
        const err = lastError.get(spec.id);
        if (err) { out.push({ id: spec.id, kind: 'local', loaded: false, reason: err.reason }); continue; }
        try {
          await resolveModelFiles(home, spec.id);
          out.push({ id: spec.id, kind: 'local', loaded: false, reason: 'not_loaded' });
        } catch (e) {
          out.push({ id: spec.id, kind: 'local', loaded: false, reason: /** @type {any} */ (e).reason ?? 'internal' });
        }
      }
      for (const spec of REMOTE_MODELS) {
        if (!env.VFLOW_REMOTE_TOKEN && !providerFactory) {
          out.push({ id: spec.id, kind: 'remote', loaded: false, reason: 'missing_token' });
          continue;
        }
        // Thăm dò /healthz từ xa (timeout ngắn) để báo đúng tình trạng tunnel.
        try {
          await providerFor(spec.id).loadModel(spec.id);
          out.push({ id: spec.id, kind: 'remote', loaded: true });
        } catch (e) {
          out.push({ id: spec.id, kind: 'remote', loaded: false, reason: /** @type {any} */ (e)?.reason ?? 'internal' });
        }
      }
      return out;
    },
  };
}
