#!/usr/bin/env python3
"""Summarize paired voice runs without republishing inputs or hypotheses."""
import argparse
import json
import statistics
from pathlib import Path

from rapidfuzz.distance import Levenshtein

from score_round5 import tokenize


def evaluate(row, entry):
    reference = tokenize(row["reference"])
    actual = tokenize(row["transcript"])
    editops = Levenshtein.editops(reference, actual)
    deletions = []
    duplicates = 0
    unmatched = set()
    for edit in editops.as_opcodes():
        if edit.tag in {"delete", "replace"}:
            unmatched.update(range(edit.src_start, edit.src_end))
        if edit.tag == "delete":
            deletions.append((edit.src_start, edit.src_end - edit.src_start))
        if edit.tag == "insert":
            inserted = actual[edit.dest_start:edit.dest_end]
            count = len(inserted)
            if (inserted == actual[max(0, edit.dest_start - count):edit.dest_start]
                    or inserted == actual[edit.dest_end:edit.dest_end + count]):
                duplicates += count
    span_stats = []
    boundary_edits = 0
    cursor = 0
    for span in entry.get("referenceSpans", []):
        count = len(tokenize(span["reference"]))
        if not count:
            continue
        if cursor:
            boundary_edits += len(unmatched.intersection(range(cursor - 1, cursor + 1)))
        matches = count - len(unmatched.intersection(range(cursor, cursor + count)))
        duration = span["end"] - span["start"]
        span_stats.append((matches / count, duration))
        cursor += count
    return {
        "id": row["id"],
        "duration_s": row["audioSeconds"],
        "frames_16k": row["resampledFrames"],
        "resample_ms": round(row["resampleMs"], 3),
        "decode_ms": round(row["transcribeTotalMs"], 3),
        "post_decode_physical_footprint_mib": round(row["physFootprintMiB"], 3),
        "reference_words": len(reference),
        "word_edits": len(editops),
        "exact_matches_in_order": len(reference) - len(unmatched),
        "longest_deletion_words": max((n for _, n in deletions), default=0),
        "deletions_5_plus_words": sum(n >= 5 for _, n in deletions),
        "adjacent_duplicate_inserted_words": duplicates,
        "reference_span_boundary_words_unmatched": boundary_edits if span_stats else None,
        "reference_spans": len(span_stats),
        "spans_below_half_exact_match": sum(ratio < 0.5 for ratio, _ in span_stats),
        "span_seconds": round(sum(duration for _, duration in span_stats), 3),
        "span_seconds_below_half_exact_match": round(sum(d for ratio, d in span_stats if ratio < 0.5), 3),
        "empty": bool(reference) and not actual and not row.get("error"),
        "text_on_silence": row["id"].startswith("all_silence_") and bool(actual),
        "error": row.get("error"),
    }


def summarize(rows):
    words = sum(r["reference_words"] for r in rows)
    edits = sum(r["word_edits"] for r in rows)
    matches = sum(r["exact_matches_in_order"] for r in rows)
    latencies = sorted(r["decode_ms"] for r in rows if not r["error"])
    return {
        "clips": len(rows),
        "word_errors_percent": round(100 * edits / words, 3) if words else None,
        "exact_matches_in_order_percent": round(100 * matches / words, 3) if words else None,
        "decode_ms_p50": round(statistics.median(latencies), 3) if latencies else None,
        "decode_ms_max": max(latencies, default=None),
        "longest_deletion_words": max(r["longest_deletion_words"] for r in rows),
        "deletions_5_plus_words": sum(r["deletions_5_plus_words"] for r in rows),
        "adjacent_duplicate_inserted_words": sum(r["adjacent_duplicate_inserted_words"] for r in rows),
        "reference_span_boundary_words_unmatched": sum(r["reference_span_boundary_words_unmatched"] or 0 for r in rows),
        "reference_spans": sum(r["reference_spans"] for r in rows),
        "spans_below_half_exact_match": sum(r["spans_below_half_exact_match"] for r in rows),
        "span_seconds": round(sum(r["span_seconds"] for r in rows), 3),
        "span_seconds_below_half_exact_match": round(sum(r["span_seconds_below_half_exact_match"] for r in rows), 3),
        "empty": sum(r["empty"] for r in rows),
        "text_on_silence": sum(r["text_on_silence"] for r in rows),
        "failed": sum(bool(r["error"]) for r in rows),
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--manifest", type=Path, required=True)
    parser.add_argument("--out", type=Path, required=True)
    parser.add_argument("--exclude", action="append", default=[])
    parser.add_argument("raw", nargs="+", metavar="LABEL=PATH")
    args = parser.parse_args()
    manifest = {r["id"]: r for r in json.loads(args.manifest.read_text())}
    expected_ids = set(manifest) - set(args.exclude)
    results = {}
    for item in args.raw:
        label, path = item.split("=", 1)
        by_strategy = {}
        for line in Path(path).read_text().splitlines():
            row = json.loads(line)
            if row["id"] not in expected_ids:
                continue
            key = row["strategy"] if label == "pair" else label
            by_strategy.setdefault(key, []).append(evaluate(row, manifest[row["id"]]))
        for strategy, rows in by_strategy.items():
            if len(rows) != len(expected_ids) or {r["id"] for r in rows} != expected_ids:
                raise ValueError(f"{strategy}: incomplete or repeated input set")
            results[strategy] = {"summary": summarize(rows), "clips": rows}
    if not results:
        raise ValueError("No matching benchmark rows")
    args.out.write_text(json.dumps(results, indent=2) + "\n")


if __name__ == "__main__":
    main()
