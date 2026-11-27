#!/usr/bin/env python3
"""Score Round5 Speech Recognition and Dictation Experience dimensions cleanly without conflating metrics."""
from __future__ import annotations

import argparse
import json
import math
import re
import statistics
import sys
import unicodedata
from collections import defaultdict
from pathlib import Path
from typing import Any

PUNCT = re.compile(r"[^\w\s]", re.UNICODE)
DIGIT_CURRENCY_TOKEN = re.compile(r"(?:\$|R\$|US\$|€|£)?\d+(?:[.,:/-]\d+)*%?|\S+@\S+|\S+\.(?:com|io|org|net|ai|app|dev)\b", re.I)


def normalize_text(text: str) -> str:
    text = unicodedata.normalize("NFC", text or "").casefold().replace("’", "'").replace("‘", "'")
    text = re.sub(r"[–—]", " ", text)
    text = PUNCT.sub(" ", text)
    return " ".join(text.split())


def tokenize(text: str, strip_punctuation: bool = True) -> list[str]:
    text = unicodedata.normalize("NFC", text or "").casefold().replace("’", "'").replace("‘", "'")
    if strip_punctuation:
        text = re.sub(r"[–—]", " ", text)
        text = PUNCT.sub(" ", text)
        return re.findall(r"[^\W_]+(?:'[^\W_]+)*", text, flags=re.UNICODE)
    return re.findall(r"[^\W_]+(?:'[^\W_]+)*|[^\w\s]", text, flags=re.UNICODE)


def edits(reference: list[Any] | str, hypothesis: list[Any] | str) -> int:
    # Myers/DP edit distance bounded sensibly
    n, m = len(reference), len(hypothesis)
    if n == 0:
        return m
    if m == 0:
        return n
    prior = list(range(m + 1))
    for i, expected in enumerate(reference, 1):
        current = [i]
        for j, actual in enumerate(hypothesis, 1):
            cost = 0 if expected == actual else 1
            current.append(min(prior[j] + 1, current[-1] + 1, prior[j - 1] + cost))
        prior = current
    return prior[-1]


def pct_stats(values: list[float]) -> dict[str, Any] | None:
    vals = sorted(v for v in values if v is not None)
    if not vals:
        return None
    return {
        "n": len(vals),
        "mean": round(statistics.fmean(vals), 3),
        "p50": round(vals[(len(vals) - 1) // 2], 3),
        "p95": round(vals[min(len(vals) - 1, math.ceil(len(vals) * 0.95) - 1)], 3),
        "min": round(vals[0], 3),
        "max": round(vals[-1], 3),
    }


def score_asr(rows: list[dict], ref_key: str = "reference", hyp_key: str = "transcript") -> dict[str, Any]:
    speech = [r for r in rows if (r.get(ref_key) or r.get("reference") or "").strip() and not r.get("error")]
    ref_words_total = 0
    hyp_words_total = 0
    word_edits = 0
    norm_ref_chars = 0
    norm_char_edits = 0
    raw_edits = 0
    raw_ref = 0
    empty = 0

    for r in speech:
        ref = (r.get(ref_key) or r.get("reference") or "").strip()
        hyp = (r.get(hyp_key) or "").strip()
        if not hyp:
            empty += 1
        rt = tokenize(ref, True)
        ht = tokenize(hyp, True)
        ref_words_total += len(rt)
        hyp_words_total += len(ht)
        word_edits += edits(rt, ht)

        nref = normalize_text(ref)
        nhyp = normalize_text(hyp)
        norm_ref_chars += len(nref)
        norm_char_edits += edits(nref, nhyp)

        rt_p = tokenize(ref, False)
        ht_p = tokenize(hyp, False)
        raw_ref += len(rt_p)
        raw_edits += edits(rt_p, ht_p)

    # Warm timings skip row idx 0 if coldFirstClip is marked True
    warm_rows = [r for r in speech if not r.get("coldFirstClip")]
    if not warm_rows:
        warm_rows = speech
    latencies = [r.get("transcribeTotalMs") for r in warm_rows if r.get("transcribeTotalMs") is not None]
    rtfs = [r.get("realTimeFactor") for r in warm_rows if r.get("realTimeFactor") is not None]

    return {
        "clips": len(speech),
        "errors": sum(1 for r in rows if r.get("error")),
        "emptyTranscripts": empty,
        "referenceWords": ref_words_total,
        "hypothesisWords": hyp_words_total,
        "wordEdits": word_edits,
        "werPercent": round(100 * word_edits / ref_words_total, 3) if ref_words_total else None,
        "cerPercent": round(100 * norm_char_edits / norm_ref_chars, 3) if norm_ref_chars else None,
        "werPunctuationSensitivePercent": round(100 * raw_edits / raw_ref, 3) if raw_ref else None,
        "warmTranscribeMs": pct_stats(latencies),
        "warmRtf": pct_stats(rtfs),
    }


def score_dictation_intended(rows: list[dict], hyp_key: str = "transcript") -> dict[str, Any]:
    valid = [r for r in rows if (r.get("intended_text") or "").strip() and not r.get("error")]
    norm_chars = 0
    norm_char_edits = 0
    exact_chars = 0
    exact_char_edits = 0
    exact_matches = 0
    spec_tokens = 0
    spec_retained = 0

    for r in valid:
        target = r["intended_text"].strip()
        hyp = (r.get(hyp_key) or "").strip()
        if hyp == target:
            exact_matches += 1
        nt = normalize_text(target)
        nh = normalize_text(hyp)
        norm_chars += len(nt)
        norm_char_edits += edits(nt, nh)
        exact_chars += len(target)
        exact_char_edits += edits(target, hyp)

        tokens = DIGIT_CURRENCY_TOKEN.findall(target)
        spec_tokens += len(tokens)
        hyp_lower = hyp.casefold()
        for tok in tokens:
            if tok.casefold() in hyp_lower:
                spec_retained += 1

    return {
        "clips": len(valid),
        "intendedNormalizedCerPercent": round(100 * norm_char_edits / norm_chars, 3) if norm_chars else None,
        "intendedExactCerPercent": round(100 * exact_char_edits / exact_chars, 3) if exact_chars else None,
        "exactIntendedMatchCount": exact_matches,
        "exactIntendedMatchPercent": round(100 * exact_matches / len(valid), 2) if valid else None,
        "numericEmailUrlTokens": spec_tokens,
        "numericEmailUrlRetainedPercent": round(100 * spec_retained / spec_tokens, 2) if spec_tokens else None,
    }


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--corpus", required=True)
    parser.add_argument("--out", type=Path, required=True)
    parser.add_argument("--input", action="append", required=True, help="label=path.jsonl (or label:refined=path.jsonl)")
    args = parser.parse_args()

    results: dict[str, Any] = {"corpus": args.corpus, "engines": {}}
    for item in args.input:
        label, path_str = item.split("=", 1)
        hyp_key = "refinedText" if ":refined" in label else "transcript"
        rows = [json.loads(line) for line in Path(path_str).read_text().splitlines() if line.strip()]
        by_cat = defaultdict(list)
        for r in rows:
            cat = r.get("category") or r.get("language") or "all"
            by_cat[cat].append(r)

        entry: dict[str, Any] = {
            "speechRecognition": score_asr(rows, ref_key="spoken_text" if any(r.get("spoken_text") for r in rows) else "reference", hyp_key=hyp_key),
            "speechRecognitionByGroup": {
                k: score_asr(v, ref_key="spoken_text" if any(r.get("spoken_text") for r in v) else "reference", hyp_key=hyp_key)
                for k, v in sorted(by_cat.items())
            },
        }
        if any(r.get("intended_text") for r in rows):
            entry["dictationIntendedText"] = score_dictation_intended(rows, hyp_key=hyp_key)
            entry["dictationIntendedByDomain"] = {
                k: score_dictation_intended(v, hyp_key=hyp_key)
                for k, v in sorted(by_cat.items())
            }
        # Tarsila word-length stratification when present
        tarsila = [r for r in rows if (r.get("category") == "pt-conversation")]
        if tarsila:
            short = [r for r in tarsila if len(tokenize(r.get("reference") or "", True)) <= 5]
            med = [r for r in tarsila if 6 <= len(tokenize(r.get("reference") or "", True)) <= 15]
            long = [r for r in tarsila if len(tokenize(r.get("reference") or "", True)) > 15]
            entry["tarsilaByLength"] = {
                "<=5_words": score_asr(short, hyp_key=hyp_key),
                "6_15_words": score_asr(med, hyp_key=hyp_key),
                ">15_words": score_asr(long, hyp_key=hyp_key),
            }
        results["engines"][label] = entry

    args.out.parent.mkdir(parents=True, exist_ok=True)
    args.out.write_text(json.dumps(results, indent=2, ensure_ascii=False) + "\n")
    print(f"Scored {args.corpus} -> {args.out}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
