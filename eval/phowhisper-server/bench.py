"""Đo độ trễ/RTF và WER/CER của máy chủ STT từ xa (chỉ dùng thư viện chuẩn).

Manifest là TSV không tiêu đề: <nhóm>\t<đường dẫn wav>\t<văn bản tham chiếu (có thể rỗng)>.
Token đọc từ VFLOW_REMOTE_TOKEN hoặc --token-file; không in ra.

  python3 bench.py --url http://127.0.0.1:7612 --manifest m.tsv --runs 10 --out kq.json

Chuẩn hoá trước khi tính WER/CER: Unicode NFC, chữ thường, bỏ mọi ký tự dấu câu
(nhóm Unicode P*) và ký hiệu (S*), gộp khoảng trắng. CER tính trên chuỗi ký tự đã bỏ khoảng trắng.
p95 theo phương pháp nearest-rank.
"""

import argparse
import json
import math
import os
import statistics
import sys
import time
import unicodedata
import urllib.error
import urllib.request


def normalize(text):
    text = unicodedata.normalize("NFC", text).lower()
    text = "".join(" " if unicodedata.category(c)[0] in "PS" else c for c in text)
    return " ".join(text.split())


def edit_distance(a, b):
    prev = list(range(len(b) + 1))
    for i, x in enumerate(a, 1):
        cur = [i]
        for j, y in enumerate(b, 1):
            cur.append(min(prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + (x != y)))
        prev = cur
    return prev[-1]


def p95(values):
    s = sorted(values)
    return s[max(0, math.ceil(0.95 * len(s)) - 1)]


def post(url, token, body):
    req = urllib.request.Request(url, data=body, method="POST", headers={
        "Content-Type": "audio/wav", "Authorization": f"Bearer {token}"})
    t0 = time.perf_counter()
    try:
        with urllib.request.urlopen(req, timeout=180) as r:
            data = json.loads(r.read())
    except urllib.error.HTTPError as e:
        with e:
            raise SystemExit(f"HTTP {e.code}: {e.read()[:300]!r}")
    return data, (time.perf_counter() - t0) * 1000


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--url", default="http://127.0.0.1:7612")
    ap.add_argument("--manifest", required=True)
    ap.add_argument("--runs", type=int, default=10)
    ap.add_argument("--token-file")
    ap.add_argument("--out")
    args = ap.parse_args()

    token = os.environ.get("VFLOW_REMOTE_TOKEN", "")
    if args.token_file:
        with open(args.token_file, encoding="utf-8") as f:
            token = f.read().strip()
    if not token:
        raise SystemExit("Thiếu token (VFLOW_REMOTE_TOKEN hoặc --token-file)")

    items = []
    with open(args.manifest, encoding="utf-8") as f:
        for line in f:
            if line.strip():
                group, path, ref = (line.rstrip("\n").split("\t") + [""])[:3]
                items.append((group, path, ref))

    endpoint = args.url.rstrip("/") + "/v1/transcribe?lang=vi"
    clips, groups = [], {}
    for group, path, ref in items:
        with open(path, "rb") as f:
            body = f.read()
        runs = []
        for _ in range(args.runs):
            data, e2e_ms = post(endpoint, token, body)
            runs.append({"stt_ms": data["stt_ms"], "e2e_ms": round(e2e_ms, 1)})
        hyp = data["text"]
        clip = {"group": group, "file": os.path.basename(path), "audio_ms": data["audio_ms"], "runs": runs,
                "hyp": hyp, "ref": ref}
        if ref:
            r, h = normalize(ref), normalize(hyp)
            clip["word_err"], clip["words"] = edit_distance(r.split(), h.split()), len(r.split())
            rc, hc = r.replace(" ", ""), h.replace(" ", "")
            clip["char_err"], clip["chars"] = edit_distance(rc, hc), len(rc)
        clips.append(clip)
        groups.setdefault(group, []).append(clip)
        print(f"{group}\t{clip['file']}\taudio_ms={clip['audio_ms']}\t"
              f"stt_med={statistics.median(r['stt_ms'] for r in runs)}", file=sys.stderr)

    summary = []
    for group, cs in groups.items():
        stt = [r["stt_ms"] for c in cs for r in c["runs"]]
        e2e = [r["e2e_ms"] for c in cs for r in c["runs"]]
        rtf = [r["stt_ms"] / c["audio_ms"] for c in cs for r in c["runs"]]
        row = {"group": group, "clips": len(cs), "requests": len(stt),
               "audio_ms_mean": round(statistics.mean(c["audio_ms"] for c in cs)),
               "stt_ms_median": statistics.median(stt), "stt_ms_p95": p95(stt),
               "rtf_median": round(statistics.median(rtf), 4), "rtf_p95": round(p95(rtf), 4),
               "e2e_ms_median": round(statistics.median(e2e), 1), "e2e_ms_p95": round(p95(e2e), 1)}
        scored = [c for c in cs if "words" in c]
        if scored:
            row["wer"] = round(sum(c["word_err"] for c in scored) / sum(c["words"] for c in scored), 4)
            row["cer"] = round(sum(c["char_err"] for c in scored) / sum(c["chars"] for c in scored), 4)
            row["scored_clips"] = len(scored)
        else:
            row["wer"] = row["cer"] = None  # không có tham chiếu: không xác định
        summary.append(row)

    print(json.dumps(summary, ensure_ascii=False, indent=1))
    if args.out:
        with open(args.out, "w", encoding="utf-8") as f:
            json.dump({"summary": summary, "clips": clips}, f, ensure_ascii=False, indent=1)


if __name__ == "__main__":
    main()
