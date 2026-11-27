#!/usr/bin/env python3
"""Evaluate mlx-community/whisper-large-v3-turbo (local Whisper engine) on Round5 manifests."""
from __future__ import annotations

import argparse
import json
import resource
import sys
import time
from pathlib import Path

import mlx.core as mx
import mlx_whisper


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--manifest", type=Path, required=True)
    parser.add_argument("--out", type=Path, required=True)
    parser.add_argument("--repo", default="mlx-community/whisper-large-v3-turbo")
    parser.add_argument("--language", default=None, help="Optional fixed language or None for auto-detect")
    parser.add_argument("--limit", type=int, default=0)
    args = parser.parse_args()

    entries = json.loads(args.manifest.read_text())
    if args.limit > 0:
        entries = entries[: args.limit]
    corpus_root = args.manifest.parent
    args.out.parent.mkdir(parents=True, exist_ok=True)

    # Measure cold load + first decode separately on first entry, then transcribe rest
    t_load0 = time.perf_counter()
    # Warm-load model + tokenizer once to separate cold model init from per-clip latency
    first_rel = entries[0].get("audio") or f"{entries[0]['id']}.wav"
    t_cold0 = time.perf_counter()
    first_res = mlx_whisper.transcribe(
        str(corpus_root / first_rel),
        path_or_hf_repo=args.repo,
        language=args.language,
        temperature=0.0,
    )
    cold_first_clip_ms = (time.perf_counter() - t_cold0) * 1000.0

    rows = []
    with args.out.open("w") as out_f:
        for idx, entry in enumerate(entries):
            rel = entry.get("audio") or f"{entry['id']}.wav"
            wav_path = corpus_root / rel
            t0 = time.perf_counter()
            err = None
            text = ""
            detected_lang = None
            if idx == 0:
                res = first_res
                elapsed_ms = cold_first_clip_ms
            else:
                try:
                    res = mlx_whisper.transcribe(
                        str(wav_path),
                        path_or_hf_repo=args.repo,
                        language=args.language,
                        temperature=0.0,
                    )
                    elapsed_ms = (time.perf_counter() - t0) * 1000.0
                except Exception as exc:
                    res = {}
                    elapsed_ms = (time.perf_counter() - t0) * 1000.0
                    err = repr(exc)
            if err is None:
                text = (res.get("text") or "").strip()
                detected_lang = res.get("language")
            dur = float(entry.get("durationSeconds") or 0)
            row = {
                "id": entry["id"],
                "language": entry.get("language") or entry.get("locale"),
                "detectedLanguage": detected_lang,
                "category": entry.get("category") or entry.get("scenario"),
                "reference": entry.get("reference"),
                "spoken_text": entry.get("spoken_text"),
                "intended_text": entry.get("intended_text"),
                "transcript": text,
                "audioSeconds": dur,
                "transcribeTotalMs": round(elapsed_ms, 3),
                "realTimeFactor": round((elapsed_ms / 1000.0) / dur, 4) if dur > 0 else None,
                "coldFirstClip": idx == 0,
                "error": err,
            }
            out_f.write(json.dumps(row, ensure_ascii=False) + "\n")
            if (idx + 1) % 25 == 0:
                print(f"mlx-whisper {idx + 1}/{len(entries)}", flush=True)

    meta = {
        "repo": args.repo,
        "languageArg": args.language,
        "coldFirstClipMs": round(cold_first_clip_ms, 2),
        "peakMaxRssBytes": resource.getrusage(resource.RUSAGE_SELF).ru_maxrss,
        "mlxActiveBytes": int(mx.get_active_memory()),
        "mlxPeakBytes": int(mx.get_peak_memory()),
    }
    args.out.with_suffix(".meta.json").write_text(json.dumps(meta, indent=2) + "\n")
    print(f"mlx-whisper finished {len(entries)} clips -> {args.out}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
