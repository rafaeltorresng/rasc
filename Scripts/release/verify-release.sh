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
MOUNTED=false

cleanup() {
  if [[ "${MOUNTED}" == true ]]; then
    if hdiutil detach "${MOUNT_POINT}" >/dev/null; then
      MOUNTED=false
    else
      echo "warning: could not unmount ${MOUNT_POINT}; temporary directory retained" >&2
      return
    fi
  fi
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

  local signature
  signature="$(codesign --display --verbose=4 "${app_path}" 2>&1)"
  if ! grep -q '^Authority=Developer ID Application:' <<<"${signature}" \
    || ! grep -Eq '^TeamIdentifier=[A-Z0-9]{10}$' <<<"${signature}" \
    || ! grep -Eq '^.*flags=.*runtime' <<<"${signature}"; then
    echo "error: a Developer ID signature, Team ID and hardened runtime are required" >&2
    exit 1
  fi

  echo "==> entitlements"
  codesign --display --entitlements :- "${app_path}" | plutil -p -

  if codesign --display --entitlements :- "${app_path}" 2>/dev/null | grep -q 'get-task-allow'; then
    echo "error: debug entitlement get-task-allow is present" >&2
    exit 1
  fi

  local entitlements
  entitlements="$(codesign --display --entitlements :- "${app_path}" 2>/dev/null)"
  if [[ "$(plutil -extract 'com\.apple\.security\.app-sandbox' raw -o - - <<<"${entitlements}")" != true ]]; then
    echo "error: App Sandbox must be enabled" >&2
    exit 1
  fi
  if grep -q 'com.apple.security.network' <<<"${entitlements}"; then
    echo "error: network entitlements are outside the v0.1 privacy contract" >&2
    exit 1
  fi

  local info="${app_path}/Contents/Info.plist"
  if [[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "${info}")" != "${BUNDLE_ID}" ]] \
    || [[ "$(marketing_version_from_app "${app_path}")" != "$(marketing_version_from_project)" ]] \
    || [[ "$(build_number_from_app "${app_path}")" != "$(build_number_from_project)" ]]; then
    echo "error: bundle identifier, version or build differs from the source candidate" >&2
    exit 1
  fi
  if find "${app_path}" \( -name '*.xctest' -o -name '*.sqlite' -o -name '*.sqlite-wal' -o -name 'RefinementEvals.v1.json' -o -name '*.debug.dylib' \) -print -quit | grep -q .; then
    echo "error: development data or test/debug artifacts found in app bundle" >&2
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
  MOUNTED=true
  verify_app "${MOUNT_POINT}/Rasc.app"
  hdiutil detach "${MOUNT_POINT}" >/dev/null
  MOUNTED=false

  echo "==> stapler validate (DMG)"
  xcrun stapler validate "${ARTIFACT_PATH}"
elif [[ "${ARTIFACT_PATH}" == *.app ]]; then
  verify_app "${ARTIFACT_PATH}"

  echo "==> stapler validate (app)"
  xcrun stapler validate "${ARTIFACT_PATH}"
else
  echo "error: unsupported artifact type: ${ARTIFACT_PATH}" >&2
  exit 1
fi

echo "Verification passed for ${ARTIFACT_PATH}"
