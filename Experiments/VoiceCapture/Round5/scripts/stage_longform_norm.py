#!/usr/bin/env python3
"""Stage loudness-matched (-20 dBFS RMS per utterance) long-form corpus (30s..300s) in /tmp."""
from __future__ import annotations

import json
from pathlib import Path
import numpy as np
import soundfile as sf

from stage_corpora import ROOT, OUT, write_ffmpeg_variant

NORM_DIR = OUT / "longform_norm"


def read_wav_16k_norm(path: Path, target_rms: float = 0.1) -> np.ndarray:
    data, sr = sf.read(path, dtype="float32")
    if data.ndim > 1:
        data = data[:, 0]
    if sr != 16000:
        raise ValueError(f"Expected 16k in {path}, got {sr}")
    rms = float(np.sqrt(np.mean(data ** 2)))
    if rms > 1e-6:
        gain = min(target_rms / rms, 0.95 / max(float(np.max(np.abs(data))), 1e-6))
        data = np.clip(data * gain, -0.98, 0.98).astype(np.float32)
    return data


def stitch_norm(sources: list[dict], base_dir: Path | None, target_seconds: float, pause_s: float = 0.55) -> tuple[np.ndarray, str]:
    sr = 16000
    target_samples = int(target_seconds * sr)
    pause = np.zeros(int(pause_s * sr), dtype=np.float32)
    chunks, refs = [], []
    cur, idx = 0, 0
    while cur < target_samples:
        entry = sources[idx % len(sources)]
        idx += 1
        base = entry.get("_base") or base_dir
        samples = read_wav_16k_norm(base / entry["audio"])
        if cur > 0 and cur + len(pause) < target_samples:
            chunks.append(pause)
            cur += len(pause)
        remaining = target_samples - cur
        if len(samples) <= remaining:
            chunks.append(samples)
            refs.append(entry["reference"])
            cur += len(samples)
        else:
            fit = next((s for s in sources if len(read_wav_16k_norm((s.get("_base") or base_dir) / s["audio"])) <= remaining), None)
            if fit is not None and remaining >= 3.5 * sr:
                f_samples = read_wav_16k_norm((fit.get("_base") or base_dir) / fit["audio"])
                chunks.append(f_samples)
                refs.append(fit["reference"])
                cur += len(f_samples)
            else:
                chunks.append(np.zeros(remaining, dtype=np.float32))
                cur = target_samples
    return np.concatenate(chunks), " ".join(refs)


def main() -> None:
    audio_dir = NORM_DIR / "audio"
    audio_dir.mkdir(parents=True, exist_ok=True)
    fleurs_base = ROOT / "Experiments/VoiceCapture/Round4/corpus"
    en_rows = json.loads((fleurs_base / "fleurs-en/manifest.json").read_text())
    pt_rows = json.loads((fleurs_base / "fleurs-pt/manifest.json").read_text())
    mixed_rows = []
    for a, b in zip(en_rows, pt_rows):
        mixed_rows.append({**a, "_base": fleurs_base / "fleurs-en"})
        mixed_rows.append({**b, "_base": fleurs_base / "fleurs-pt"})

    entries = []
    for lang, rows, base in [("en-US", en_rows, fleurs_base / "fleurs-en"), ("pt-BR", pt_rows, fleurs_base / "fleurs-pt")]:
        for dur in [30, 60, 180, 300]:
            wav16, ref = stitch_norm(rows, base, dur)
            cid = f"norm_{lang.lower().replace('-', '_')}_{dur}s"
            p16 = audio_dir / f"{cid}_16k.wav"
            write_ffmpeg_variant(wav16, p16, rate=16000, channels=1)
            entries.append({
                "id": f"{cid}_16k", "audio": f"audio/{p16.name}", "reference": ref,
                "language": lang, "category": f"norm_{dur}s_16k", "durationSeconds": round(len(wav16) / 16000, 3),
            })
            if dur == 300 and lang == "en-US":
                p48 = audio_dir / f"{cid}_48k_mono.wav"
                write_ffmpeg_variant(wav16, p48, rate=48000, channels=1)
                entries.append({
                    "id": f"{cid}_48k_mono", "audio": f"audio/{p48.name}", "reference": ref,
                    "language": lang, "category": "norm_300s_48k_mono", "durationSeconds": round(len(wav16) / 16000, 3),
                })

    for dur in [180, 300]:
        wav16, ref = stitch_norm(mixed_rows, None, dur)
        cid = f"norm_mixed_{dur}s_16k"
        p16 = audio_dir / f"{cid}.wav"
        write_ffmpeg_variant(wav16, p16, rate=16000, channels=1)
        entries.append({
            "id": cid, "audio": f"audio/{p16.name}", "reference": ref,
            "language": "mixed", "category": f"norm_mixed_{dur}s", "durationSeconds": round(len(wav16) / 16000, 3),
        })

    manifest = NORM_DIR / "manifest.json"
    manifest.write_text(json.dumps(entries, ensure_ascii=False, indent=2) + "\n")
    print(f"Staged loudness-matched longform_norm: {len(entries)} clips -> {manifest}")


if __name__ == "__main__":
    main()
