#!/usr/bin/env bash
# Proof-only build: strong-link Sparkle, then replace default Library
# Validation with a library load constraint (LLC) that pins Sparkle's cdhash.
#
# Usage:
#   Scripts/sparkle-proof/build-variant-llc.sh <version> <build> <output-dir> [feed-url]
#
# Example:
#   Scripts/sparkle-proof/build-variant-llc.sh \
#     0.1.7 13 build/sparkle-proof/llc/dist/0.1.7
#
# Produces three apps from one compile:
#   Rasc-repro-no-llc.app     default LV, no constraint -> dyld Team ID crash
#   Rasc-llc.app              disable-library-validation + cdhash-pinned LLC
#   Rasc-llc-wrong-pin.app    valid Sparkle with a different cdhash, old pin
#
# This is not a production release procedure. It does not modify the project,
# the production feed, or any existing proof artifact.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
VERSION="${1:?usage: build-variant-llc.sh <version> <build> <output-dir> [feed-url]}"
BUILD_NUMBER="${2:?usage: build-variant-llc.sh <version> <build> <output-dir> [feed-url]}"
OUTPUT_DIR="${3:?usage: build-variant-llc.sh <version> <build> <output-dir> [feed-url]}"
FEED_URL="${4:-https://127.0.0.1:8443/appcast.xml}"

PROOF_DIR="${ROOT_DIR}/build/sparkle-proof"
KEYS_DIR="${SPARKLE_KEYS_DIR:-${PROOF_DIR}/keys}"
FRAMEWORK_SOURCE="${ROOT_DIR}/Vendor/Sparkle/Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework"
BASE_ENTITLEMENTS="${ROOT_DIR}/Rasc/Rasc.sparkle.entitlements"
DERIVED_DATA="${OUTPUT_DIR}/DerivedData"

PUBLIC_KEY="${SPARKLE_PUBLIC_KEY:-$(cat "${KEYS_DIR}/sparkle_public_key")}"
if [[ -z "${PUBLIC_KEY}" ]]; then
  echo "error: Sparkle public key is empty; set SPARKLE_PUBLIC_KEY" >&2
  exit 1
fi

for command in xcodebuild codesign ditto hdiutil install_name_tool /usr/libexec/PlistBuddy; do
  command -v "${command}" >/dev/null 2>&1 || {
    echo "error: required command not found: ${command}" >&2
    exit 1
  }
done

if [[ ! -d "${FRAMEWORK_SOURCE}" ]]; then
  echo "error: vendored Sparkle framework not found at ${FRAMEWORK_SOURCE}" >&2
  exit 1
fi

if [[ ! -f "${BASE_ENTITLEMENTS}" ]]; then
  echo "error: Sparkle entitlements not found at ${BASE_ENTITLEMENTS}" >&2
  exit 1
fi

rm -rf "${OUTPUT_DIR}"
mkdir -p "${OUTPUT_DIR}"
OUTPUT_DIR="$(cd "${OUTPUT_DIR}" && pwd)"
DERIVED_DATA="${OUTPUT_DIR}/DerivedData"

# Library validation is still enforced when an LLC is present alone. Apple's
# documented LLC adoption turns LV off with this entitlement, then constrains
# loading with the LLC. Keep it out of the repro app so the original failure is
# unchanged.
MERGED_ENTITLEMENTS="${OUTPUT_DIR}/Rasc.sparkle-llc.entitlements"
python3 - "${BASE_ENTITLEMENTS}" "${MERGED_ENTITLEMENTS}" <<'PY'
import plistlib
import sys

source, destination = sys.argv[1], sys.argv[2]
with open(source, "rb") as handle:
    entitlements = plistlib.load(handle)
entitlements["com.apple.security.cs.disable-library-validation"] = True
with open(destination, "wb") as handle:
    plistlib.dump(entitlements, handle)
PY

echo "==> Building Rasc ${VERSION} (${BUILD_NUMBER}) strong-linked against Sparkle..."
xcodebuild \
  -project "${ROOT_DIR}/Rasc.xcodeproj" \
  -scheme Rasc \
  -configuration Release \
  -derivedDataPath "${DERIVED_DATA}" \
  -destination 'platform=macOS,arch=arm64' \
  CODE_SIGN_STYLE=Manual \
  CODE_SIGN_IDENTITY=- \
  DEVELOPMENT_TEAM= \
  CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO \
  CODE_SIGN_ENTITLEMENTS="${MERGED_ENTITLEMENTS}" \
  OTHER_LDFLAGS="-framework Sparkle" \
  MARKETING_VERSION="${VERSION}" \
  CURRENT_PROJECT_VERSION="${BUILD_NUMBER}" \
  clean build

APP="${DERIVED_DATA}/Build/Products/Release/Rasc.app"
XCENT="${DERIVED_DATA}/Build/Intermediates.noindex/Rasc.build/Release/Rasc.build/Rasc.app.xcent"

if [[ ! -d "${APP}" ]]; then
  echo "error: built app not found at ${APP}" >&2
  exit 1
fi
if [[ ! -f "${XCENT}" ]]; then
  echo "error: expanded entitlements not found at ${XCENT}" >&2
  exit 1
fi

echo "==> Expanded entitlements:"
plutil -p "${XCENT}"
if grep -q '\$(' "${XCENT}"; then
  echo "error: build settings were not expanded in ${XCENT}" >&2
  exit 1
fi

REPRO_ENTITLEMENTS="${OUTPUT_DIR}/Rasc.sparkle-base.entitlements"
python3 - "${XCENT}" "${REPRO_ENTITLEMENTS}" <<'PY'
import plistlib
import sys

source, destination = sys.argv[1], sys.argv[2]
with open(source, "rb") as handle:
    entitlements = plistlib.load(handle)
entitlements.pop("com.apple.security.cs.disable-library-validation", None)
with open(destination, "wb") as handle:
    plistlib.dump(entitlements, handle)
PY

echo "==> Confirming Sparkle is strong-linked..."
SPARKLE_LOAD_COMMAND="$(otool -l "${APP}/Contents/MacOS/Rasc" | awk '
  /cmd LC_LOAD/ { command = $2 }
  /Sparkle\.framework/ { print command; exit }
')"
if [[ "${SPARKLE_LOAD_COMMAND}" != "LC_LOAD_DYLIB" ]]; then
  echo "error: Rasc is not strong-linked against Sparkle (found ${SPARKLE_LOAD_COMMAND:-nothing})" >&2
  otool -l "${APP}/Contents/MacOS/Rasc" | grep -B2 -A4 'Sparkle' >&2 || true
  exit 1
fi

echo "==> Pointing the test build at ${FEED_URL} and the test public key..."
/usr/libexec/PlistBuddy -c "Set :SUFeedURL ${FEED_URL}" "${APP}/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :SUPublicEDKey ${PUBLIC_KEY}" "${APP}/Contents/Info.plist"

embed_and_sign_sparkle() {
  local app="$1"
  local framework="$2"
  mkdir -p "${app}/Contents/Frameworks"
  ditto "${FRAMEWORK_SOURCE}" "${framework}"
  codesign --force --sign - --options runtime \
    --preserve-metadata=identifier,entitlements \
    "${framework}/Versions/B/XPCServices/Installer.xpc"
  codesign --force --sign - --options runtime \
    --preserve-metadata=identifier,entitlements \
    "${framework}/Versions/B/XPCServices/Downloader.xpc"
  codesign --force --sign - --options runtime \
    --preserve-metadata=identifier,entitlements \
    "${framework}/Versions/B/Autoupdate"
  codesign --force --sign - --options runtime \
    --preserve-metadata=identifier,entitlements \
    "${framework}/Versions/B/Updater.app"
  codesign --force --sign - --options runtime \
    --preserve-metadata=identifier,entitlements \
    "${framework}"
}

cdhash_of() {
  codesign -dvvv "$1" 2>&1 | awk -F= '/^CDHash=/{print $2}'
}

sign_app() {
  local app="$1"
  local entitlements="$2"
  shift 2
  codesign --force --sign - --options runtime --entitlements "${entitlements}" "$@" "${app}"
}

echo "==> Staging repro app (default Library Validation, no LLC)..."
APP_REPRO="${OUTPUT_DIR}/Rasc-repro-no-llc.app"
ditto "${APP}" "${APP_REPRO}"
embed_and_sign_sparkle "${APP_REPRO}" "${APP_REPRO}/Contents/Frameworks/Sparkle.framework"
sign_app "${APP_REPRO}" "${REPRO_ENTITLEMENTS}"
codesign --verify --deep --strict --verbose=2 "${APP_REPRO}"

echo "==> Staging LLC app (LV off + cdhash-pinned LLC)..."
APP_LLC="${OUTPUT_DIR}/Rasc-llc.app"
ditto "${APP}" "${APP_LLC}"
FRAMEWORK_LLC="${APP_LLC}/Contents/Frameworks/Sparkle.framework"
embed_and_sign_sparkle "${APP_LLC}" "${FRAMEWORK_LLC}"
SPARKLE_CDHASH="$(cdhash_of "${FRAMEWORK_LLC}/Versions/B/Sparkle")"
if [[ -z "${SPARKLE_CDHASH}" ]]; then
  echo "error: could not read Sparkle cdhash" >&2
  exit 1
fi
echo "==> Pinning Sparkle cdhash ${SPARKLE_CDHASH}"

LLC_PLIST="${OUTPUT_DIR}/library-constraint.plist"
python3 - "${SPARKLE_CDHASH}" "${LLC_PLIST}" <<'PY'
import plistlib
import sys

cdhash_hex, destination = sys.argv[1], sys.argv[2]
constraint = {"cdhash": {"$in": [bytes.fromhex(cdhash_hex)]}}
with open(destination, "wb") as handle:
    plistlib.dump(constraint, handle)
PY

codesign --validate-constraint "${LLC_PLIST}"
sign_app "${APP_LLC}" "${XCENT}" --library-constraint "${LLC_PLIST}"
codesign --verify --deep --strict --verbose=2 "${APP_LLC}"

echo "==> Staging wrong-pin app (valid Sparkle, different cdhash, stale pin)..."
APP_NEG="${OUTPUT_DIR}/Rasc-llc-wrong-pin.app"
ditto "${APP_LLC}" "${APP_NEG}"
FRAMEWORK_NEG="${APP_NEG}/Contents/Frameworks/Sparkle.framework"
# Change a load command without affecting the framework's behavior, then
# re-sign so the result is a valid library with a different cdhash.
install_name_tool -add_rpath "@executable_path/../Frameworks/SparkleProofNegative" \
  "${FRAMEWORK_NEG}/Versions/B/Sparkle"
codesign --force --sign - --options runtime \
  --preserve-metadata=identifier,entitlements \
  "${FRAMEWORK_NEG}"
NEG_CDHASH="$(cdhash_of "${FRAMEWORK_NEG}/Versions/B/Sparkle")"
if [[ "${NEG_CDHASH}" == "${SPARKLE_CDHASH}" ]]; then
  echo "error: negative control did not change Sparkle's cdhash" >&2
  exit 1
fi
echo "==> Negative control Sparkle cdhash ${NEG_CDHASH}"
# Re-seal the app while keeping the original (now wrong) pin.
sign_app "${APP_NEG}" "${XCENT}" --library-constraint "${LLC_PLIST}"
codesign --verify --deep --strict --verbose=2 "${APP_NEG}"

echo
echo "Repro app:      ${APP_REPRO}"
echo "LLC app:        ${APP_LLC}"
echo "Wrong-pin app:  ${APP_NEG}"
echo "Pinned cdhash:  ${SPARKLE_CDHASH}"
echo "Wrong cdhash:   ${NEG_CDHASH}"
echo
echo "Expected: repro and wrong-pin crash at launch outside Xcode; LLC app launches"
echo "with Sparkle.framework mapped and the updater constructed."
