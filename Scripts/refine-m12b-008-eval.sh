#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

EXP="Evals/Refine/experiments/M12B-008-integrated-reliability"
REPORTS="$EXP/reports"
SRC007G="$ROOT/Evals/Refine/experiments/M12B-007G-strict-unresolved-language/reports"
mkdir -p "$EXP" "$REPORTS"

echo "Recording production git SHA" >&2
git rev-parse HEAD > "$EXP/production-git-sha.txt"

copy_split() {
  local name="$1"
  shift || true
  if [[ -d "$SRC007G/$name" && "$name" != "holdout" ]]; then
    echo "Reusing M12B-007G $name reports (same accepted production stack)" >&2
    rm -rf "$REPORTS/$name"
    cp -R "$SRC007G/$name" "$REPORTS/$name"
    echo "m12b-007g-reuse-$(date -u +%Y-%m-%dT%H:%M:%SZ)" > "$REPORTS/$name/PROVENANCE.txt"
  else
    echo "Running split: $name" >&2
    mkdir -p "$REPORTS/$name"
    "$ROOT/Scripts/refine-eval.sh" --split "$name" --output "$REPORTS/$name" "$@"
  fi
}

copy_split dev
copy_split validation
copy_split regression --include-regression

STABILITY_DIR="$REPORTS/stability"
if [[ -d "$SRC007G/stability" ]]; then
  echo "Reusing M12B-007G stability reports" >&2
  rm -rf "$STABILITY_DIR"
  cp -R "$SRC007G/stability" "$STABILITY_DIR"
  echo "m12b-007g-reuse-$(date -u +%Y-%m-%dT%H:%M:%SZ)" > "$STABILITY_DIR/PROVENANCE.txt"
else
  mkdir -p "$STABILITY_DIR"
  "$ROOT/Scripts/refine-eval.sh" --split dev --output "$STABILITY_DIR" --critical-stability --repetitions 5
fi

echo "Running frozen holdout ONCE (first integrated checkpoint)" >&2
HOLDOUT_DIR="$REPORTS/holdout"
mkdir -p "$HOLDOUT_DIR"
HOLDOUT_STARTED="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
"$ROOT/Scripts/refine-eval.sh" --split holdout --output "$HOLDOUT_DIR"
HOLDOUT_FINISHED="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
cat > "$HOLDOUT_DIR/PROVENANCE.txt" <<EOF
holdoutRun=once
startedAt=${HOLDOUT_STARTED}
finishedAt=${HOLDOUT_FINISHED}
gitSha=$(git rev-parse HEAD)
corpus=Evals/Refine/corpus.v1.jsonl
splits=Evals/Refine/splits.v1.json
note=First post-M12B integrated holdout; not used for tuning in this task.
EOF

CHALLENGES="$REPORTS/challenges"
python3 "$ROOT/Scripts/prepare-m12b-008-challenge-corpora.py" "$CHALLENGES/corpus-root"

run_challenge() {
  local name="$1"
  local corpus="$2"
  local out="$CHALLENGES/$name"
  mkdir -p "$out"
  echo "Running challenge: $name" >&2
  "$ROOT/Scripts/refine-eval.sh" --split dev --output "$out" --corpus-root "$corpus"
}

run_challenge one-token "$CHALLENGES/corpus-root/one-token-challenge"
run_challenge semantic-protected "$CHALLENGES/corpus-root/semantic-protected-challenge"
run_challenge semantic-money "$CHALLENGES/corpus-root/semantic-money-challenge"
run_challenge semantic-percentage "$CHALLENGES/corpus-root/semantic-percentage-challenge"
run_challenge semantic-time "$CHALLENGES/corpus-root/semantic-time-challenge"
run_challenge selection "$CHALLENGES/corpus-root/selection-challenge"
run_challenge language-cohort "$CHALLENGES/corpus-root/language-cohort"

python3 "$ROOT/Scripts/analyze-m12b-008-integrated-reliability.py"
