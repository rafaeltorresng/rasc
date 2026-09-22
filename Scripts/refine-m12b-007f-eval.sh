#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

OUT="${1:-$ROOT/Evals/Refine/experiments/M12B-007F-unresolved-language-safety/reports}"
mkdir -p "$OUT" "$(dirname "$ROOT/Evals/Refine/experiments/M12B-007F-unresolved-language-safety/run.log")"

run_split() {
  local split="$1"
  shift
  local dir="$OUT/$split"
  mkdir -p "$dir"
  echo "Running split: $split" >&2
  "$ROOT/Scripts/refine-eval.sh" --split "$split" --output "$dir" "$@"
}

run_split dev
run_split validation
run_split regression --include-regression

STABILITY_DIR="$OUT/stability"
mkdir -p "$STABILITY_DIR"
echo "Running critical stability ×5" >&2
"$ROOT/Scripts/refine-eval.sh" --split dev --output "$STABILITY_DIR" --critical-stability --repetitions 5

COHORT_DIR="$OUT/unresolved-cohort"
mkdir -p "$COHORT_DIR"
python3 "$ROOT/Scripts/prepare-m12b-007f-unresolved-cohort.py" "$COHORT_DIR/corpus-root"
echo "Running unresolved-language cohort" >&2
"$ROOT/Scripts/refine-eval.sh" --split dev --output "$COHORT_DIR" --corpus-root "$COHORT_DIR/corpus-root"

python3 "$ROOT/Scripts/analyze-m12b-007f-unresolved-language-safety.py"
