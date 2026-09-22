#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

OUT="$ROOT/Evals/Refine/experiments/M12B-003-nochange-ambiguity/references/m12b-001-rerun"
mkdir -p "$OUT"

if ! rg -q 'static let version = "refine-v2-language"' "$ROOT/Rasc/AI/RefinementPrompt.swift"; then
  echo "M12B-001 prompt is not active; refusing to overwrite the matched reference." >&2
  exit 2
fi

run_split() {
  local split="$1"
  "$ROOT/Scripts/refine-eval.sh" --split "$split" --output "$OUT/$split"
}

run_split dev
run_split validation
run_split regression
"$ROOT/Scripts/refine-eval.sh" \
  --critical-stability \
  --repetitions 5 \
  --output "$OUT/stability"

echo "M12B-001 reference rerun complete → $OUT"
