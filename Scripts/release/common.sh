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
