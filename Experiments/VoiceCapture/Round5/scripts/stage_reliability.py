#!/usr/bin/env python3
"""Build local boundary/coverage fixtures from pinned Round 3/4 inputs."""
import hashlib
import json
from pathlib import Path

import numpy as np
import soundfile as sf

from stage_corpora import OUT, ROOT, write_ffmpeg_variant
from stage_longform_norm import read_wav_16k_norm

RATE = 16000
BASE = ROOT / "Experiments/VoiceCapture/Round4/corpus"
HELD = OUT / "round3-held"
DEST = OUT / "reliability"


def source(base, row, trim=False):
    audio = read_wav_16k_norm(base / (row.get("audio") or f"{row['id']}.wav"))
    if trim:
        voiced = np.flatnonzero(np.abs(audio) > 0.018)
        if voiced.size:
            audio = audio[max(0, voiced[0] - 400):min(len(audio), voiced[-1] + 401)]
    return audio, row["id"], row["reference"]


def timeline(sources, duration, pause, last_at_end=False):
    count = round(duration * RATE)
    track = np.zeros(count, dtype=np.float32)
    cursor = 0
    spans = []
    for audio, source_id, reference in sources:
        if last_at_end:
            cursor = count - len(audio)
        if cursor + len(audio) > count:
            break
        end = cursor + len(audio)
        track[cursor:end] = audio
        spans.append({"source": source_id, "start": cursor / RATE, "end": end / RATE,
                      "reference": reference})
        cursor = end + round(pause * RATE)
    return track, spans


def main():
    DEST.mkdir(parents=True, exist_ok=True)
    english = json.loads((BASE / "fleurs-en/manifest.json").read_text())
    portuguese = json.loads((BASE / "fleurs-pt/manifest.json").read_text())
    held = json.loads((HELD / "manifest.json").read_text())
    mixed = [row for row in held if row["scenario"] == "pt-en-read-switch"]
    rows = []

    unique = OUT / "fleurs-unique"
    unique.mkdir(exist_ok=True)
    fleurs = json.loads((BASE / "manifest.json").read_text())
    for subdir in ("fleurs-en", "fleurs-pt"):
        link = unique / subdir
        if not link.exists():
            link.symlink_to(BASE / subdir, target_is_directory=True)
    by_audio = {entry["audio"]: entry for entry in fleurs}
    (unique / "manifest.json").write_text(json.dumps(list(by_audio.values()), ensure_ascii=False) + "\n")

    def add(name, audio, spans, stereo=False):
        path = DEST / f"{name}.wav"
        if stereo:
            write_ffmpeg_variant(audio, path, rate=48_000, channels=2, active_ch=1)
        else:
            sf.write(path, audio, RATE, subtype="PCM_16")
        rows.append({"id": name, "audio": path.name, "durationSeconds": len(audio) / RATE,
                     "reference": " ".join(s["reference"] for s in spans),
                     "referenceSpans": spans, "sha256": hashlib.sha256(path.read_bytes()).hexdigest()})

    for kind, base, entries in [("en", BASE / "fleurs-en", english),
                                ("pt", BASE / "fleurs-pt", portuguese), ("mixed", HELD, mixed)]:
        clips = [source(base, row, trim=True) for row in entries]
        for duration in [30, 60, 120, 300]:
            add(f"dense_{kind}_{duration}s", *timeline(clips, duration, pause=0.035))

    raw_english, raw_portuguese, raw_mixed = [], [], []
    for en, pt in zip(english, portuguese):
        for base, row, dest in [(BASE / "fleurs-en", en, raw_english),
                                (BASE / "fleurs-pt", pt, raw_portuguese)]:
            wav, rate = sf.read(base / row["audio"], dtype="float32")
            assert rate == RATE and wav.ndim == 1
            clip = (wav, row["id"], row["reference"])
            dest.append(clip)
            raw_mixed.append(clip)
    for duration in [30, 60, 120]:
        add(f"raw_mixed_{duration}s", *timeline(raw_mixed, duration, pause=0.55))
    add("raw_en_120s", *timeline(raw_english, 120, pause=0.55))
    add("raw_pt_120s", *timeline(raw_portuguese, 120, pause=0.55))

    tail = source(BASE / "fleurs-en", english[0], trim=True)
    add("speech_at_300s_cap", *timeline([tail], 300, pause=0, last_at_end=True))
    pt_tail = source(BASE / "fleurs-pt", portuguese[0], trim=True)
    add("speech_at_120s_cap_stereo_ch1", *timeline([pt_tail], 120, pause=0, last_at_end=True), stereo=True)
    add("all_silence_60s", np.zeros(60 * RATE), [])
    add("all_noise_60s", np.random.default_rng(719).normal(0, 0.002, 60 * RATE), [])
    for duration in [14.99, 15.0, 15.01, 16.0]:
        add(f"single_window_{duration:.2f}s", *timeline([tail], duration, pause=0, last_at_end=True))

    (DEST / "manifest.json").write_text(json.dumps(rows, indent=2, ensure_ascii=False) + "\n")

    # Vary the left context while keeping the same PCM and right boundary.
    audio, _ = sf.read(OUT / "longform_norm/audio/norm_en_us_30s_16k.wav", dtype="float32")
    rows.clear()
    for start, name in [(12.8, "round5_window_with_context_pcm"),
                        (12.88, "round5_window_without_context_pcm"),
                        (20.56, "round5_clause_only")]:
        add(name, audio[round(start * RATE):round(27.76 * RATE)], [])
    (DEST / "context-probes.json").write_text(json.dumps(rows, indent=2) + "\n")


if __name__ == "__main__":
    main()
