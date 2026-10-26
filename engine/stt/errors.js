/**
 * Lỗi có mã theo bảng trong contract/engine-api.md.
 * `reason` là mã ngắn (snake_case) giải thích nguyên nhân, ví dụ `not_downloaded`.
 */
export class SttError extends Error {
  /**
   * @param {'bad_audio'|'bad_request'|'model_unavailable'|'timeout'|'payload_too_large'|'internal'} code
   * @param {string} message thông báo tiếng Việt
   * @param {{reason?: string, cause?: unknown}} [extra]
   */
  constructor(code, message, extra = {}) {
    super(message, extra.cause === undefined ? undefined : { cause: extra.cause });
    this.name = 'SttError';
    this.code = code;
    /** @type {string|undefined} */
    this.reason = extra.reason;
  }
}

/** @param {string} message */
export const badAudio = (message) => new SttError('bad_audio', message);

/**
 * @param {string} reason
 * @param {string} message
 * @param {unknown} [cause]
 */
export const modelUnavailable = (reason, message, cause) =>
  new SttError('model_unavailable', message, { reason, cause });
