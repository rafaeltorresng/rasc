#!/usr/bin/env python3
"""Create controlled perturbations of real human speech (silence, added noise,
tempo). References are unchanged; every variant is labelled. Synthetic noise is
added, never substituted for speech."""
import argparse
import json
import shutil
import subprocess
import sys
from pathlib import Path

RATE = 16000


def run(args):
    subprocess.run(["ffmpeg", "-hide_banner", "-loglevel", "error", *args, "-y"], check=True)


def add_pink_noise(src: Path, dest: Path, snr_db: float):
    import array, math, random, wave
    with wave.open(str(src), "rb") as wav:
        params = wav.getparams()
        frames = array.array("h", wav.readframes(wav.getnframes()))
    speech = [v / 32768.0 for v in frames]
    rms = math.sqrt(sum(x * x for x in speech) / len(speech)) if speech else 0.0
    target_noise_rms = rms * 10 ** (-snr_db / 20.0)
    rng = random.Random(4567)
    # simple pink-ish noise: 0.96 one-pole low-pass on white noise
    noise = []
    low = 0.0
    for _ in speech:
        white = rng.gauss(0, 1)
        low = 0.96 * low + 0.04 * white
        noise.append(0.30 * white + 2.0 * low)
    noise_rms = math.sqrt(sum(x * x for x in noise) / len(noise)) or 1.0
    scale = target_noise_rms / noise_rms
    out = array.array("h", (max(-32768, min(32767, int((x + n * scale) * 32767))) for x, n in zip(speech, noise)))
    with wave.open(str(dest), "wb") as wav:
        wav.setparams((1, 2, RATE, 0, "NONE", "not compressed"))
        wav.writeframes(out.tobytes())


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--manifest", type=Path, required=True)
    parser.add_argument("--out", type=Path, required=True)
    parser.add_argument("--limit", type=int, default=12)
    parser.add_argument("--per-language", type=int, default=6)
    args = parser.parse_args()

    src = json.loads(args.manifest.read_text())
    base_root = args.manifest.parent
    args.out.mkdir(parents=True, exist_ok=True)
    audio_dir = args.out / "audio"
    audio_dir.mkdir(exist_ok=True)

    # pick a balanced deterministic subset
    by_lang = {}
    for e in src:
        by_lang.setdefault(e["language"], []).append(e)
    picked = []
    for lang, items in sorted(by_lang.items()):
        items.sort(key=lambda e: e["id"])
        picked.extend(items[:args.per_language])
    picked = picked[:args.limit] or src[:args.limit]

    out_entries = []
    for e in picked:
        src_audio = base_root / e["audio"]
        stem = e["id"]
        # copy base as-is for reference
        base_dest = audio_dir / f"{stem}__base.wav"
        shutil.copy(src_audio, base_dest)
        variants = {"base": (base_dest, e["category"] or "read-speech", None)}
        if not variants:
            pass
        # +3s trailing silence
        d = audio_dir / f"{stem}__trailing_silence_3s.wav"
        run(["-i", str(src_audio), "-af", "apad=pad_dur=3", "-ar", str(RATE), "-ac", "1", "-sample_fmt", "s16", str(d)])
        variants["trailing_silence_3s"] = (d, "pauses-silence", "3 s silence appended")
        # +2s leading silence
        d = audio_dir / f"{stem}__leading_silence_2s.wav"
        run(["-i", str(src_audio), "-af", "adelay=2000|2000", "-ar", str(RATE), "-ac", "1", "-sample_fmt", "s16", str(d)])
        variants["leading_silence_2s"] = (d, "pauses-silence", "2 s silence prepended")
        # added synthetic pink-filtered noise at +15 dB SNR (noise RMS = speech RMS * 10^(-15/20))
        d = audio_dir / f"{stem}__noise_m15db.wav"
        add_pink_noise(src_audio, d, snr_db=15.0)
        variants["added_noise_m15db"] = (d, "background-noise", "pink-filtered noise added at +15 dB SNR (noise -15 dB relative to speech RMS); reference unchanged")
        # faster speech
        d = audio_dir / f"{stem}__tempo_fast_1p25.wav"
        run(["-i", str(src_audio), "-af", "atempo=1.25", "-ar", str(RATE), "-ac", "1", "-sample_fmt", "s16", str(d)])
        variants["tempo_fast_1p25"] = (d, "speaking-rate", "atempo=1.25; reference unchanged")
        # slower speech
        d = audio_dir / f"{stem}__tempo_slow_0p8.wav"
        run(["-i", str(src_audio), "-af", "atempo=0.8", "-ar", str(RATE), "-ac", "1", "-sample_fmt", "s16", str(d)])
        variants["tempo_slow_0p8"] = (d, "speaking-rate", "atempo=0.8; reference unchanged")

        for name, (path, category, note) in variants.items():
            rel = f"audio/{path.name}"
            entry = dict(e)
            entry["id"] = f"{stem}__{name}"
            entry["audio"] = rel
            entry["category"] = category
            entry["variant"] = name
            entry["variantNote"] = note
            entry["baseId"] = stem
            entry["referenceUnchanged"] = True
            out_entries.append(entry)

    # non-speech controls: pure silence + click-only, no reference
    for name, secs in [("silence_1s", 1.0), ("silence_3s", 3.0)]:
        d = audio_dir / f"control__{name}.wav"
        run(["-f", "lavfi", "-i", f"anullsrc=r={RATE}:cl=mono", "-t", str(secs), "-sample_fmt", "s16", str(d)])
        out_entries.append({"id": f"control__{name}", "audio": f"audio/{d.name}", "reference": None,
                            "language": None, "category": "non-speech-control", "variant": name})
    # click-only: 1.0 s silence + a short click at 400 ms (16 samples, 16-bit PCM)
    import array, wave
    click_path = audio_dir / "control__click_only.wav"
    samples = array.array("h", [0]) * (RATE + 16)
    samples[int(0.4 * RATE):int(0.4 * RATE) + 4] = array.array("h", [8000, -6200, 4000, -2500])
    with wave.open(str(click_path), "wb") as wav:
        wav.setparams((1, 2, RATE, 0, "NONE", "not compressed"))
        wav.writeframes(samples.tobytes())
    out_entries.append({"id": "control__click_only", "audio": "audio/control__click_only.wav", "reference": None,
                        "language": None, "category": "non-speech-control", "variant": "click_only"})

    out_entries.sort(key=lambda e: e["id"])
    (args.out / "manifest.json").write_text(json.dumps(out_entries, ensure_ascii=False, indent=2) + "\n")
    print(f"wrote {len(out_entries)} entries to {args.out}", file=sys.stderr)
    return 0


if __name__ == "__main__":
    sys.exit(main())
