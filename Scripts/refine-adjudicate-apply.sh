#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
DERIVED_DATA="${DERIVED_DATA:-$ROOT/.derivedData}"
xcodebuild -project Rasc.xcodeproj -scheme Rasc -configuration Debug -derivedDataPath "$DERIVED_DATA" build -quiet
APP="$DERIVED_DATA/Build/Products/Debug/Rasc.app/Contents/MacOS/Rasc"
"$APP" --refine-review-apply-adjudications
