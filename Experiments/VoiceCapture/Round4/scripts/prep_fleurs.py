#!/usr/bin/env python3
"""Build a real-human read-speech corpus from Google FLEURS (CC-BY 4.0).

Deterministic selection. Emits 16 kHz mono 16-bit PCM WAV + manifest.json.
No transcript editing. Both normalized and raw references are preserved.
"""
import argparse
import json
import random
import subprocess
import sys
import tempfile
import wave
from pathlib import Path

RATE = 16000


def convert(src_bytes: bytes, dest: Path) -> int:
    with tempfile.NamedTemporaryFile(suffix=".wav", delete=False) as tmp:
        tmp.write(src_bytes)
        tmp_path = tmp.name
    try:
        subprocess.run(
            ["ffmpeg", "-hide_banner", "-loglevel", "error", "-i", tmp_path,
             "-ar", str(RATE), "-ac", "1", "-sample_fmt", "s16", "-y", str(dest)],
            check=True,
        )
    finally:
        Path(tmp_path).unlink(missing_ok=True)
    with wave.open(str(dest), "rb") as wav:
        return wav.getnframes()


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--parquet", required=True, help="FLEURS test parquet for one language")
    parser.add_argument("--language", required=True, help="e.g. en_us or pt_br")
    parser.add_argument("--count", type=int, default=30)
    parser.add_argument("--seed", type=int, default=20261126)
    parser.add_argument("--out", required=True, type=Path)
    parser.add_argument("--min-seconds", type=float, default=2.0)
    parser.add_argument("--max-seconds", type=float, default=18.0)
    args = parser.parse_args()

    import pyarrow.parquet as pq  # noqa: WPS433 (optional dependency)

    table = pq.read_table(args.parquet)
    rows = table.to_pylist()
    # Keep only rows with a raw transcript and usable audio; sort deterministically.
    usable = [r for r in rows if r.get("raw_transcription") and r.get("audio") and r["audio"].get("bytes")]
    usable.sort(key=lambda r: int(r["id"]))
    rng = random.Random(args.seed)
    shuffled = usable[:]
    rng.shuffle(shuffled)

    audio_dir = args.out / "audio"
    audio_dir.mkdir(parents=True, exist_ok=True)

    chosen = []
    for row in shuffled:
        if len(chosen) >= args.count:
            break
        num_samples = int(row.get("num_samples") or 0)
        seconds = num_samples / RATE
        if not (args.min_seconds <= seconds <= args.max_seconds):
            continue
        clip_id = f"{args.language}-{int(row['id']):09d}"
        dest = audio_dir / f"{clip_id}.wav"
        frames = convert(row["audio"]["bytes"], dest)
        chosen.append({
            "id": clip_id,
            "audio": f"audio/{clip_id}.wav",
            "reference": row["raw_transcription"],
            "referenceNormalized": row.get("transcription"),
            "language": args.language,
            "category": "read-speech",
            "source": "google/fleurs test split",
            "sourceId": int(row["id"]),
            "sourcePath": row.get("path"),
            "gender": row.get("gender"),
            "speaker": "unknown; FLEURS does not expose speaker ids",
            "durationSeconds": round(frames / RATE, 4),
            "license": "CC-BY 4.0 (Google FLEURS)",
        })

    chosen.sort(key=lambda r: r["id"])
    (args.out / "manifest.json").write_text(json.dumps(chosen, ensure_ascii=False, indent=2) + "\n")
    print(f"wrote {len(chosen)} clips to {args.out}", file=sys.stderr)
    return 0


if __name__ == "__main__":
    sys.exit(main())
