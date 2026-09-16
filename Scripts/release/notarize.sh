#!/usr/bin/env bash
set -euo pipefail

source "$(dirname "$0")/common.sh"

require_command xcrun

ARTIFACT_PATH="${1:-${DMG_PATH}}"
NOTARY_PROFILE="${RASC_NOTARY_KEYCHAIN_PROFILE:-RASC_NOTARY}"

if [[ ! -e "${ARTIFACT_PATH}" ]]; then
  echo "usage: $0 [path-to-dmg-or-zip]" >&2
  echo "error: artifact not found at ${ARTIFACT_PATH}" >&2
  exit 1
fi

echo "Submitting ${ARTIFACT_PATH} for notarization..."
if ! xcrun notarytool submit "${ARTIFACT_PATH}" \
  --keychain-profile "${NOTARY_PROFILE}" \
  --wait; then
  cat >&2 <<EOF
error: notarization failed.

Inspect recent submissions:

  xcrun notarytool history --keychain-profile ${NOTARY_PROFILE}

Fetch a submission log:

  xcrun notarytool log <submission-id> --keychain-profile ${NOTARY_PROFILE}
EOF
  exit 1
fi

echo "Stapling notarization ticket to ${ARTIFACT_PATH}..."
xcrun stapler staple "${ARTIFACT_PATH}"
xcrun stapler validate "${ARTIFACT_PATH}"

echo "Notarization complete for ${ARTIFACT_PATH}"
