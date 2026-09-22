#!/usr/bin/env bash
set -euo pipefail

source "$(dirname "$0")/common.sh"

DMG_PATH="${1:-}"
if [[ -z "${DMG_PATH}" || ! -f "${DMG_PATH}" ]]; then
  echo "usage: $0 path-to-rc.dmg" >&2
  exit 1
fi

require_command hdiutil
require_command ditto

TEMP_DIR="$(mktemp -d)"
MOUNT_POINT="${TEMP_DIR}/mount"
INSTALL_DIR="${TEMP_DIR}/install"
cleanup() {
  hdiutil detach "${MOUNT_POINT}" >/dev/null 2>&1 || true
  rm -rf "${TEMP_DIR}"
}
trap cleanup EXIT

mkdir -p "${MOUNT_POINT}" "${INSTALL_DIR}"
hdiutil attach -nobrowse -readonly -mountpoint "${MOUNT_POINT}" "${DMG_PATH}" >/dev/null

SOURCE_APP="${MOUNT_POINT}/Rasc.app"
if [[ ! -d "${SOURCE_APP}" ]]; then
  echo "error: Rasc.app missing from DMG" >&2
  exit 1
fi

if [[ ! -L "${MOUNT_POINT}/Applications" ]]; then
  echo "error: Applications alias missing from DMG" >&2
  exit 1
fi

TARGET_APP="${INSTALL_DIR}/Rasc.app"
ditto "${SOURCE_APP}" "${TARGET_APP}"

MARKETING_VERSION="$(marketing_version_from_app "${TARGET_APP}")"
BUILD_NUMBER="$(build_number_from_app "${TARGET_APP}")"
echo "Installed copy: ${MARKETING_VERSION} (${BUILD_NUMBER}) at ${TARGET_APP}"

echo "==> Launch smoke test"
open -n "${TARGET_APP}"
sleep 4

if ! pgrep -f "${TARGET_APP}/Contents/MacOS/Rasc" >/dev/null; then
  echo "error: packaged app did not stay running after launch" >&2
  exit 1
fi

echo "Launch smoke test passed"
pkill -f "${TARGET_APP}/Contents/MacOS/Rasc" >/dev/null 2>&1 || true
sleep 1

echo "Installation smoke test passed for ${DMG_PATH}"
