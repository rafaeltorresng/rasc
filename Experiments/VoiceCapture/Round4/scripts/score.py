#!/usr/bin/env python3
"""Score Rasc voice eval JSONL against references. Reports WER/CER, punctuation,
and latency percentiles. Word error rate is punctuation-insensitive by default;
`werPunctuationSensitive` keeps punctuation tokens. Nothing is silently dropped."""
import argparse
import json
import math
import re
import statistics
import sys
import unicodedata
from collections import defaultdict
from pathlib import Path

PUNCT = re.compile(r"[^\w\s]", re.UNICODE)


def normalize_text(text):
    text = unicodedata.normalize("NFC", text or "").casefold().replace("’", "'").replace("‘", "'")
    text = re.sub(r"[–—]", " ", text)
    text = PUNCT.sub(" ", text)
    return " ".join(text.split())


def tokenize(text, strip_punctuation=True):
    text = unicodedata.normalize("NFC", text or "").casefold().replace("’", "'").replace("‘", "'")
    if strip_punctuation:
        text = re.sub(r"[–—]", " ", text)
        text = PUNCT.sub(" ", text)
        return re.findall(r"[^\W_]+(?:'[^\W_]+)*", text, flags=re.UNICODE)
    return re.findall(r"[^\W_]+(?:'[^\W_]+)*|[^\w\s]", text, flags=re.UNICODE)


def edits(reference, hypothesis):
    prior = list(range(len(hypothesis) + 1))
    for i, expected in enumerate(reference, 1):
        current = [i]
        for j, actual in enumerate(hypothesis, 1):
            current.append(min(prior[j] + 1, current[-1] + 1, prior[j - 1] + (expected != actual)))
        prior = current
    return prior[-1]


def stats(values):
    values = sorted(v for v in values if v is not None)
    if not values:
        return None
    return {
        "n": len(values),
        "mean": round(statistics.fmean(values), 3),
        "p50": round(values[(len(values) - 1) // 2], 3),
        "p95": round(values[min(len(values) - 1, math.ceil(len(values) * 0.95) - 1)], 3),
        "min": round(values[0], 3),
        "max": round(values[-1], 3),
    }


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("results_jsonl", type=Path)
    parser.add_argument("--out", type=Path, required=True)
    parser.add_argument("--group-by", default="language", choices=["language", "category", "none"])
    args = parser.parse_args()

    rows = [json.loads(line) for line in args.results_jsonl.read_text().splitlines() if line.startswith("{")]
    speech = [r for r in rows if (r.get("reference") or "").strip()]
    scored = [r for r in speech if r.get("error") is None]
    groups = defaultdict(list)
    for r in scored:
        key = r.get(args.group_by) or "all" if args.group_by != "none" else "all"
        groups[key].append(r)

    def score(subset):
        ref_words = sum(len(tokenize(r["reference"], True)) for r in subset)
        hyp_words = sum(len(tokenize(r["transcript"], True)) for r in subset)
        edit_total = sum(edits(tokenize(r["reference"], True), tokenize(r["transcript"], True)) for r in subset)
        norm_refs = [normalize_text(r["reference"]) for r in subset]
        norm_hyps = [normalize_text(r["transcript"]) for r in subset]
        ref_chars = sum(len(x) for x in norm_refs)
        char_edits = sum(edits(list(a), list(b)) for a, b in zip(norm_refs, norm_hyps))
        raw_ref_chars = sum(len((r["reference"] or "").strip()) for r in subset)
        raw_char_edits = sum(edits(list((r["reference"] or "").strip()), list((r["transcript"] or "").strip())) for r in subset)
        raw_edits = sum(edits(tokenize(r["reference"], False), tokenize(r["transcript"], False)) for r in subset)
        raw_ref = sum(len(tokenize(r["reference"], False)) for r in subset)
        # punctuation counts (reference vs hypothesis tokens)
        ref_punct = sum(len(PUNCT.findall(r["reference"] or "")) for r in subset)
        hyp_punct = sum(len(PUNCT.findall(r["transcript"] or "")) for r in subset)
        return {
            "clips": len(subset),
            "referenceWords": ref_words,
            "hypothesisWords": hyp_words,
            "wordEdits": edit_total,
            "werPercent": round(100 * edit_total / ref_words, 3) if ref_words else None,
            "cerPercent": round(100 * char_edits / ref_chars, 3) if ref_chars else None,
            "cerRawPercent": round(100 * raw_char_edits / raw_ref_chars, 3) if raw_ref_chars else None,
            "werPunctuationSensitivePercent": round(100 * raw_edits / raw_ref, 3) if raw_ref else None,
            "referencePunctuationMarks": ref_punct,
            "hypothesisPunctuationMarks": hyp_punct,
            "emptyTranscripts": sum(1 for r in subset if not (r["transcript"] or "").strip()),
        }

    variants = defaultdict(list)
    for r in scored:
        if "__" in r["id"]:
            variants[r["id"].split("__", 1)[1]].append(r)

    report = {
        "overall": score(scored),
        "groups": {k: score(v) for k, v in sorted(groups.items())},
        **({"variants": {k: score(v) for k, v in sorted(variants.items())}} if variants else {}),
        "nonSpeechOutcomes": {r["id"]: r.get("transcript", "").strip() for r in rows if not (r.get("reference") or "").strip()},
        "errors": {r["id"]: r["error"] for r in rows if r.get("error")},
        "latencyMs": {
            "modelLoad": stats([r["modelLoadMs"] for r in scored]),
            "modelReady": stats([r["modelReadyMs"] for r in scored]),
            "audioPrepare": stats([r.get("audioPrepareMs") for r in scored]),
            "initialize": stats([r["initializeMs"] for r in scored]),
            "inference": stats([r["inferenceMs"] for r in scored]),
            "cleanup": stats([r["cleanupMs"] for r in scored]),
            "transcribeTotal": stats([r["transcribeTotalMs"] for r in scored]),
            "audioLoad": stats([r.get("audioLoadMs", r.get("audioResampleMs")) for r in scored]),
        },
        "realTimeFactor": stats([r["realTimeFactor"] for r in scored if r.get("realTimeFactor") is not None]),
        "repetitions": len({r["repetition"] for r in rows}),
    }
    args.out.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n")
    print(json.dumps(report["overall"], indent=2))
    print(f"wrote {args.out}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
