#!/usr/bin/env bash
# Native AppKit suites. The test host uses its own bundle id so it can launch
# while the shipping app is open, and Debug builds refuse the personal database.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DERIVED="${DERIVED_DATA_PATH:-/tmp/rasc-native-tests}"
APP_DB="$HOME/Library/Application Support/Rasc/Rasc.sqlite"
CONTAINER_DB="$HOME/Library/Containers/com.rafaeltorres.rasc/Data/Library/Application Support/Rasc/Rasc.sqlite"

cleanup() {
  if [[ -z "${DERIVED_DATA_PATH:-}" && "${KEEP_DERIVED_DATA:-0}" != "1" ]]; then
    rm -rf "$DERIVED"
  fi
}
trap cleanup EXIT

stamp() {
  stat -f '%m %z' "$1" 2>/dev/null || echo "missing"
}

before_app="$(stamp "$APP_DB")"
before_container="$(stamp "$CONTAINER_DB")"

PACKAGE_ARGS=()
if [[ -d "$ROOT/.derivedData/Rasc/SourcePackages/checkouts" ]]; then
  PACKAGE_ARGS=(
    -clonedSourcePackagesDirPath "$ROOT/.derivedData/Rasc/SourcePackages"
    -disableAutomaticPackageResolution
  )
fi

if swift -e 'import Quartz; let d = CGSessionCopyCurrentDictionary() as? [String: Any]; print(d?["CGSSessionScreenIsLocked"] as? Int ?? 0)' 2>/dev/null | grep -qx '1'; then
  echo "note: macOS screen is locked (CGSSessionScreenIsLocked=1); live WindowServer key-window and occlusion tests require an unlocked session or CI." >&2
fi

xcodebuild test \
  -project "$ROOT/Rasc.xcodeproj" \
  -scheme Rasc \
  -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath "$DERIVED" \
  "${PACKAGE_ARGS[@]}" \
  CODE_SIGN_STYLE=Manual \
  CODE_SIGN_IDENTITY=- \
  DEVELOPMENT_TEAM= \
  RASC_APP_BUNDLE_IDENTIFIER=com.rafaeltorres.rasc.testhost \
  -only-testing:RascTests/PanelControllerTests \
  -only-testing:RascTests/HomeWindowControllerTests \
  -only-testing:RascTests/SettingsWindowPresentationTests \
  -only-testing:RascTests/WindowFrameStoreTests \
  -only-testing:RascTests/AppReliabilityLifecycleTests \
  -only-testing:RascTests/DisplayCoordinateTests \
  -only-testing:RascTests/ScratchpadPanelLevelPolicyTests \
  -only-testing:RascTests/SettingsWindowFitTests \
  -only-testing:RascTests/ShortcutKeycapTokenTests \
  -only-testing:RascTests/InternalShortcutStoreTests \
  -only-testing:RascTests/NaturalListEditingTests \
  -only-testing:RascTests/VisualTokenContrastTests \
  -only-testing:RascTests/TransientPanelSizingTests \
  -only-testing:RascTests/ScratchpadEditorCaretTests \
  -only-testing:RascTests/OnboardingBehaviorTests \
  -only-testing:RascTests/HomeSessionTests

after_app="$(stamp "$APP_DB")"
after_container="$(stamp "$CONTAINER_DB")"

if [[ "$before_app" != "$after_app" || "$before_container" != "$after_container" ]]; then
  echo "error: personal Rasc database changed during native tests" >&2
  echo "application support: $before_app -> $after_app" >&2
  echo "container: $before_container -> $after_container" >&2
  exit 1
fi

echo "Personal databases unchanged."
