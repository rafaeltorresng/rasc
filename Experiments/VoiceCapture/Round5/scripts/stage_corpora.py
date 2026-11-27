#!/usr/bin/env python3
"""Stage VoiceArena/Dictation_Dataset (test, n=151) + FLEURS stitched long-form (30s..300s) + acoustic boundaries in /tmp."""
from __future__ import annotations

import json
import math
import subprocess
from pathlib import Path
import numpy as np
import pyarrow.parquet as pq
import soundfile as sf
from huggingface_hub import hf_hub_download

ROOT = Path(__file__).resolve().parents[4]
OUT = Path("/tmp/rasc-round5-corpora")


def stage_voicearena() -> None:
    va_dir = OUT / "voicearena"
    audio_dir = va_dir / "audio"
    manifest_path = va_dir / "manifest.json"
    if manifest_path.exists() and len(list(audio_dir.glob("*.wav"))) == 151:
        print("VoiceArena already staged (151 clips)")
        return
    audio_dir.mkdir(parents=True, exist_ok=True)
    parquet_path = Path(
        hf_hub_download(
            repo_id="VoiceArena/Dictation_Dataset",
            filename="data/test-00000-of-00001.parquet",
            repo_type="dataset",
            revision="ab671bb28d33defac2955fda2a588e75599a368b",
        )
    )
    table = pq.read_table(parquet_path)
    entries = []
    for i in range(table.num_rows):
        row = {col: table[col][i].as_py() for col in table.column_names}
        clip_id = str(row["id"])
        audio_obj = row["audio"]
        raw_bytes = audio_obj.get("bytes")
        raw_path = audio_dir / f"{clip_id}.src"
        wav_path = audio_dir / f"{clip_id}.wav"
        if raw_bytes is not None:
            raw_path.write_bytes(raw_bytes)
            src = str(raw_path)
        else:
            src = str(audio_obj["path"])
        subprocess.run(
            [
                "ffmpeg", "-nostdin", "-y", "-v", "error",
                "-i", src, "-ac", "1", "-ar", "16000", "-c:a", "pcm_s16le", "-map_metadata", "-1",
                str(wav_path),
            ],
            check=True,
        )
        if raw_path.exists():
            raw_path.unlink()
        data, sr = sf.read(wav_path, dtype="float32")
        entries.append(
            {
                "id": clip_id,
                "audio": f"audio/{clip_id}.wav",
                "reference": row["spoken_text"],
                "spoken_text": row["spoken_text"],
                "intended_text": row["intended_text"],
                "domain": row.get("domain"),
                "language": "en-US",
                "category": row.get("domain") or "dictation",
                "speaker_id": row.get("speaker_id"),
                "durationSeconds": round(len(data) / sr, 3),
            }
        )
    manifest_path.write_text(json.dumps(entries, ensure_ascii=False, indent=2) + "\n")
    print(f"Staged VoiceArena: {len(entries)} clips -> {manifest_path}")


def read_wav_16k(path: Path) -> np.ndarray:
    data, sr = sf.read(path, dtype="float32")
    if data.ndim > 1:
        data = data[:, 0]
    if sr != 16000:
        raise ValueError(f"Expected 16k in {path}, got {sr}")
    return data


def stitch_duration(sources: list[dict], base_dir: Path, target_seconds: float, pause_s: float = 0.55) -> tuple[np.ndarray, str, list[str]]:
    sr = 16000
    target_samples = int(target_seconds * sr)
    pause = np.zeros(int(pause_s * sr), dtype=np.float32)
    chunks = []
    refs = []
    src_ids = []
    cur = 0
    idx = 0
    while cur < target_samples:
        entry = sources[idx % len(sources)]
        idx += 1
        samples = read_wav_16k(base_dir / entry["audio"])
        if cur > 0 and cur + len(pause) < target_samples:
            chunks.append(pause)
            cur += len(pause)
        remaining = target_samples - cur
        if len(samples) <= remaining:
            chunks.append(samples)
            refs.append(entry["reference"])
            src_ids.append(entry["id"])
            cur += len(samples)
        else:
            # Trim tail cleanly only if we have room for >= 3.5s, else pad silence to exact target_seconds
            if remaining < 3.5 * sr and chunks:
                chunks.append(np.zeros(remaining, dtype=np.float32))
                cur += remaining
            else:
                # Try finding a shorter clip that fits cleanly first
                fit = next((s for s in sources if len(read_wav_16k(base_dir / s["audio"])) <= remaining), None)
                if fit is not None:
                    f_samples = read_wav_16k(base_dir / fit["audio"])
                    chunks.append(f_samples)
                    refs.append(fit["reference"])
                    src_ids.append(fit["id"])
                    cur += len(f_samples)
                else:
                    chunks.append(np.zeros(remaining, dtype=np.float32))
                    cur += remaining
    audio = np.concatenate(chunks)
    return audio, " ".join(refs), src_ids


def write_ffmpeg_variant(wav16: np.ndarray, dest: Path, rate: int = 16000, channels: int = 1, active_ch: int = 0) -> None:
    tmp16 = dest.with_suffix(".tmp16.wav")
    if channels == 1:
        sf.write(tmp16, wav16, 16000, subtype="PCM_16")
        if rate == 16000:
            tmp16.replace(dest)
            return
        subprocess.run(
            ["ffmpeg", "-nostdin", "-y", "-v", "error", "-i", str(tmp16), "-ar", str(rate), "-ac", "1", "-c:a", "pcm_s16le", str(dest)],
            check=True,
        )
        tmp16.unlink()
    else:
        # First resample mono cleanly via ffmpeg, then build stereo with low ambient hum on inactive channel
        tmp_rate = dest.with_suffix(".tmprate.wav")
        sf.write(tmp16, wav16, 16000, subtype="PCM_16")
        subprocess.run(
            ["ffmpeg", "-nostdin", "-y", "-v", "error", "-i", str(tmp16), "-ar", str(rate), "-ac", "1", "-c:a", "pcm_s16le", str(tmp_rate)],
            check=True,
        )
        mono_r, _ = sf.read(tmp_rate, dtype="float32")
        rng = np.random.default_rng(20261127)
        quiet_noise = rng.normal(0.0, 0.0005, size=len(mono_r)).astype(np.float32)
        stereo = np.column_stack([quiet_noise, mono_r]) if active_ch == 1 else np.column_stack([mono_r, quiet_noise])
        sf.write(dest, stereo, rate, subtype="PCM_16")
        tmp16.unlink()
        tmp_rate.unlink()


def stage_longform_and_boundaries() -> None:
    lf_dir = OUT / "longform"
    audio_dir = lf_dir / "audio"
    audio_dir.mkdir(parents=True, exist_ok=True)
    fleurs_base = ROOT / "Experiments/VoiceCapture/Round4/corpus"
    en_rows = json.loads((fleurs_base / "fleurs-en/manifest.json").read_text())
    pt_rows = json.loads((fleurs_base / "fleurs-pt/manifest.json").read_text())
    mixed_rows = []
    for a, b in zip(en_rows, pt_rows):
        mixed_rows.append({**a, "_base": fleurs_base / "fleurs-en"})
        mixed_rows.append({**b, "_base": fleurs_base / "fleurs-pt"})

    entries = []
    for lang, rows, base in [
        ("en-US", en_rows, fleurs_base / "fleurs-en"),
        ("pt-BR", pt_rows, fleurs_base / "fleurs-pt"),
    ]:
        for dur in [30, 60, 180, 300]:
            wav16, ref, src_ids = stitch_duration(rows, base, dur)
            cid = f"long_{lang.lower().replace('-', '_')}_{dur}s"
            p16 = audio_dir / f"{cid}_16k.wav"
            write_ffmpeg_variant(wav16, p16, rate=16000, channels=1)
            entries.append({
                "id": f"{cid}_16k", "audio": f"audio/{p16.name}", "reference": ref,
                "language": lang, "category": f"long_{dur}s_16k", "durationSeconds": round(len(wav16) / 16000, 3),
                "sourceClips": len(src_ids),
            })
            # Also stage 48kHz mono for EN and 48kHz stereo (ch1 active) for PT-BR at 300s (and EN 60s)
            if dur in (60, 300):
                p48 = audio_dir / f"{cid}_48k_mono.wav"
                write_ffmpeg_variant(wav16, p48, rate=48000, channels=1)
                entries.append({
                    "id": f"{cid}_48k_mono", "audio": f"audio/{p48.name}", "reference": ref,
                    "language": lang, "category": f"long_{dur}s_48k_mono", "durationSeconds": round(len(wav16) / 16000, 3),
                })
            if dur == 300 and lang == "pt-BR":
                p48s = audio_dir / f"{cid}_48k_stereo_ch1.wav"
                write_ffmpeg_variant(wav16, p48s, rate=48000, channels=2, active_ch=1)
                entries.append({
                    "id": f"{cid}_48k_stereo_ch1", "audio": f"audio/{p48s.name}", "reference": ref,
                    "language": lang, "category": "long_300s_48k_stereo_ch1", "durationSeconds": round(len(wav16) / 16000, 3),
                })

    # Mixed PT-EN 180s & 300s
    for dur in [180, 300]:
        # Flatten into uniform base
        sr = 16000
        pause = np.zeros(int(0.55 * sr), dtype=np.float32)
        chunks, refs, cur, idx = [], [], 0, 0
        target = dur * sr
        while cur < target:
            r = mixed_rows[idx % len(mixed_rows)]
            idx += 1
            s = read_wav_16k(r["_base"] / r["audio"])
            if cur > 0 and cur + len(pause) < target:
                chunks.append(pause)
                cur += len(pause)
            if cur + len(s) <= target:
                chunks.append(s)
                refs.append(r["reference"])
                cur += len(s)
            else:
                chunks.append(np.zeros(target - cur, dtype=np.float32))
                cur = target
        wav16 = np.concatenate(chunks)
        cid = f"long_mixed_{dur}s_16k"
        p = audio_dir / f"{cid}.wav"
        write_ffmpeg_variant(wav16, p, rate=16000, channels=1)
        entries.append({
            "id": cid, "audio": f"audio/{p.name}", "reference": " ".join(refs),
            "language": "mixed", "category": f"long_mixed_{dur}s", "durationSeconds": round(len(wav16) / 16000, 3),
        })

    # Acoustic boundary probes: zero-ms onset, 299.8s end-speech (inside 300s), +10 dB / +20 dB SNR noise
    sample_en = read_wav_16k(fleurs_base / "fleurs-en" / en_rows[0]["audio"])
    sample_pt = read_wav_16k(fleurs_base / "fleurs-pt" / pt_rows[0]["audio"])
    # 0ms immediate speech onset (trim leading silence <0.01 rms)
    onset_idx = int(np.argmax(np.abs(sample_pt) > 0.02))
    trimmed_pt = sample_pt[onset_idx:]
    p_onset = audio_dir / "boundary_0ms_onset_pt.wav"
    sf.write(p_onset, trimmed_pt, 16000, subtype="PCM_16")
    entries.append({"id": "boundary_0ms_onset_pt", "audio": f"audio/{p_onset.name}", "reference": pt_rows[0]["reference"], "language": "pt-BR", "category": "boundary_onset", "durationSeconds": round(len(trimmed_pt) / 16000, 3)})

    # 300s boundary tail (quiet until last 6s so speech finishes at 299.9s)
    tail_speech = sample_en[: min(len(sample_en), 6 * 16000)]
    padded_300 = np.concatenate([np.zeros(300 * 16000 - len(tail_speech), dtype=np.float32), tail_speech])
    p_tail = audio_dir / "boundary_300s_tail_en.wav"
    sf.write(p_tail, padded_300, 16000, subtype="PCM_16")
    entries.append({"id": "boundary_300s_tail_en", "audio": f"audio/{p_tail.name}", "reference": en_rows[0]["reference"], "language": "en-US", "category": "boundary_300s_tail", "durationSeconds": 300.0})

    manifest = lf_dir / "manifest.json"
    manifest.write_text(json.dumps(entries, ensure_ascii=False, indent=2) + "\n")
    print(f"Staged LongForm + Boundaries: {len(entries)} entries -> {manifest}")


if __name__ == "__main__":
    stage_voicearena()
    stage_longform_and_boundaries()
