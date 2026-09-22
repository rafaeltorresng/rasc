#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

EXP="Evals/Refine/experiments/M12C-001-language-preference"
REPORTS="$EXP/reports"
REFINE_V2="$ROOT/Evals/Refine/experiments/M12B-008-integrated-reliability/reports"
mkdir -p "$EXP" "$REPORTS"

echo "Recording production git SHA" >&2
git rev-parse HEAD > "$EXP/production-git-sha.txt"

python3 "$ROOT/Scripts/prepare-m12c-001-language-preference-corpus.py" "$REPORTS/corpus-root"

echo "Running M12C language-preference corpus" >&2
"$ROOT/Scripts/refine-eval.sh" --split dev --output "$REPORTS/language-preference" --corpus-root "$REPORTS/corpus-root"

echo "Running matchNote regression: dev" >&2
"$ROOT/Scripts/refine-eval.sh" --split dev --output "$REPORTS/matchnote-regression-dev"

echo "Running matchNote regression: validation" >&2
"$ROOT/Scripts/refine-eval.sh" --split validation --output "$REPORTS/matchnote-regression-validation"

echo "Running matchNote regression corpus" >&2
"$ROOT/Scripts/refine-eval.sh" --split regression --output "$REPORTS/matchnote-regression" --include-regression

python3 "$ROOT/Scripts/analyze-m12c-001-language-preference.py"
