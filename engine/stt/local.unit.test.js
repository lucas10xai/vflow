/** Test thuần (không cần sherpa-onnx/model thật) cho các hàm hỗ trợ của provider cục bộ. */
import { test } from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { normalizeModelText, createLocalProvider } from './local.js';

test('normalizeModelText: engine transducer thô (zipformer) ⇒ đổi về chữ thường', () => {
  assert.equal(normalizeModelText('ANH ĐI DEPLOY', true), 'anh đi deploy');
  assert.equal(normalizeModelText('  nhiều   khoảng   trắng  ', true), 'nhiều khoảng trắng');
});

test('normalizeModelText: Whisper đã tự viết hoa/dấu câu ⇒ GIỮ NGUYÊN, cả với câu tiếng Việt', () => {
  // Bug đã gặp: hàm cũ khoá theo "language" yêu cầu (vi/en/…) thay vì theo loại engine, nên một
  // câu tiếng Việt do Whisper trả về (đã viết hoa, có dấu câu đúng) bị ép về chữ thường mất hết.
  assert.equal(normalizeModelText('Anh đi deploy bản mới nhé.', false), 'Anh đi deploy bản mới nhé.');
  assert.equal(normalizeModelText('Please review the PR.', false), 'Please review the PR.');
  // Vẫn gọn khoảng trắng dù giữ hoa/thường.
  assert.equal(normalizeModelText('  Hello   World.  ', false), 'Hello World.');
});

test('normalizeModelText: mặc định (không truyền cờ) là transducer thô, dùng cho đường streaming', () => {
  assert.equal(normalizeModelText('XIN CHÀO'), 'xin chào');
});

/** Thư mục model whisper giả (tệp rỗng, không cần sherpa-onnx thật) để test tham số nạp model. */
function fakeWhisperHome() {
  const home = fs.mkdtempSync(path.join(os.tmpdir(), 'vflow-local-whisper-'));
  const dir = path.join(home, 'models', 'whisper-tiny-multilingual');
  fs.mkdirSync(dir, { recursive: true });
  for (const n of ['encoder.onnx', 'decoder.onnx', 'tokens.txt']) fs.writeFileSync(path.join(dir, n), 'x');
  fs.writeFileSync(path.join(dir, 'manifest.json'), JSON.stringify({
    files: {
      encoder: { path: 'encoder.onnx' }, decoder: { path: 'decoder.onnx' }, tokens: { path: 'tokens.txt' },
    },
  }));
  return home;
}

/** Recognizer giả: ghi lại `modelConfig.whisper.language` mỗi lần được tạo (mỗi lần NẠP/nạp lại). */
function fakeWhisperSherpa(loadedLanguages) {
  return () => ({
    OfflineRecognizer: {
      createAsync: async (config) => {
        loadedLanguages.push(config.modelConfig.whisper.language);
        return {
          createStream: () => ({ acceptWaveform() {} }),
          decodeAsync: async () => ({ text: 'stub' }),
        };
      },
    },
  });
}

test('createLocalProvider (whisper): stt_language=vi|en dẫn tới đúng tham số nạp model; "auto" chỉ truyền chuỗi rỗng, KHÔNG BAO GIỜ chữ "auto"; không nạp lại khi ngôn ngữ không đổi', async (t) => {
  // Bug đã gặp (eval/reports/2026-10-30-multilingual.md mục "Phát hiện ở tầng engine hiện tại"):
  // local.js LUÔN nạp Whisper với language:'' bất kể stt_language ⇒ tham số vi/en/auto không có
  // tác dụng gì qua API thật. Test này phải THẤY các giá trị language KHÁC NHAU được nạp tuỳ
  // stt_language; trước khi sửa, mảng `loadedLanguages` toàn là '' nên assertion dưới sẽ đỏ.
  const home = fakeWhisperHome();
  t.after(() => fs.rmSync(home, { recursive: true, force: true }));
  const loadedLanguages = [];
  const p = createLocalProvider({ home, sherpa: fakeWhisperSherpa(loadedLanguages) });

  await p.loadModel('whisper-tiny-multilingual');
  assert.deepEqual(loadedLanguages, [''], 'nạp lần đầu (chưa biết stt_language) dùng chuỗi rỗng an toàn làm mặc định');

  const input = (language) => ({ pcm: new Float32Array(16), sampleRate: 16000, language });

  await p.transcribe(input('vi'));
  assert.deepEqual(loadedLanguages, ['', 'vi'], 'stt_language=vi ⇒ nạp lại với language sherpa-onnx = "vi"');

  await p.transcribe(input('vi'));
  assert.deepEqual(loadedLanguages, ['', 'vi'], 'vẫn stt_language=vi ⇒ KHÔNG nạp lại (không nạp lại mỗi câu)');

  await p.transcribe(input('en'));
  assert.deepEqual(loadedLanguages, ['', 'vi', 'en'], 'stt_language=en ⇒ nạp lại với language = "en"');

  await p.transcribe(input('auto'));
  assert.deepEqual(loadedLanguages, ['', 'vi', 'en', ''], 'stt_language=auto ⇒ nạp lại với language = "" (map sang chuỗi rỗng)');
  assert.ok(!loadedLanguages.includes('auto'), 'BẪY ĐÃ BIẾT: literal "auto" khiến addon thật gọi SHERPA_ONNX_EXIT và tắt tiến trình Node — không bao giờ được truyền xuống sherpa-onnx');

  await p.transcribe(input('vi'));
  assert.deepEqual(loadedLanguages, ['', 'vi', 'en', '', 'vi'], 'đổi lại vi sau auto ⇒ nạp lại một lần nữa');
});
