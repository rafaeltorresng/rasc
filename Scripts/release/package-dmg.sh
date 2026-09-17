#!/usr/bin/env bash
set -euo pipefail

source "$(dirname "$0")/common.sh"

if [[ ! -d "${APP_PATH}" ]]; then
  echo "error: exported app not found at ${APP_PATH}. Run export-app.sh first." >&2
  exit 1
fi

package_dmg "${APP_PATH}" "${DMG_PATH}" "${STAGING_DIR}"
