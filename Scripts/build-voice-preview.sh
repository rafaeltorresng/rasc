#!/bin/bash
# Build an isolated local tester with the existing sandbox and an ad-hoc signature.
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
output="${RASC_VOICE_PREVIEW_OUTPUT:-${root}/build/voice-preview}"
derived="${RASC_VOICE_PREVIEW_DERIVED_DATA:-${output}/DerivedData}"
app="${output}/Rasc Voice Preview.app"

if [[ -e "${app}" ]]; then
  echo "Retain the current preview and pick a new RASC_VOICE_PREVIEW_OUTPUT before building again." >&2
  exit 1
fi

if [[ $# != 1 || ! -d "$1" ]]; then
  echo "Usage: $0 path-to-pinned-model-folder" >&2
  echo "Prepare a folder with Scripts/stage-voice-model.py." >&2
  exit 2
fi

mkdir -p "${output}"
stage="$(mktemp -d "${output}/.preview.XXXXXXXX")"
trap 'rm -rf -- "${stage}"' EXIT
xcodebuild -project "${root}/Rasc.xcodeproj" -scheme Rasc -configuration Release \
  -destination 'platform=macOS,arch=arm64' -derivedDataPath "${derived}" \
  -disableAutomaticPackageResolution PRODUCT_BUNDLE_IDENTIFIER=com.rafaeltorres.rasc.voicepreview \
  CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY=- DEVELOPMENT_TEAM= build

ditto "${derived}/Build/Products/Release/Rasc.app" "${stage}/Rasc.app"
python3 "${root}/Scripts/stage-voice-model.py" "${stage}/Rasc.app/Contents/Resources/VoiceModel" --from "$1"
/usr/libexec/PlistBuddy -c 'Set :CFBundleDisplayName Rasc Voice Preview' "${stage}/Rasc.app/Contents/Info.plist"
codesign --force --sign - --options runtime --entitlements "${root}/Rasc/Rasc.entitlements" "${stage}/Rasc.app"
codesign --verify --deep --strict "${stage}/Rasc.app"
mv "${stage}/Rasc.app" "${app}"
echo "${app}"
