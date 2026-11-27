#!/usr/bin/env python3
"""Run clean, non-overlapping paired Round5 benchmarks and score every corpus."""
from __future__ import annotations

import json
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[4]
RASC_BENCH = Path("/tmp/rasc-bench-pkg/RascBench.app/Contents/MacOS/RascBench")
VENV_PY = Path("/tmp/rasc-eval-venv/bin/python")
SCRIPTS = Path(__file__).resolve().parent
RAW_DIR = ROOT / "Experiments/VoiceCapture/Round5/results/raw"
SCORED_DIR = ROOT / "Experiments/VoiceCapture/Round5/results/scored"
CORPORA = {
    "voicearena": Path("/tmp/rasc-round5-corpora/voicearena/manifest.json"),
    "round3_held": Path("/tmp/rasc-round5-corpora/round3-held/manifest.json"),
    "fleurs60": ROOT / "Experiments/VoiceCapture/Round4/corpus/manifest.json",
    "longform": Path("/tmp/rasc-round5-corpora/longform/manifest.json"),
}


def run(cmd: list[str]) -> None:
    print(f"\n==> RUN: {' '.join(cmd)}", flush=True)
    subprocess.run(cmd, check=True)


def main() -> int:
    RAW_DIR.mkdir(parents=True, exist_ok=True)
    SCORED_DIR.mkdir(parents=True, exist_ok=True)

    # 1. Rasc Fluid Speech Pro (+ Refine on VoiceArena; + 200ms onset probe on Round3 held)
    run([str(RASC_BENCH), "eval-voice", "--manifest", str(CORPORA["voicearena"]), "--out", str(RAW_DIR / "voicearena_fluid_refine.jsonl"), "--refine"])
    run([str(RASC_BENCH), "eval-voice", "--manifest", str(CORPORA["round3_held"]), "--out", str(RAW_DIR / "round3_fluid.jsonl")])
    run([str(RASC_BENCH), "eval-voice", "--manifest", str(CORPORA["round3_held"]), "--onset-pad-ms", "200", "--out", str(RAW_DIR / "round3_fluid_pad200.jsonl")])
    run([str(RASC_BENCH), "eval-voice", "--manifest", str(CORPORA["fleurs60"]), "--out", str(RAW_DIR / "fleurs60_fluid.jsonl")])

    # 2. Apple On-Device SpeechTranscriber
    run([str(RASC_BENCH), "apple-speech", "--manifest", str(CORPORA["voicearena"]), "--out", str(RAW_DIR / "voicearena_apple.jsonl")])
    run([str(RASC_BENCH), "apple-speech", "--manifest", str(CORPORA["round3_held"]), "--out", str(RAW_DIR / "round3_apple.jsonl")])
    run([str(RASC_BENCH), "apple-speech", "--manifest", str(CORPORA["fleurs60"]), "--out", str(RAW_DIR / "fleurs60_apple.jsonl")])
    run([str(RASC_BENCH), "apple-speech", "--manifest", str(CORPORA["longform"]), "--out", str(RAW_DIR / "longform_apple.jsonl")])

    # 3. Local mlx-community/whisper-large-v3-turbo (Superwhisper local / Handy / VoiceInk representative engine)
    run([str(VENV_PY), str(SCRIPTS / "run_mlx_whisper.py"), "--manifest", str(CORPORA["voicearena"]), "--out", str(RAW_DIR / "voicearena_whisper_turbo.jsonl")])
    run([str(VENV_PY), str(SCRIPTS / "run_mlx_whisper.py"), "--manifest", str(CORPORA["round3_held"]), "--out", str(RAW_DIR / "round3_whisper_turbo.jsonl")])
    run([str(VENV_PY), str(SCRIPTS / "run_mlx_whisper.py"), "--manifest", str(CORPORA["fleurs60"]), "--out", str(RAW_DIR / "fleurs60_whisper_turbo.jsonl")])
    run([str(VENV_PY), str(SCRIPTS / "run_mlx_whisper.py"), "--manifest", str(CORPORA["longform"]), "--out", str(RAW_DIR / "longform_whisper_turbo.jsonl")])

    # 4. Score all four corpora cleanly
    run([
        str(VENV_PY), str(SCRIPTS / "score_round5.py"),
        "--corpus", "voicearena_151",
        "--out", str(SCORED_DIR / "voicearena_151.json"),
        "--input", f"rasc_fluid={RAW_DIR / 'voicearena_fluid_refine.jsonl'}",
        "--input", f"rasc_fluid_plus_refine:refined={RAW_DIR / 'voicearena_fluid_refine.jsonl'}",
        "--input", f"apple_speech_transcriber={RAW_DIR / 'voicearena_apple.jsonl'}",
        "--input", f"whisper_large_v3_turbo={RAW_DIR / 'voicearena_whisper_turbo.jsonl'}",
    ])
    run([
        str(VENV_PY), str(SCRIPTS / "score_round5.py"),
        "--corpus", "round3_held_168",
        "--out", str(SCORED_DIR / "round3_held_168.json"),
        "--input", f"rasc_fluid={RAW_DIR / 'round3_fluid.jsonl'}",
        "--input", f"rasc_fluid_pad200={RAW_DIR / 'round3_fluid_pad200.jsonl'}",
        "--input", f"apple_speech_transcriber={RAW_DIR / 'round3_apple.jsonl'}",
        "--input", f"whisper_large_v3_turbo={RAW_DIR / 'round3_whisper_turbo.jsonl'}",
    ])
    run([
        str(VENV_PY), str(SCRIPTS / "score_round5.py"),
        "--corpus", "fleurs_60",
        "--out", str(SCORED_DIR / "fleurs_60.json"),
        "--input", f"rasc_fluid={RAW_DIR / 'fleurs60_fluid.jsonl'}",
        "--input", f"apple_speech_transcriber={RAW_DIR / 'fleurs60_apple.jsonl'}",
        "--input", f"whisper_large_v3_turbo={RAW_DIR / 'fleurs60_whisper_turbo.jsonl'}",
    ])
    # Convert long_capture_bench.json rows into JSONL for uniform scoring alongside apple & whisper
    lf_rows = json.loads((ROOT / "Experiments/VoiceCapture/Round5/results/long_capture_bench.json").read_text())["rows"]
    lf_rasc_jsonl = RAW_DIR / "longform_fluid.jsonl"
    with lf_rasc_jsonl.open("w") as fh:
        for r in lf_rows:
            fh.write(json.dumps({
                "id": r["id"], "language": r["language"], "category": r["category"],
                "reference": r["reference"], "transcript": r["transcript"],
                "audioSeconds": r["audioSeconds"], "transcribeTotalMs": r["timing"]["totalMs"],
                "realTimeFactor": r["timing"].get("realTimeFactor"), "error": None,
            }, ensure_ascii=False) + "\n")
    run([
        str(VENV_PY), str(SCRIPTS / "score_round5.py"),
        "--corpus", "longform_30s_300s",
        "--out", str(SCORED_DIR / "longform_30s_300s.json"),
        "--input", f"rasc_fluid={lf_rasc_jsonl}",
        "--input", f"apple_speech_transcriber={RAW_DIR / 'longform_apple.jsonl'}",
        "--input", f"whisper_large_v3_turbo={RAW_DIR / 'longform_whisper_turbo.jsonl'}",
    ])
    print("ALL ROUND5 EVALUATIONS AND SCORES COMPLETE.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
