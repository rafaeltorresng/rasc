#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
EXP="$ROOT/Evals/Refine/experiments/M12B-001-language-contract"
mkdir -p "$EXP/reports"
BASELINE="$ROOT/Evals/Refine/reports"
run() {
  local split="$1"
  local out="$EXP/reports/${split}"
  "$ROOT/Scripts/refine-eval.sh" --split "$split" --output "$out" --compare "$BASELINE/baseline-${split}-v2"
}
run dev
run validation
run regression
"$ROOT/Scripts/refine-eval.sh" --critical-stability --repetitions 5 --output "$EXP/reports/stability" --compare "$BASELINE/baseline-stability-v2"
echo "M12B-001 evals complete → $EXP/reports"
