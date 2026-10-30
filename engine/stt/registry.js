/**
 * Danh mục model STT mà vflow biết. Nguồn và checksum ghi rõ để `models pull` kiểm được.
 */
import os from 'node:os';
import path from 'node:path';

/**
 * @typedef {{
 *   name: string, url: string, saveAs?: string,
 *   sha256: string|null, sha256Source: string|null, size?: number,
 * }} SourceFile
 * @typedef {{
 *   id: string, kind: 'local', engine: 'offline-transducer'|'online-transducer'|'whisper'|'sense-voice',
 *   title: string, license: string, homepage: string,
 *   source: { type: 'archive', file: SourceFile, root: string } | { type: 'files', files: SourceFile[] },
 *   files: Record<string, RegExp>, languages?: string[], autoDetect?: boolean,
 *   keepDirs?: string[],
 * }} LocalModelSpec
 * @typedef {{ id: string, kind: 'remote', title: string, configKey: string, defaultUrl: string }} RemoteModelSpec
 */

const SHERPA_RELEASE = 'https://github.com/k2-fsa/sherpa-onnx/releases/download/asr-models';
const HF_STREAMING_REV = 'c122fdc21cea4894fd775e9d3fe66ebbc787e26b';
const HF_STREAMING = `https://huggingface.co/hynt/Zipformer-30M-RNNT-Streaming-6000h/resolve/${HF_STREAMING_REV}`;

/** @type {LocalModelSpec[]} */
export const LOCAL_MODELS = [
  {
    id: 'zipformer-vi-30m',
    kind: 'local',
    engine: 'offline-transducer',
    title: 'Zipformer-30M-RNNT-6000h (sherpa-onnx, int8)',
    license: 'CC-BY-NC-ND-4.0 (theo model gốc hynt/Zipformer-30M-RNNT-6000h trên Hugging Face)',
    homepage: 'https://k2-fsa.github.io/sherpa/onnx/pretrained_models/offline-transducer/zipformer-transducer-models.html',
    source: {
      type: 'archive',
      root: 'sherpa-onnx-zipformer-vi-30M-int8-2026-02-09',
      file: {
        name: 'sherpa-onnx-zipformer-vi-30M-int8-2026-02-09.tar.bz2',
        url: `${SHERPA_RELEASE}/sherpa-onnx-zipformer-vi-30M-int8-2026-02-09.tar.bz2`,
        size: 26442384,
        // Digest do GitHub công bố cho asset của release `asr-models` (API releases, trường `digest`).
        sha256: 'da8b637947091829d7ee9eda23da2a4ec7caa399233a3f4e34eb719fb2ea6b9b',
        sha256Source: 'github-release-asset-digest',
      },
    },
    files: { encoder: /^encoder.*\.onnx$/, decoder: /^decoder.*\.onnx$/, joiner: /^joiner.*\.onnx$/, tokens: /^tokens\.txt$/ },
    keepDirs: ['test_wavs'],
  },
  {
    id: 'zipformer-vi-30m-streaming',
    kind: 'local',
    engine: 'online-transducer',
    title: 'Zipformer-30M-RNNT-Streaming-6000h chunk-32 (ONNX fp16 do tác giả xuất, không phải gói sherpa-onnx)',
    license: 'CC-BY-NC-ND-4.0 (hynt/Zipformer-30M-RNNT-Streaming-6000h)',
    homepage: 'https://huggingface.co/hynt/Zipformer-30M-RNNT-Streaming-6000h',
    source: {
      type: 'files',
      files: [
        {
          name: 'encoder-epoch-31-avg-11-chunk-32-left-128.fp16.onnx',
          url: `${HF_STREAMING}/encoder-epoch-31-avg-11-chunk-32-left-128.fp16.onnx`,
          size: 46172538,
          sha256: '49577079b22ace4ade7a994743279ce9128c92803dd04b5e7ead809a30107358',
          sha256Source: 'huggingface-lfs-oid',
        },
        {
          name: 'decoder-epoch-31-avg-11-chunk-32-left-128.fp16.onnx',
          url: `${HF_STREAMING}/decoder-epoch-31-avg-11-chunk-32-left-128.fp16.onnx`,
          size: 2584449,
          sha256: '12274189a3ef638905e0d966a4f1ab090c96447f165190c4aa6b8053ac49b014',
          sha256Source: 'huggingface-lfs-oid',
        },
        {
          name: 'joiner-epoch-31-avg-11-chunk-32-left-128.fp16.onnx',
          url: `${HF_STREAMING}/joiner-epoch-31-avg-11-chunk-32-left-128.fp16.onnx`,
          size: 2052891,
          sha256: '54f469ec6841deca336e33808514640be9bc1cb222dedfda312cdb2155ae37df',
          sha256Source: 'huggingface-lfs-oid',
        },
        {
          // Trên repo gốc, bảng token (định dạng tokens.txt) mang tên config.json và không phải tệp LFS,
          // nên upstream không công bố sha256: hash dưới đây do vflow tự tính ở revision cố định.
          name: 'config.json',
          saveAs: 'tokens.txt',
          url: `${HF_STREAMING}/config.json`,
          size: 23238,
          sha256: 'ca8171f8bbd516c050b627582f2125c8f5f1f6ed967ab41b0fa9aae2cf61b492',
          sha256Source: 'vflow-pinned (không có checksum gốc)',
        },
      ],
    },
    files: { encoder: /^encoder.*\.onnx$/, decoder: /^decoder.*\.onnx$/, joiner: /^joiner.*\.onnx$/, tokens: /^tokens\.txt$/ },
  },
  {
    id: 'whisper-tiny-multilingual', kind: 'local', engine: 'whisper',
    title: 'Whisper tiny đa ngôn ngữ (sherpa-onnx, CPU)', license: 'MIT (OpenAI Whisper)',
    homepage: 'https://k2-fsa.github.io/sherpa/onnx/pretrained_models/whisper/tiny.html',
    languages: ['vi', 'en', 'ja', 'ko', 'zh', 'fr', 'de', 'es', 'th'], autoDetect: true,
    source: { type: 'archive', root: 'sherpa-onnx-whisper-tiny', file: {
      name: 'sherpa-onnx-whisper-tiny.tar.bz2', url: `${SHERPA_RELEASE}/sherpa-onnx-whisper-tiny.tar.bz2`, size: 116204861,
      // GitHub không công bố digest cho asset này (đã kiểm qua API releases, trường `digest` = null).
      // vflow tự tải và băm ở revision ghim trên (xem báo cáo E5); không có checksum gốc để đối chiếu.
      sha256: 'c46116994e539aa165266d96b325252728429c12535eb9d8b6a2b10f129e66b1',
      sha256Source: 'vflow-pinned (không có checksum gốc)',
    } },
    files: { encoder: /encoder.*\.onnx$/, decoder: /decoder.*\.onnx$/, tokens: /tokens\.txt$/ },
    keepDirs: ['test_wavs'],
  },
  {
    id: 'sense-voice-multilingual', kind: 'local', engine: 'sense-voice',
    title: 'SenseVoice zh/en/ja/ko/yue (sherpa-onnx, CPU)', license: 'Apache-2.0 (FunASR SenseVoice)',
    homepage: 'https://k2-fsa.github.io/sherpa/onnx/sense-voice/pretrained.html',
    languages: ['en', 'ja', 'ko', 'zh', 'yue'], autoDetect: true,
    source: { type: 'archive', root: 'sherpa-onnx-sense-voice-zh-en-ja-ko-yue-2024-07-17', file: {
      name: 'sherpa-onnx-sense-voice-zh-en-ja-ko-yue-2024-07-17.tar.bz2', url: `${SHERPA_RELEASE}/sherpa-onnx-sense-voice-zh-en-ja-ko-yue-2024-07-17.tar.bz2`, size: 1047870769,
      // GitHub không công bố digest (đã kiểm qua API releases). Gói ~1 GB: vượt giới hạn RAM/thời
      // gian an toàn để tự tải và băm trong phiên này (xem báo cáo E5) ⇒ chưa có checksum đã xác
      // minh. `models pull` phải từ chối model này cho đến khi ai đó tải và ghim hash thật.
      sha256: null, sha256Source: 'upstream_digest_unavailable',
    } },
    files: { model: /^model.*\.onnx$/, tokens: /tokens\.txt$/ },
  },
];

/** @type {RemoteModelSpec[]} */
export const REMOTE_MODELS = [
  {
    id: 'phowhisper-large',
    kind: 'remote',
    title: 'PhoWhisper-large trên gpu-host (qua SSH tunnel)',
    configKey: 'phowhisper',
    defaultUrl: 'http://127.0.0.1:7612',
  },
];

export const DEFAULT_MODEL = 'zipformer-vi-30m';

/** @param {string} id */
export function findModel(id) {
  return LOCAL_MODELS.find((m) => m.id === id) ?? REMOTE_MODELS.find((m) => m.id === id) ?? null;
}

/**
 * Model cục bộ chỉ được `models pull` khi MỌI tệp nguồn có sha256 đã biết (gốc upstream hoặc
 * vflow tự băm và ghim). Thiếu checksum ⇒ không tải, để không bỏ qua kiểm toàn vẹn.
 * @param {LocalModelSpec} spec
 */
export function hasVerifiedChecksum(spec) {
  const files = spec.source.type === 'archive' ? [spec.source.file] : spec.source.files;
  return files.every((f) => typeof f.sha256 === 'string' && f.sha256.length > 0);
}

export const ALL_MODEL_IDS = [...LOCAL_MODELS, ...REMOTE_MODELS].map((m) => m.id);

/** @param {NodeJS.ProcessEnv} [env] */
export function vflowHome(env = process.env) {
  return env.VFLOW_HOME ? path.resolve(env.VFLOW_HOME) : path.join(os.homedir(), '.vflow');
}

/** @param {string} home @param {string} id */
export const modelDir = (home, id) => path.join(home, 'models', id);
