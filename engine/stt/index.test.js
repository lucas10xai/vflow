import { test } from 'node:test';
import assert from 'node:assert/strict';
import { createStt } from './index.js';

/** Provider giả: không tải sherpa thật, chỉ ghi lại được gọi hay không. */
function fakeFactory(calls) {
  return (id) => ({
    loaded: false,
    async loadModel() { this.loaded = true; calls.push({ id, event: 'load' }); },
    async transcribe(input) { calls.push({ id, event: 'transcribe', language: input.language }); return { text: 'ok', audio_ms: 1, stt_ms: 1 }; },
  });
}

test('createStt.transcribe: kiểm năng lực ngôn ngữ theo registry TRƯỚC khi tải model, áp cho mọi provider', async () => {
  const calls = [];
  const stt = createStt({ home: '/khong-dung-toi', providerFactory: fakeFactory(calls) });
  const input = (language) => ({ pcm: new Float32Array(1), sampleRate: 16000, language });

  // zipformer-vi-30m: đơn ngữ, không autoDetect ⇒ chỉ "vi" được nhận.
  await assert.rejects(stt.transcribe('zipformer-vi-30m', input('en')), { code: 'bad_request' });
  await assert.rejects(stt.transcribe('zipformer-vi-30m', input('auto')), { code: 'bad_request' });
  assert.deepEqual(calls, [], 'ngôn ngữ sai ⇒ không được tải model hay gọi provider (fail fast)');
  await stt.transcribe('zipformer-vi-30m', input('vi'));
  assert.deepEqual(calls.map((c) => c.event), ['load', 'transcribe']);

  // whisper-tiny-multilingual: nhiều ngôn ngữ + autoDetect ⇒ auto và các mã đã khai được nhận.
  calls.length = 0;
  await stt.transcribe('whisper-tiny-multilingual', input('en'));
  await stt.transcribe('whisper-tiny-multilingual', input('auto'));
  await assert.rejects(stt.transcribe('whisper-tiny-multilingual', input('th-TH')), { code: 'bad_request' }, 'mã ngôn ngữ không có trong danh sách phải bị chặn');

  // Model không có trong registry (vd provider tuỳ ý trong test khác) ⇒ coi như chỉ nói "vi".
  await assert.rejects(stt.transcribe('tuy-y-khong-co-trong-registry', input('en')), { code: 'bad_request' });
  await stt.transcribe('tuy-y-khong-co-trong-registry', input('vi'));
  await stt.transcribe('tuy-y-khong-co-trong-registry', input(undefined));
});
