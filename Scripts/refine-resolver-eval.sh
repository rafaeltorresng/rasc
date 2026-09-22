#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

OUTPUT=""
CORPUS_ROOT="${RASC_EVAL_ROOT:-$ROOT/Evals/Refine}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --output)
      OUTPUT="$2"; shift 2 ;;
    --corpus-root)
      CORPUS_ROOT="$2"; shift 2 ;;
    -h|--help)
      cat <<'EOF'
Usage: Scripts/refine-resolver-eval.sh --output <dir> [--corpus-root <path>]

Runs the evaluation-only language resolver benchmark (no Foundation Models).
EOF
      exit 0 ;;
    *)
      echo "Unknown option: $1" >&2; exit 1 ;;
  esac
done

if [[ -z "$OUTPUT" ]]; then
  OUTPUT="$ROOT/Evals/Refine/experiments/M12B-007A-language-resolver/resolver-results.json"
  mkdir -p "$(dirname "$OUTPUT")"
  OUTPUT="$(dirname "$OUTPUT")"
fi
mkdir -p "$OUTPUT"

DERIVED_DATA="${DERIVED_DATA:-$ROOT/.derivedData}"
xcodebuild -project Rasc.xcodeproj -scheme Rasc -configuration Debug -derivedDataPath "$DERIVED_DATA" build -quiet

APP="$DERIVED_DATA/Build/Products/Debug/Rasc.app/Contents/MacOS/Rasc"
"$APP" --run-refine-resolver-eval --output "$OUTPUT" --corpus-root "$CORPUS_ROOT"
