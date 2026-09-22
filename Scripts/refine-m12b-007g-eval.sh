#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

EXP_DIR="$ROOT/Evals/Refine/experiments/M12B-007G-strict-unresolved-language"
OUT="${1:-$EXP_DIR/reports}"
mkdir -p "$OUT" "$EXP_DIR"

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
echo "Running critical stability x5" >&2
"$ROOT/Scripts/refine-eval.sh" --split dev --output "$STABILITY_DIR" --critical-stability --repetitions 5

COHORT_DIR="$OUT/language-cohort"
mkdir -p "$COHORT_DIR"
python3 "$ROOT/Scripts/prepare-m12b-007f-unresolved-cohort.py" "$COHORT_DIR/corpus-root"
echo "Running M12B-007D/007F language cohort" >&2
"$ROOT/Scripts/refine-eval.sh" --split dev --output "$COHORT_DIR" --corpus-root "$COHORT_DIR/corpus-root"

python3 "$ROOT/Scripts/analyze-m12b-007g-strict-unresolved-language.py"
