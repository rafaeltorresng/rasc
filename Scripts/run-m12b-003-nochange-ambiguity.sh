#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

EXP="$ROOT/Evals/Refine/experiments/M12B-003-nochange-ambiguity"
BASELINE="$ROOT/Evals/Refine/reports"
mkdir -p "$EXP/reports"

if ! rg -q 'static let version = "refine-v3-nochange-ambiguity"' "$ROOT/Rasc/AI/RefinementPrompt.swift"; then
  echo "M12B-003 candidate prompt is not active; refusing to overwrite candidate reports." >&2
  exit 2
fi

run_split() {
  local split="$1"
  "$ROOT/Scripts/refine-eval.sh" \
    --split "$split" \
    --output "$EXP/reports/$split" \
    --compare "$BASELINE/baseline-${split}-v2"
}

run_split dev
run_split validation
run_split regression

"$ROOT/Scripts/refine-eval.sh" \
  --critical-stability \
  --repetitions 5 \
  --output "$EXP/reports/stability" \
  --compare "$BASELINE/baseline-stability-v2"

echo "M12B-003 evals complete → $EXP/reports"
