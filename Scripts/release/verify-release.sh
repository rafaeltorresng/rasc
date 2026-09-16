#!/usr/bin/env bash
set -euo pipefail

source "$(dirname "$0")/common.sh"

require_command codesign
require_command spctl
require_command xcrun
require_command hdiutil
require_command ditto

ARTIFACT_PATH="${1:-${DMG_PATH}}"
TEMP_DIR=""

cleanup() {
  if [[ -n "${TEMP_DIR}" && -d "${TEMP_DIR}" ]]; then
    rm -rf "${TEMP_DIR}"
  fi
}
trap cleanup EXIT

if [[ ! -e "${ARTIFACT_PATH}" ]]; then
  echo "usage: $0 [path-to-dmg-or-app]" >&2
  echo "error: artifact not found at ${ARTIFACT_PATH}" >&2
  exit 1
fi

verify_app() {
  local app_path="$1"
  echo "==> codesign verify (deep, strict): ${app_path}"
  codesign --verify --deep --strict --verbose=2 "${app_path}"

  echo "==> codesign display"
  codesign --display --verbose=4 "${app_path}"

  echo "==> entitlements"
  codesign --display --entitlements :- "${app_path}" | plutil -p -

  if codesign --display --entitlements :- "${app_path}" 2>/dev/null | grep -q 'get-task-allow'; then
    echo "error: debug entitlement get-task-allow is present" >&2
    exit 1
  fi

  echo "==> Gatekeeper assessment"
  spctl --assess --type execute --verbose=4 "${app_path}"
}

if [[ "${ARTIFACT_PATH}" == *.dmg ]]; then
  TEMP_DIR="$(mktemp -d)"
  MOUNT_POINT="${TEMP_DIR}/mount"
  mkdir -p "${MOUNT_POINT}"
  hdiutil attach -nobrowse -readonly -mountpoint "${MOUNT_POINT}" "${ARTIFACT_PATH}" >/dev/null
  verify_app "${MOUNT_POINT}/Rasc.app"
  hdiutil detach "${MOUNT_POINT}" >/dev/null

  echo "==> stapler validate (DMG)"
  xcrun stapler validate "${ARTIFACT_PATH}"
elif [[ "${ARTIFACT_PATH}" == *.app ]]; then
  verify_app "${ARTIFACT_PATH}"

  if xcrun stapler validate "${ARTIFACT_PATH}" >/dev/null 2>&1; then
    echo "==> stapler validate (app)"
    xcrun stapler validate "${ARTIFACT_PATH}"
  else
    echo "note: app ticket not stapled locally; validate the distributed DMG/ZIP instead."
  fi
else
  echo "error: unsupported artifact type: ${ARTIFACT_PATH}" >&2
  exit 1
fi

echo "Verification passed for ${ARTIFACT_PATH}"
