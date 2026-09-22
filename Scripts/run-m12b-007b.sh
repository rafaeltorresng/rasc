#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

OUT="$ROOT/Evals/Refine/experiments/M12B-007B-language-resolver-v2"
REPORTS="$OUT/reports"
mkdir -p "$REPORTS"

echo "Step 1: rerun M12B-007A resolver-only eval after boundary fix" >&2
Scripts/refine-resolver-eval.sh --output "$ROOT/Evals/Refine/experiments/M12B-007A-language-resolver"
python3 Scripts/analyze-m12b-007a-language-resolver.py

STEP1_ACC=$(python3 - <<'PY'
import json
from pathlib import Path
analysis = json.loads(Path("Evals/Refine/experiments/M12B-007A-language-resolver/analysis.json").read_text())
print(analysis["candidate"]["summary"]["overallAccuracy"])
PY
)
PRIOR_ACC="0.7347"
python3 - <<PY
prior = float("$PRIOR_ACC")
current = float("$STEP1_ACC")
if current + 0.02 < prior:
    raise SystemExit(f"Step 1 gate FAIL: boundary fix dropped accuracy {prior:.4f} -> {current:.4f}")
print(f"Step 1 gate PASS: {prior:.4f} -> {current:.4f}")
PY

echo "Step 2: run end-to-end eval slices" >&2
Scripts/refine-eval.sh --split dev --output "$REPORTS/dev"
Scripts/refine-eval.sh --split validation --output "$REPORTS/validation"
Scripts/refine-eval.sh --split regression --include-regression --output "$REPORTS/regression"
Scripts/refine-eval.sh --critical-stability --repetitions 5 --output "$REPORTS/stability"

python3 Scripts/analyze-m12b-007b-language-resolver-v2.py prepare-language-slice
RASC_EVAL_ROOT="/private/tmp/rasc-m12b-007b-language-slice" Scripts/refine-eval.sh --split dev --output "$REPORTS/language-slice"

python3 Scripts/analyze-m12b-007b-language-resolver-v2.py analyze
echo "M12B-007B complete → $REPORTS" >&2
