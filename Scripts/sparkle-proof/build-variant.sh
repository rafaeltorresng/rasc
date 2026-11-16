#!/usr/bin/env bash
# Build one proof variant with Sparkle embedded and ad-hoc signed.
#
# Usage:
#   Scripts/sparkle-proof/build-variant.sh <version> <build> <output-dir> [feed-url]
#
# Example:
#   Scripts/sparkle-proof/build-variant.sh 0.1.7 13 build/sparkle-proof/repro/dist/0.1.7
#
# This intentionally uses ad-hoc signing. The app is weak-linked against
# Sparkle, so it launches, but Hardened Runtime's Library Validation rejects the
# embedded framework because the app and framework have no matching Team ID.
# The updater is therefore unavailable. See docs/SPARKLE-UPDATES.md.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
VERSION="${1:?usage: build-variant.sh <version> <build> <output-dir> [feed-url]}"
BUILD_NUMBER="${2:?usage: build-variant.sh <version> <build> <output-dir> [feed-url]}"
OUTPUT_DIR="${3:?usage: build-variant.sh <version> <build> <output-dir> [feed-url]}"
FEED_URL="${4:-https://127.0.0.1:8443/appcast.xml}"

PROOF_DIR="${ROOT_DIR}/build/sparkle-proof"
KEYS_DIR="${SPARKLE_KEYS_DIR:-${PROOF_DIR}/keys}"
FRAMEWORK_SOURCE="${ROOT_DIR}/Vendor/Sparkle/Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework"
ENTITLEMENTS="${ROOT_DIR}/Rasc/Rasc.sparkle.entitlements"
DERIVED_DATA="${OUTPUT_DIR}/DerivedData"

PUBLIC_KEY="${SPARKLE_PUBLIC_KEY:-$(cat "${KEYS_DIR}/sparkle_public_key")}"
if [[ -z "${PUBLIC_KEY}" ]]; then
  echo "error: Sparkle public key is empty; set SPARKLE_PUBLIC_KEY" >&2
  exit 1
fi

for command in xcodebuild codesign ditto hdiutil /usr/libexec/PlistBuddy; do
  command -v "${command}" >/dev/null 2>&1 || {
    echo "error: required command not found: ${command}" >&2
    exit 1
  }
done

if [[ ! -d "${FRAMEWORK_SOURCE}" ]]; then
  echo "error: vendored Sparkle framework not found at ${FRAMEWORK_SOURCE}" >&2
  exit 1
fi

if [[ ! -f "${ENTITLEMENTS}" ]]; then
  echo "error: Sparkle entitlements not found at ${ENTITLEMENTS}" >&2
  exit 1
fi

rm -rf "${OUTPUT_DIR}"
mkdir -p "${OUTPUT_DIR}/dmg-staging"

echo "==> Building Rasc ${VERSION} (${BUILD_NUMBER}) with Sparkle entitlements..."
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
  CODE_SIGN_ENTITLEMENTS="${ENTITLEMENTS}" \
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

echo "==> Pointing the test build at ${FEED_URL} and the test public key..."
/usr/libexec/PlistBuddy -c "Set :SUFeedURL ${FEED_URL}" "${APP}/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :SUPublicEDKey ${PUBLIC_KEY}" "${APP}/Contents/Info.plist"

echo "==> Embedding and signing Sparkle..."
FRAMEWORK="${APP}/Contents/Frameworks/Sparkle.framework"
mkdir -p "${APP}/Contents/Frameworks"
ditto "${FRAMEWORK_SOURCE}" "${FRAMEWORK}"

sign_nested() {
  codesign --force --sign - --options runtime \
    --preserve-metadata=identifier,entitlements \
    "$1"
}

sign_nested "${FRAMEWORK}/Versions/B/XPCServices/Installer.xpc"
sign_nested "${FRAMEWORK}/Versions/B/XPCServices/Downloader.xpc"
sign_nested "${FRAMEWORK}/Versions/B/Autoupdate"
sign_nested "${FRAMEWORK}/Versions/B/Updater.app"
sign_nested "${FRAMEWORK}"

echo "==> Re-signing the app with the expanded entitlements..."
codesign --force --sign - --options runtime --entitlements "${XCENT}" "${APP}"

echo "==> Verifying nested signatures..."
codesign --verify --deep --strict --verbose=2 "${APP}"

echo "==> App signature:"
codesign -dvvv "${APP}" 2>&1 | grep -E 'Identifier|TeamIdentifier|flags|Authority' || true

echo "==> App entitlements:"
codesign -d --entitlements :- "${APP}" 2>/dev/null | plutil -p - || true

echo "==> Packaging DMG..."
STAGING="${OUTPUT_DIR}/dmg-staging"
ditto "${APP}" "${STAGING}/Rasc.app"
ln -s /Applications "${STAGING}/Applications"
DMG="${OUTPUT_DIR}/Rasc-${VERSION}.dmg"
hdiutil create -volname Rasc -srcfolder "${STAGING}" -format UDZO -ov "${DMG}" >/dev/null

echo
echo "Built: ${APP}"
echo "DMG:   ${DMG}"
echo
echo "This ad-hoc build is expected to launch without loading Sparkle:"
echo "Library Validation rejects the framework; the weak link lets the app run,"
echo "but updates remain unavailable."
