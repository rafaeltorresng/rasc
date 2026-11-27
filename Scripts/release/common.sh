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
VOICE_DOWNLOADER_ENTITLEMENTS="${ROOT_DIR}/VoiceModelDownloader/VoiceModelDownloader.entitlements"
VOICE_DOWNLOADER_XPC_REL="Contents/XPCServices/com.rafaeltorres.rasc.VoiceModelDownloader.xpc"
SHARED_SOURCE_PACKAGES_DIR="${ROOT_DIR}/.derivedData/Rasc/SourcePackages"

SHARED_SOURCE_PACKAGES_ARGS=()
if [[ -d "${SHARED_SOURCE_PACKAGES_DIR}" ]]; then
  SHARED_SOURCE_PACKAGES_ARGS=(
    -clonedSourcePackagesDirPath "${SHARED_SOURCE_PACKAGES_DIR}"
    -disableAutomaticPackageResolution
  )
fi

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
  echo "${BETA_DIR}/Rasc-${version}.dmg"
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

  if [[ -e "${dmg_path}" ]]; then
    echo "error: refusing to overwrite retained artifact ${dmg_path}. Move it to a versioned archive first." >&2
    exit 1
  fi
  rm -rf "${staging_dir}"
  mkdir -p "${staging_dir}"

  ditto "${app_path}" "${staging_dir}/Rasc.app"
  ln -s /Applications "${staging_dir}/Applications"

  echo "Creating DMG at ${dmg_path}..."
  hdiutil create \
    -volname "Rasc" \
    -srcfolder "${staging_dir}" \
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

codesign_with_identity() {
  local identity="$1"
  shift
  if [[ "${identity}" == "-" ]]; then
    codesign --force --sign - --options runtime "$@"
  else
    codesign --force --sign "${identity}" --options runtime --timestamp "$@"
  fi
}

verify_voice_downloader_entitlements() {
  local xpc_path="$1"
  local ent_out
  ent_out="$(codesign -d --entitlements :- "${xpc_path}" 2>/dev/null)"
  if ! grep -q 'com.apple.security.network.client' <<< "${ent_out}"; then
    echo "error: VoiceModelDownloader.xpc must carry com.apple.security.network.client" >&2
    exit 1
  fi
  if grep -q 'com.apple.security.device.audio-input' <<< "${ent_out}"; then
    echo "error: VoiceModelDownloader.xpc must not carry com.apple.security.device.audio-input" >&2
    exit 1
  fi
  if grep -q 'com.apple.security.files.user-selected.read-write' <<< "${ent_out}"; then
    echo "error: VoiceModelDownloader.xpc must not carry com.apple.security.files.user-selected.read-write" >&2
    exit 1
  fi
}

sign_voice_downloader_xpc() {
  local app_path="$1"
  local identity="${2:--}"
  local xpc_path="${app_path}/${VOICE_DOWNLOADER_XPC_REL}"
  if [[ ! -d "${xpc_path}" ]]; then
    return 0
  fi
  if [[ ! -f "${VOICE_DOWNLOADER_ENTITLEMENTS}" ]]; then
    echo "error: VoiceModelDownloader entitlements not found at ${VOICE_DOWNLOADER_ENTITLEMENTS}" >&2
    exit 1
  fi
  echo "==> Signing VoiceModelDownloader.xpc inside-out..."
  codesign_with_identity "${identity}" \
    --entitlements "${VOICE_DOWNLOADER_ENTITLEMENTS}" \
    "${xpc_path}"
  verify_voice_downloader_entitlements "${xpc_path}"
}

sign_loose_framework_dylibs() {
  local app_path="$1"
  local identity="${2:--}"
  local frameworks_dir="${app_path}/Contents/Frameworks"
  if [[ ! -d "${frameworks_dir}" ]]; then
    return 0
  fi
  while IFS= read -r -d '' dylib; do
    echo "==> Signing embedded dylib $(basename "${dylib}")..."
    codesign_with_identity "${identity}" \
      --preserve-metadata=identifier \
      "${dylib}"
  done < <(find "${frameworks_dir}" -maxdepth 1 -type f -name '*.dylib' -print0)
}

sign_app_inside_out() {
  local app_path="$1"
  local app_entitlements="$2"
  local identity="${3:--}"
  local llc_plist="${4:-}"

  sign_voice_downloader_xpc "${app_path}" "${identity}"
  sign_loose_framework_dylibs "${app_path}" "${identity}"

  local sign_args=(--entitlements "${app_entitlements}")
  if [[ -n "${llc_plist}" ]]; then
    sign_args+=(--library-constraint "${llc_plist}")
  fi
  codesign_with_identity "${identity}" "${sign_args[@]}" "${app_path}"
  codesign --verify --deep --strict --verbose=2 "${app_path}"

  local xpc_path="${app_path}/${VOICE_DOWNLOADER_XPC_REL}"
  if [[ -d "${xpc_path}" ]]; then
    verify_voice_downloader_entitlements "${xpc_path}"
  fi
}
