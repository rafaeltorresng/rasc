#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
REPORTS="$ROOT/Evals/Refine/reports"
run() {
  local split="$1"
  local out="$REPORTS/baseline-${split}-v2"
  echo "=== baseline-${split}-v2 ===" >&2
  "$ROOT/Scripts/refine-eval.sh" --split "$split" --output "$out"
}
run dev
run validation
run holdout
run regression
"$ROOT/Scripts/refine-eval.sh" --critical-stability --repetitions 5 --output "$REPORTS/baseline-stability-v2"
echo "All baseline v2 runs complete." >&2
