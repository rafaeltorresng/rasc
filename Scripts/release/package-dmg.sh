#!/usr/bin/env bash
set -euo pipefail

source "$(dirname "$0")/common.sh"

require_command hdiutil
require_command ditto

if [[ ! -d "${APP_PATH}" ]]; then
  echo "error: exported app not found at ${APP_PATH}. Run export-app.sh first." >&2
  exit 1
fi

rm -rf "${STAGING_DIR}" "${DMG_PATH}"
mkdir -p "${STAGING_DIR}"

ditto "${APP_PATH}" "${STAGING_DIR}/Rasc.app"
ln -s /Applications "${STAGING_DIR}/Applications"

echo "Creating DMG at ${DMG_PATH}..."
hdiutil create \
  -volname "Rasc" \
  -srcfolder "${STAGING_DIR}" \
  -ov \
  -format UDZO \
  "${DMG_PATH}"

echo "DMG created at ${DMG_PATH}"
