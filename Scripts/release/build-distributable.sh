#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"

source "${ROOT}/common.sh"

"${ROOT}/archive.sh"
"${ROOT}/export-app.sh"
"${ROOT}/package-dmg.sh"

echo "Distributable DMG ready at ${DMG_PATH}"
