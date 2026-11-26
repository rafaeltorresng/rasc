#!/usr/bin/env python3
"""Summarize identical synthetic inputs. Semantic adjudication lives in the report."""
import json
import math
import re
import statistics
import sys
import unicodedata
from pathlib import Path

def tokenize(text):
    text = unicodedata.normalize("NFC", text.casefold()).replace("’", "'")
    return re.findall(r"[^\W_]+(?:'[^\W_]+)*", text, flags=re.UNICODE)

def edits(reference, hypothesis):
    prior = list(range(len(hypothesis) + 1))
    for i, expected in enumerate(reference, 1):
        current = [i]
        for j, actual in enumerate(hypothesis, 1):
            current.append(min(prior[j] + 1, current[-1] + 1, prior[j-1] + (expected != actual)))
        prior = current
    return prior[-1]

def stats(values):
    values = sorted(value for value in values if value is not None)
    if not values:
        return None
    return dict(n=len(values), p50=round(statistics.median(values), 2),
                p95=round(values[math.ceil(len(values)*0.95)-1], 2),
                min=round(values[0], 2), max=round(values[-1], 2))

def read(name):
    return [json.loads(line) for line in (root / name).read_text().splitlines() if line.startswith("{")]

root = Path(sys.argv[1])
manifest = {f["id"] + ".wav": f for f in json.loads((root / "fixture-manifest.json").read_text())}
summary = {}
for engine, path in {
    "SpeechTranscriber": "speech-paced.jsonl",
    "DictationTranscriber": "dictation-paced.jsonl",
    "Whisper turbo": "whisper-batch.jsonl",
    "Parakeet v3": "parakeet-batch.jsonl",
}.items():
    raw = read(path)
    rows = [r for r in raw if r["event"] in {"result", "case_error"} and r.get("requested_language") != "auto"]
    assert len(rows) == len(manifest)
    assert {r["fixture"] for r in rows} == set(manifest)
    speech = [r for r in rows if manifest[r["fixture"]]["reference"]]
    short = [r for r in speech if manifest[r["fixture"]]["seconds"] <= 6]
    scores = {}
    for group in ("en", "pt", "mix", "all"):
        subset = [r for r in speech if group == "all" or manifest[r["fixture"]]["group"] == group]
        reference_words = sum(len(tokenize(manifest[r["fixture"]]["reference"])) for r in subset)
        word_edits = sum(edits(tokenize(manifest[r["fixture"]]["reference"]), tokenize(r.get("transcript", ""))) for r in subset)
        scores[group] = {"utterances": len(subset), "reference_words": reference_words,
                         "word_edits": word_edits, "wer_percent": round(100*word_edits/reference_words, 2)}
    summary[engine] = {
        "wer": scores,
        "no_speech_outcomes": {r["fixture"]: r.get("error", r.get("transcript", "").strip())
                               for r in rows if not manifest[r["fixture"]]["reference"]},
        "first_result_ms": stats(r.get("first_result_ms") for r in speech),
        "first_partial_ms": stats(r.get("first_partial_ms") for r in speech),
        "finish_ms_all_speech": stats(r["finish_ms"] for r in speech),
        "finish_ms_short_speech": stats(r["finish_ms"] for r in short),
        "prepare_first_clip_in_process_ms": [round(x["prepare_ms"], 2) for x in
            ([rows[0], next(r for r in rows if r.get("locale") == "pt_BR")]
             if "prepare_ms" in rows[0] else [x for x in raw if x["event"] == "setup"])],
        "analyzer_prepare_ms": stats(r.get("prepare_ms") for r in speech),
        "boundary": {r["fixture"]: r.get("transcript", "").strip() for r in speech if r["fixture"] in
                     {"en-clip.wav", "en-boundary.wav", "pt-clip.wav", "pt-boundary.wav"}},
    }
mic = [r for r in read("microphone.jsonl") if r["event"] == "mic_trial"]
summary["microphone"] = {
    "first_trial_ms": mic[0]["first_buffer_ms"],
    "all_first_buffer_ms": stats(r["first_buffer_ms"] for r in mic),
    "repeated_first_buffer_ms": stats(r["first_buffer_ms"] for r in mic[1:]),
    "engine_start_ms": stats(r["start_ms"] for r in mic),
    "tap_frames": sorted({r["first_buffer_frames"] for r in mic}),
    "sample_rates": sorted({r["sample_rate"] for r in mic}),
}
print(json.dumps(summary, indent=2, ensure_ascii=False))
