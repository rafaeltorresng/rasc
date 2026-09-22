#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
CORPUS_ROOT="${RASC_EVAL_ROOT:-$ROOT/Evals/Refine}"
DERIVED_DATA="${DERIVED_DATA:-$ROOT/.derivedData}"
PORT="${REFINE_REVIEW_PORT:-8765}"

usage() {
  cat <<'EOF'
Usage: Scripts/refine-review.sh [options]

Local maintainer review workflow for Refine eval adjudication.

Options:
  --generate-queue          Regenerate priority-queue.v1.json
  --include-holdout         Include holdout cases (off by default)
  --queue review-queue-75   Review the 75-case queue instead of priority queue
  --status                  Print adjudication / review-queue status JSON
  --port <n>                Local server port (default: 8765)
  -h, --help                Show help

Examples:
  Scripts/refine-review.sh --generate-queue
  Scripts/refine-review.sh
  Scripts/refine-review.sh --queue review-queue-75
  Scripts/refine-adjudicate-apply.sh
EOF
}

GENERATE=0
INCLUDE_HOLDOUT=0
QUEUE_MODE="priority"
STATUS_ONLY=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --generate-queue) GENERATE=1; shift ;;
    --include-holdout) INCLUDE_HOLDOUT=1; shift ;;
    --queue)
      QUEUE_MODE="$2"; shift 2 ;;
    --status) STATUS_ONLY=1; shift ;;
    --port) PORT="$2"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown option: $1" >&2; usage; exit 1 ;;
  esac
done

xcodebuild -project Rasc.xcodeproj -scheme Rasc -configuration Debug -derivedDataPath "$DERIVED_DATA" build -quiet
APP="$DERIVED_DATA/Build/Products/Debug/Rasc.app/Contents/MacOS/Rasc"

ARGS=()
if [[ "$GENERATE" -eq 1 ]]; then
  ARGS+=(--refine-review-generate-queue)
  [[ "$INCLUDE_HOLDOUT" -eq 1 ]] && ARGS+=(--include-holdout)
fi
if [[ "$STATUS_ONLY" -eq 1 ]]; then
  ARGS=(--refine-review-status)
fi

if [[ ${#ARGS[@]} -gt 0 ]]; then
  "$APP" "${ARGS[@]}"
fi

if [[ "$STATUS_ONLY" -eq 1 ]]; then
  exit 0
fi

export RASC_EVAL_ROOT="$CORPUS_ROOT"
export REFINE_REVIEW_PORT="$PORT"
export REFINE_REVIEW_QUEUE_MODE="$QUEUE_MODE"
[[ "$INCLUDE_HOLDOUT" -eq 1 ]] && export REFINE_REVIEW_INCLUDE_HOLDOUT=1
exec python3 "$ROOT/Scripts/refine-review-server.py"
