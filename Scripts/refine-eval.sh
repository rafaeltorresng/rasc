#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

SPLIT="dev"
OUTPUT=""
FILTER=""
REPETITIONS=1
CRITICAL_ONLY=0
INCLUDE_REGRESSION=0
COMPARE=""
CORPUS_ROOT="${RASC_EVAL_ROOT:-$ROOT/Evals/Refine}"

usage() {
  cat <<'EOF'
Usage: Scripts/refine-eval.sh [options]

Runs the production-faithful Refine reliability evaluation harness (DEBUG only).

Options:
  --split <dev|validation|holdout|all|regression>   Dataset split (default: dev)
  --output <path>                                   Output directory for reports
  --filter <tag-or-category>                        Filter cases (repeatable)
  --repetitions <n>                                 Repetitions per case (default: 1)
  --critical-stability                              Run curated critical/review subset
  --include-regression                              Include permanent regression corpus
  --compare <baseline-output-dir>                   Compare against prior summary.json
  --corpus-root <path>                              Override Evals/Refine location
  -h, --help                                        Show help

Examples:
  Scripts/refine-eval.sh --split dev --output /tmp/refine-baseline
  Scripts/refine-eval.sh --critical-stability --repetitions 5 --output /tmp/refine-stability
  Scripts/refine-eval.sh --split all --compare /tmp/refine-baseline --output /tmp/refine-candidate
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --split)
      SPLIT="$2"; shift 2 ;;
    --output)
      OUTPUT="$2"; shift 2 ;;
    --filter)
      FILTER="$FILTER $2"; shift 2 ;;
    --repetitions)
      REPETITIONS="$2"; shift 2 ;;
    --critical-stability)
      CRITICAL_ONLY=1; shift ;;
    --include-regression)
      INCLUDE_REGRESSION=1; shift ;;
    --compare)
      COMPARE="$2"; shift 2 ;;
    --corpus-root)
      CORPUS_ROOT="$2"; shift 2 ;;
    -h|--help)
      usage; exit 0 ;;
    *)
      echo "Unknown option: $1" >&2
      usage
      exit 1 ;;
  esac
done

if [[ -z "$OUTPUT" ]]; then
  OUTPUT="$ROOT/Evals/Refine/reports/$(date +%Y%m%d-%H%M%S)-${SPLIT}"
fi
mkdir -p "$OUTPUT"

if [[ ! -f "$ROOT/Evals/Refine/corpus.v1.jsonl" ]]; then
  echo "Generating evaluation corpus..." >&2
  python3 "$ROOT/Scripts/generate-refine-eval-corpus.py"
fi

DERIVED_DATA="${DERIVED_DATA:-$ROOT/.derivedData}"
xcodebuild -project Rasc.xcodeproj -scheme Rasc -configuration Debug -derivedDataPath "$DERIVED_DATA" build -quiet

APP="$DERIVED_DATA/Build/Products/Debug/Rasc.app/Contents/MacOS/Rasc"
if [[ ! -x "$APP" ]]; then
  echo "Could not find Debug Rasc binary at $APP" >&2
  exit 1
fi

ARGS=(--run-refine-evals --split "$SPLIT" --output "$OUTPUT" --repetitions "$REPETITIONS" --corpus-root "$CORPUS_ROOT")
for token in $FILTER; do
  ARGS+=(--filter "$token")
done
if [[ "$CRITICAL_ONLY" -eq 1 ]]; then
  ARGS+=(--critical-stability)
fi
if [[ "$INCLUDE_REGRESSION" -eq 1 || "$SPLIT" == "regression" ]]; then
  ARGS+=(--include-regression)
fi
if [[ -n "$COMPARE" ]]; then
  ARGS+=(--compare "$COMPARE")
fi

echo "Running Refine eval → $OUTPUT" >&2
"$APP" "${ARGS[@]}"
echo "Reports written to $OUTPUT" >&2
