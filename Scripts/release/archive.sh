#!/usr/bin/env bash
set -euo pipefail

source "$(dirname "$0")/common.sh"

require_command xcodebuild
require_development_team

rm -rf "${ARCHIVE_PATH}"
mkdir -p "${BUILD_DIR}"

echo "Archiving ${SCHEME} (${CONFIGURATION})..."
xcodebuild \
  -project "${PROJECT_PATH}" \
  -scheme "${SCHEME}" \
  -configuration "${CONFIGURATION}" \
  -archivePath "${ARCHIVE_PATH}" \
  archive \
  DEVELOPMENT_TEAM="${RASC_DEVELOPMENT_TEAM}" \
  CODE_SIGN_STYLE=Manual \
  "CODE_SIGN_IDENTITY=Developer ID Application"

echo "Archive created at ${ARCHIVE_PATH}"
