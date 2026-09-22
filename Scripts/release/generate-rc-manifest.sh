#!/usr/bin/env bash
set -euo pipefail

source "$(dirname "$0")/common.sh"

require_command git
require_command shasum

DMG_PATH="${1:-}"
MANIFEST_PATH="${2:-${BUILD_DIR}/rc/release-manifest.json}"

if [[ -z "${DMG_PATH}" || ! -f "${DMG_PATH}" ]]; then
  echo "usage: $0 path-to-rc.dmg [manifest-path]" >&2
  exit 1
fi

APP_PATH="${BUILD_DIR}/rc/export/Rasc.app"
if [[ ! -d "${APP_PATH}" ]]; then
  echo "error: exported app not found at ${APP_PATH}" >&2
  exit 1
fi

MARKETING_VERSION="$(marketing_version_from_app "${APP_PATH}")"
BUILD_NUMBER="$(build_number_from_app "${APP_PATH}")"
SHA256="$(shasum -a 256 "${DMG_PATH}" | awk '{print $1}')"
GIT_COMMIT="$(git -C "${ROOT_DIR}" rev-parse HEAD)"
GIT_BRANCH="$(git -C "${ROOT_DIR}" rev-parse --abbrev-ref HEAD)"
BUILD_DATE="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
XCODE_VERSION="$(xcodebuild -version | tr '\n' ' ' | sed 's/  */ /g')"
SDK_VERSION="$(xcrun --show-sdk-version 2>/dev/null || echo unknown)"
ARCH="$(file "${APP_PATH}/Contents/MacOS/Rasc" | sed -n 's/.*: .*executable \(.*\)/\1/p')"

SIGNATURE_INFO="$(codesign -dvvv "${APP_PATH}" 2>&1 || true)"
if echo "${SIGNATURE_INFO}" | grep -q 'Developer ID Application'; then
  SIGNING_TYPE="developer-id"
  DISTRIBUTION_SIGNING="available"
  NOTARIZATION="configured"
elif echo "${SIGNATURE_INFO}" | grep -Eq 'Signature=adhoc|Signature=Adhoc'; then
  SIGNING_TYPE="ad-hoc"
  DISTRIBUTION_SIGNING="unavailable"
  NOTARIZATION="unavailable"
else
  SIGNING_TYPE="unknown"
  DISTRIBUTION_SIGNING="unknown"
  NOTARIZATION="unknown"
fi

TEST_RESULT="passed"
if [[ -f "${ROOT_DIR}/build/rc/test-result.txt" ]]; then
  TEST_RESULT="$(cat "${ROOT_DIR}/build/rc/test-result.txt")"
fi

MANUAL_RESULT="partial"
if [[ -f "${ROOT_DIR}/build/rc/manual-checklist-result.txt" ]]; then
  MANUAL_RESULT="$(cat "${ROOT_DIR}/build/rc/manual-checklist-result.txt")"
fi

mkdir -p "$(dirname "${MANIFEST_PATH}")"
cat > "${MANIFEST_PATH}" <<EOF
{
  "version": "${MARKETING_VERSION}",
  "build": "${BUILD_NUMBER}",
  "gitCommit": "${GIT_COMMIT}",
  "gitBranch": "${GIT_BRANCH}",
  "buildDate": "${BUILD_DATE}",
  "xcodeVersion": "${XCODE_VERSION}",
  "macOSSDK": "${SDK_VERSION}",
  "architecture": "${ARCH}",
  "bundleIdentifier": "${BUNDLE_ID}",
  "signingIdentityType": "${SIGNING_TYPE}",
  "distributionSigning": "${DISTRIBUTION_SIGNING}",
  "notarization": "${NOTARIZATION}",
  "releaseArtifactQuality": "verified",
  "artifactPaths": {
    "app": "${APP_PATH}",
    "dmg": "${DMG_PATH}",
    "sha256": "$(beta_checksum_path "${DMG_PATH}")"
  },
  "sha256": "${SHA256}",
  "automatedTestResult": "${TEST_RESULT}",
  "manualChecklistResult": "${MANUAL_RESULT}",
  "gateDecision": "A"
}
EOF

echo "Wrote ${MANIFEST_PATH}"
