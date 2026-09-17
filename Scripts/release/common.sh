#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PROJECT_PATH="${ROOT_DIR}/Rasc.xcodeproj"
SCHEME="Rasc"
CONFIGURATION="Release"
BUILD_DIR="${ROOT_DIR}/build"
ARCHIVE_PATH="${BUILD_DIR}/Rasc.xcarchive"
EXPORT_DIR="${BUILD_DIR}/export"
APP_PATH="${EXPORT_DIR}/Rasc.app"
DMG_PATH="${BUILD_DIR}/Rasc.dmg"
STAGING_DIR="${BUILD_DIR}/dmg-staging"

BUNDLE_ID="com.rafaeltorres.rasc"
ENTITLEMENTS_PATH="${ROOT_DIR}/Rasc/Rasc.entitlements"

BETA_DIR="${BUILD_DIR}/private-beta"
BETA_DERIVED_DATA="${BETA_DIR}/DerivedData"
BETA_EXPORT_DIR="${BETA_DIR}/export"
BETA_APP_PATH="${BETA_EXPORT_DIR}/Rasc.app"
BETA_STAGING_DIR="${BETA_DIR}/dmg-staging"
BETA_PRODUCTS_DIR="${BETA_DERIVED_DATA}/Build/Products/${CONFIGURATION}"

require_command() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "error: required command not found: $1" >&2
    exit 1
  fi
}

require_development_team() {
  if [[ -z "${RASC_DEVELOPMENT_TEAM:-}" ]]; then
    cat >&2 <<'EOF'
error: RASC_DEVELOPMENT_TEAM is not set.

Export your 10-character Apple Developer Team ID before archiving or exporting:

  export RASC_DEVELOPMENT_TEAM="YOURTEAMID"

EOF
    exit 1
  fi
}

marketing_version() {
  /usr/libexec/PlistBuddy -c 'Print :ApplicationProperties:CFBundleShortVersionString' \
    "${ARCHIVE_PATH}/Info.plist"
}

build_number() {
  /usr/libexec/PlistBuddy -c 'Print :ApplicationProperties:CFBundleVersion' \
    "${ARCHIVE_PATH}/Info.plist"
}

marketing_version_from_project() {
  xcodebuild -showBuildSettings \
    -project "${PROJECT_PATH}" \
    -scheme "${SCHEME}" \
    -configuration "${CONFIGURATION}" \
    2>/dev/null | awk -F' = ' '/^[[:space:]]*MARKETING_VERSION[[:space:]]*=/ {print $2; exit}'
}

build_number_from_project() {
  xcodebuild -showBuildSettings \
    -project "${PROJECT_PATH}" \
    -scheme "${SCHEME}" \
    -configuration "${CONFIGURATION}" \
    2>/dev/null | awk -F' = ' '/^[[:space:]]*CURRENT_PROJECT_VERSION[[:space:]]*=/ {print $2; exit}'
}

marketing_version_from_app() {
  local app_path="$1"
  /usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' \
    "${app_path}/Contents/Info.plist"
}

build_number_from_app() {
  local app_path="$1"
  /usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' \
    "${app_path}/Contents/Info.plist"
}

beta_dmg_path() {
  local version="$1"
  echo "${BETA_DIR}/Rasc-${version}-beta.dmg"
}

beta_checksum_path() {
  local dmg_path="$1"
  echo "${dmg_path}.sha256"
}

package_dmg() {
  local app_path="$1"
  local dmg_path="$2"
  local staging_dir="$3"

  require_command hdiutil
  require_command ditto

  rm -rf "${staging_dir}" "${dmg_path}"
  mkdir -p "${staging_dir}"

  ditto "${app_path}" "${staging_dir}/Rasc.app"
  ln -s /Applications "${staging_dir}/Applications"

  echo "Creating DMG at ${dmg_path}..."
  hdiutil create \
    -volname "Rasc" \
    -srcfolder "${staging_dir}" \
    -ov \
    -format UDZO \
    "${dmg_path}"

  echo "DMG created at ${dmg_path}"
}

write_sha256_checksum() {
  local artifact_path="$1"
  local checksum_path="$2"

  require_command shasum

  (
    cd "$(dirname "${artifact_path}")"
    shasum -a 256 "$(basename "${artifact_path}")" > "$(basename "${checksum_path}")"
  )

  echo "SHA-256 checksum written to ${checksum_path}"
}
