"""Chuyển vinai/PhoWhisper-* (pytorch_model.bin fp32) sang CTranslate2 float16 với RAM đỉnh thấp.

Bước 1: mmap state dict -> ép fp16 -> lưu safetensors (không nạp cả model fp32 vào RAM).
Bước 2: ct2 TransformersConverter đọc bản fp16 -> thư mục CT2 float16.

  venv/bin/python -B convert.py <thư mục HF gốc> <thư mục fp16 tạm> <thư mục CT2 đích>
"""

import resource
import shutil
import sys
from pathlib import Path

import torch
from safetensors.torch import save_file

src, mid, dst = (Path(p) for p in sys.argv[1:4])
mid.mkdir(parents=True, exist_ok=True)
if not (mid / "model.safetensors").exists():
    state = torch.load(src / "pytorch_model.bin", map_location="cpu", mmap=True, weights_only=True)
    half = {k: v.to(torch.float16).contiguous() for k, v in state.items()}
    del state
    # proj_out dùng chung trọng số với embed_tokens; safetensors không cho lưu tensor chung.
    half.pop("proj_out.weight", None)
    save_file(half, str(mid / "model.safetensors"), metadata={"format": "pt"})
    del half
    for f in src.iterdir():
        if f.is_file() and f.name != "pytorch_model.bin":
            shutil.copy(f, mid / f.name)

import ctranslate2.converters  # noqa: E402

copy = ["tokenizer.json", "preprocessor_config.json"]
ctranslate2.converters.TransformersConverter(
    str(mid), copy_files=copy, load_as_float16=True
).convert(str(dst), quantization="float16", force=False)
print("CONVERT_DONE", dst, "peak_rss_mb", resource.getrusage(resource.RUSAGE_SELF).ru_maxrss // 1024)
