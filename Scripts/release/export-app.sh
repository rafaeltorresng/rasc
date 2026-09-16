#!/usr/bin/env bash
set -euo pipefail

source "$(dirname "$0")/common.sh"

require_command xcodebuild
require_command /usr/libexec/PlistBuddy
require_development_team

if [[ ! -d "${ARCHIVE_PATH}" ]]; then
  echo "error: archive not found at ${ARCHIVE_PATH}. Run archive.sh first." >&2
  exit 1
fi

EXPORT_OPTIONS_PLIST="${BUILD_DIR}/ExportOptions.plist"
rm -rf "${EXPORT_DIR}"
mkdir -p "${BUILD_DIR}"

/usr/libexec/PlistBuddy -c 'Clear dict' "${EXPORT_OPTIONS_PLIST}"
/usr/libexec/PlistBuddy -c 'Add :method string developer-id' "${EXPORT_OPTIONS_PLIST}"
/usr/libexec/PlistBuddy -c 'Add :signingStyle string manual' "${EXPORT_OPTIONS_PLIST}"
/usr/libexec/PlistBuddy -c "Add :teamID string ${RASC_DEVELOPMENT_TEAM}" "${EXPORT_OPTIONS_PLIST}"

echo "Exporting signed app from archive..."
xcodebuild \
  -exportArchive \
  -archivePath "${ARCHIVE_PATH}" \
  -exportPath "${EXPORT_DIR}" \
  -exportOptionsPlist "${EXPORT_OPTIONS_PLIST}"

echo "Exported app at ${APP_PATH}"
