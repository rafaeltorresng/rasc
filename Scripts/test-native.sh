#!/usr/bin/env bash
# Native AppKit suites. The test host uses its own bundle id so it can launch
# while the shipping app is open, and Debug builds refuse the personal database.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DERIVED="${DERIVED_DATA_PATH:-/tmp/rasc-native-tests}"
APP_DB="$HOME/Library/Application Support/Rasc/Rasc.sqlite"
CONTAINER_DB="$HOME/Library/Containers/com.rafaeltorres.rasc/Data/Library/Application Support/Rasc/Rasc.sqlite"

stamp() {
  stat -f '%m %z' "$1" 2>/dev/null || echo "missing"
}

before_app="$(stamp "$APP_DB")"
before_container="$(stamp "$CONTAINER_DB")"

xcodebuild test \
  -project "$ROOT/Rasc.xcodeproj" \
  -scheme Rasc \
  -destination 'platform=macOS' \
  -derivedDataPath "$DERIVED" \
  -only-testing:RascTests/PanelControllerTests \
  -only-testing:RascTests/HomeWindowControllerTests \
  -only-testing:RascTests/SettingsWindowPresentationTests \
  -only-testing:RascTests/WindowFrameStoreTests \
  -only-testing:RascTests/AppReliabilityLifecycleTests \
  -only-testing:RascTests/QualitySprintTests \
  PRODUCT_BUNDLE_IDENTIFIER=com.rafaeltorres.rasc.tests

after_app="$(stamp "$APP_DB")"
after_container="$(stamp "$CONTAINER_DB")"

if [[ "$before_app" != "$after_app" || "$before_container" != "$after_container" ]]; then
  echo "error: personal Rasc database changed during native tests" >&2
  echo "application support: $before_app -> $after_app" >&2
  echo "container: $before_container -> $after_container" >&2
  exit 1
fi

echo "Personal databases unchanged."
