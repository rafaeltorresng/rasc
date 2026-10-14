#!/usr/bin/env bash
set -euo pipefail

source "$(dirname "$0")/common.sh"

# RC artifacts live under build/rc/ (M13B); reuse private-beta build flow.
BETA_DIR="${BUILD_DIR}/rc"
BETA_DERIVED_DATA="${BETA_DIR}/DerivedData"
BETA_EXPORT_DIR="${BETA_DIR}/export"
BETA_APP_PATH="${BETA_EXPORT_DIR}/Rasc.app"
BETA_STAGING_DIR="${BETA_DIR}/dmg-staging"
BETA_PRODUCTS_DIR="${BETA_DERIVED_DATA}/Build/Products/${CONFIGURATION}"

require_command xcodebuild
require_command codesign
require_command ditto
require_command /usr/libexec/PlistBuddy

MARKETING_VERSION="$(marketing_version_from_project)"
BUILD_NUMBER="$(build_number_from_project)"
BETA_DMG_PATH="$(beta_dmg_path "${MARKETING_VERSION}")"
BETA_CHECKSUM_PATH="$(beta_checksum_path "${BETA_DMG_PATH}")"

echo "Building Rasc RC (version ${MARKETING_VERSION}, build ${BUILD_NUMBER})..."

if [[ -e "${BETA_DIR}" ]]; then
  echo "error: refusing to erase ${BETA_DIR}. Retain the previous RC in a versioned directory before building again." >&2
  exit 1
fi
mkdir -p "${BETA_EXPORT_DIR}"

echo "==> Clean Release build (ad-hoc signing)..."
xcodebuild \
  -project "${PROJECT_PATH}" \
  -scheme "${SCHEME}" \
  -configuration "${CONFIGURATION}" \
  -derivedDataPath "${BETA_DERIVED_DATA}" \
  clean build \
  CODE_SIGN_STYLE=Manual \
  CODE_SIGN_IDENTITY=- \
  DEVELOPMENT_TEAM=

BUILT_APP="${BETA_PRODUCTS_DIR}/Rasc.app"
if [[ ! -d "${BUILT_APP}" ]]; then
  echo "error: built app not found at ${BUILT_APP}" >&2
  exit 1
fi

echo "==> Copying app to ${BETA_EXPORT_DIR}..."
ditto "${BUILT_APP}" "${BETA_APP_PATH}"

echo "==> Ad-hoc signing with sandbox entitlements..."
codesign --force --deep --sign - \
  --options runtime \
  --entitlements "${ENTITLEMENTS_PATH}" \
  "${BETA_APP_PATH}"

echo "==> Packaging DMG..."
package_dmg "${BETA_APP_PATH}" "${BETA_DMG_PATH}" "${BETA_STAGING_DIR}"

echo "==> Writing SHA-256 checksum..."
write_sha256_checksum "${BETA_DMG_PATH}" "${BETA_CHECKSUM_PATH}"

cat <<EOF

RC artifacts ready:

  App:       ${BETA_APP_PATH}
  DMG:       ${BETA_DMG_PATH}
  Checksum:  ${BETA_CHECKSUM_PATH}

Version: ${MARKETING_VERSION}
Build:   ${BUILD_NUMBER}

Verify with:

  ./Scripts/release/verify-private-beta.sh ${BETA_DMG_PATH}
  ./Scripts/release/verify-rc-bundle.sh ${BETA_APP_PATH}

EOF
