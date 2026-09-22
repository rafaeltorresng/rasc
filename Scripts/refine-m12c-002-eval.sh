#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

EXP="Evals/Refine/experiments/M12C-002-global-refine-preference"
REPORTS="$EXP/reports"
M12C001="$ROOT/Evals/Refine/experiments/M12C-001-language-preference/reports"
mkdir -p "$EXP" "$REPORTS"

python3 "$ROOT/Scripts/generate-m12c-002-challenge-set.py"
git rev-parse HEAD > "$EXP/production-git-sha.txt"

python3 "$ROOT/Scripts/prepare-m12c-002-global-refine-preference-corpus.py" "$REPORTS/challenge-corpus-root"

echo "Running M12C-002 preference challenge" >&2
"$ROOT/Scripts/refine-eval.sh" --split dev --output "$REPORTS/preference-challenge" --corpus-root "$REPORTS/challenge-corpus-root"

echo "Running empty-preference dev" >&2
"$ROOT/Scripts/refine-eval.sh" --split dev --output "$REPORTS/empty-preference-dev"

echo "Running empty-preference validation" >&2
"$ROOT/Scripts/refine-eval.sh" --split validation --output "$REPORTS/empty-preference-validation"

echo "Running empty-preference regression" >&2
"$ROOT/Scripts/refine-eval.sh" --split regression --output "$REPORTS/empty-preference-regression" --include-regression

echo "Running preference stability subset x5" >&2
mkdir -p "$REPORTS/stability"
"$ROOT/Scripts/refine-eval.sh" \
  --split dev \
  --output "$REPORTS/stability" \
  --corpus-root "$REPORTS/challenge-corpus-root" \
  --filter concise \
  --filter casual \
  --filter adversarial \
  --repetitions 5

python3 "$ROOT/Scripts/analyze-m12c-002-global-refine-preference.py"
