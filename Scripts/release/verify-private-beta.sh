#!/usr/bin/env bash
set -euo pipefail

source "$(dirname "$0")/common.sh"

require_command codesign
require_command hdiutil
require_command ditto
require_command /usr/libexec/PlistBuddy
require_command shasum

ARTIFACT_PATH="${1:-}"
TEMP_DIR=""
MOUNT_POINT=""

cleanup() {
  if [[ -n "${MOUNT_POINT}" && -d "${MOUNT_POINT}" ]]; then
    hdiutil detach "${MOUNT_POINT}" >/dev/null 2>&1 || true
  fi
  if [[ -n "${TEMP_DIR}" && -d "${TEMP_DIR}" ]]; then
    rm -rf "${TEMP_DIR}"
  fi
}
trap cleanup EXIT

if [[ -z "${ARTIFACT_PATH}" ]]; then
  echo "usage: $0 path-to-private-beta-dmg" >&2
  exit 1
fi

if [[ ! -f "${ARTIFACT_PATH}" ]]; then
  echo "error: artifact not found at ${ARTIFACT_PATH}" >&2
  exit 1
fi

if [[ "${ARTIFACT_PATH}" != *.dmg ]]; then
  echo "error: expected a .dmg artifact" >&2
  exit 1
fi

CHECKSUM_PATH="$(beta_checksum_path "${ARTIFACT_PATH}")"

echo "==> SHA-256 checksum"
if [[ ! -f "${CHECKSUM_PATH}" ]]; then
  echo "error: checksum file not found at ${CHECKSUM_PATH}" >&2
  exit 1
fi

(
  cd "$(dirname "${ARTIFACT_PATH}")"
  shasum -a 256 -c "$(basename "${CHECKSUM_PATH}")"
)

echo "==> Mount DMG"
TEMP_DIR="$(mktemp -d)"
MOUNT_POINT="${TEMP_DIR}/mount"
mkdir -p "${MOUNT_POINT}"
hdiutil attach -nobrowse -readonly -mountpoint "${MOUNT_POINT}" "${ARTIFACT_PATH}" >/dev/null

APP_PATH="${MOUNT_POINT}/Rasc.app"
if [[ ! -d "${APP_PATH}" ]]; then
  echo "error: Rasc.app not found inside DMG" >&2
  exit 1
fi

if [[ ! -L "${MOUNT_POINT}/Applications" ]]; then
  echo "error: Applications alias not found inside DMG" >&2
  exit 1
fi

echo "==> Bundle identifier"
BUNDLE_IDENTIFIER="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "${APP_PATH}/Contents/Info.plist")"
if [[ "${BUNDLE_IDENTIFIER}" != "${BUNDLE_ID}" ]]; then
  echo "error: expected bundle identifier ${BUNDLE_ID}, found ${BUNDLE_IDENTIFIER}" >&2
  exit 1
fi
echo "Bundle identifier: ${BUNDLE_IDENTIFIER}"

echo "==> Version and build"
MARKETING_VERSION="$(marketing_version_from_app "${APP_PATH}")"
BUILD_NUMBER="$(build_number_from_app "${APP_PATH}")"
EXPECTED_MARKETING_VERSION="$(marketing_version_from_project)"
EXPECTED_BUILD_NUMBER="$(build_number_from_project)"
echo "Marketing version: ${MARKETING_VERSION}"
echo "Build number: ${BUILD_NUMBER}"

if [[ "${MARKETING_VERSION}" != "${EXPECTED_MARKETING_VERSION}" ]]; then
  echo "error: expected marketing version ${EXPECTED_MARKETING_VERSION}, found ${MARKETING_VERSION}" >&2
  exit 1
fi

if [[ "${BUILD_NUMBER}" != "${EXPECTED_BUILD_NUMBER}" ]]; then
  echo "error: expected build ${EXPECTED_BUILD_NUMBER}, found ${BUILD_NUMBER}" >&2
  exit 1
fi

echo "==> LSUIElement"
LS_UI_ELEMENT="$(/usr/libexec/PlistBuddy -c 'Print :LSUIElement' "${APP_PATH}/Contents/Info.plist")"
if [[ "${LS_UI_ELEMENT}" != "true" ]]; then
  echo "error: expected LSUIElement=true, found ${LS_UI_ELEMENT}" >&2
  exit 1
fi

echo "==> codesign verify (deep, strict)"
codesign --verify --deep --strict --verbose=2 "${APP_PATH}"

echo "==> codesign display"
codesign --display --verbose=4 "${APP_PATH}"

SIGNATURE_INFO="$(codesign -dvvv "${APP_PATH}" 2>&1)"
echo "${SIGNATURE_INFO}"

echo "==> Hardened Runtime"
if ! echo "${SIGNATURE_INFO}" | grep -q 'Runtime Version'; then
  echo "error: Hardened Runtime not detected" >&2
  exit 1
fi
echo "Hardened Runtime confirmed"

echo "==> ad-hoc signature status"
if echo "${SIGNATURE_INFO}" | grep -q 'Developer ID Application'; then
  echo "error: expected ad-hoc signature, found Developer ID Application" >&2
  exit 1
fi
if ! echo "${SIGNATURE_INFO}" | grep -Eq 'Signature=adhoc|Signature=Adhoc'; then
  echo "error: expected ad-hoc signature" >&2
  exit 1
fi
echo "Ad-hoc signature confirmed"

echo "==> entitlements"
ENTITLEMENTS_PLIST="$(codesign --display --entitlements :- "${APP_PATH}" 2>/dev/null)"
echo "${ENTITLEMENTS_PLIST}" | plutil -p -

if ! echo "${ENTITLEMENTS_PLIST}" | plutil -p - | grep -Eq '"com.apple.security.app-sandbox" => (1|true)'; then
  echo "error: App Sandbox entitlement is missing or disabled" >&2
  exit 1
fi

if echo "${ENTITLEMENTS_PLIST}" | grep -q 'get-task-allow'; then
  echo "error: debug entitlement get-task-allow is present" >&2
  exit 1
fi

echo "==> third-party notices"
THIRD_PARTY_NOTICES="${APP_PATH}/Contents/Resources/ThirdPartyNotices.txt"
if [[ ! -f "${THIRD_PARTY_NOTICES}" ]]; then
  echo "error: ThirdPartyNotices.txt not found in app bundle" >&2
  exit 1
fi
for dependency in ThinkingOrbsKit GRDB KeyboardShortcuts; do
  if ! grep -q "${dependency}" "${THIRD_PARTY_NOTICES}"; then
    echo "error: ThirdPartyNotices.txt is missing ${dependency} attribution" >&2
    exit 1
  fi
done
echo "Third-party notices present"

echo "==> bundle audit"
if find "${APP_PATH}" -name '*.xctest' -print -quit | grep -q .; then
  echo "error: test bundle found inside app" >&2
  exit 1
fi

if find "${APP_PATH}" \( -name '*.sqlite' -o -name '*.db' \) -print -quit | grep -q .; then
  echo "error: SQLite database found inside app bundle" >&2
  exit 1
fi

if find "${APP_PATH}" -iname '*RefinementEvals*' -print -quit | grep -q .; then
  echo "error: test fixture found inside app bundle" >&2
  exit 1
fi

SENSITIVE_PATTERNS=(
  'BEGIN PRIVATE KEY'
  'BEGIN RSA PRIVATE KEY'
  'api[_-]?key'
  'secret'
  'password'
  'notarytool'
  'AC_PASSWORD'
)

while IFS= read -r -d '' file; do
  case "$(basename "${file}")" in
    *.car|*.nib|*.png|*.icns|*.ttf|*.otf|*.woff|*.woff2|*.dylib|*.bundle|Rasc)
      continue
      ;;
  esac

  if grep -Eiq "$(IFS='|'; echo "${SENSITIVE_PATTERNS[*]}")" "${file}" 2>/dev/null; then
    echo "error: possible credential or secret pattern in ${file}" >&2
    exit 1
  fi
done < <(find "${APP_PATH}" -type f -print0)

ABSOLUTE_PATH_HITS=()
while IFS= read -r -d '' file; do
  case "$(basename "${file}")" in
    ThirdPartyNotices.txt|*.car|*.nib|*.png|*.icns|*.ttf|*.otf|*.woff|*.woff2|*.dylib|*.bundle|Rasc)
      continue
      ;;
  esac

  if grep -E '/Users/[^/]+/' "${file}" >/dev/null 2>&1; then
    ABSOLUTE_PATH_HITS+=("${file}")
  fi
done < <(find "${APP_PATH}" -type f -print0)

if ((${#ABSOLUTE_PATH_HITS[@]} > 0)); then
  echo "error: absolute developer-machine paths found in bundle:" >&2
  printf '  %s\n' "${ABSOLUTE_PATH_HITS[@]}" >&2
  exit 1
fi

echo "Bundle audit passed"

echo "note: Gatekeeper acceptance is not required for private beta (ad-hoc, not notarized)."

echo "Private beta verification passed for ${ARTIFACT_PATH}"
