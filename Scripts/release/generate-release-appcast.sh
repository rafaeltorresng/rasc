#!/usr/bin/env bash
# Generate a Sparkle appcast fragment for a versioned GitHub Release asset.
#
# Routine signing reads the private key directly from the login keychain via
# Sparkle's official tools (generate_appcast --account). No raw key file is
# required. For a headless/CI fallback, pass --ed-key-file explicitly.
# Preserve the complete updater history and the six known prior public builds
# in each release's delta set; Sparkle's defaults silently drop supported paths.
#
# Debian-style archives layout (build/updater-rc/feed) accumulates DMGs and one
# appcast.xml across releases. Re-running for a new version appends a new entry;
# entries for previous releases keep their original GitHub download URLs and
# signatures. The wrapper restores old enclosure URLs after Sparkle regenerates
# the feed, since Sparkle applies the current prefix to every archive.
#
# Usage:
#   Scripts/release/generate-release-appcast.sh \
#     --version 0.1.6 \
#     --prefix https://github.com/rafaeltorresng/rasc/releases/download/v0.1.6/ \
#     --dmg build/updater-rc/0.1.6/Rasc-0.1.6-updater.dmg \
#     --account rasc-sparkle
#
# Options:
#   --version          release marketing version (required)
#   --prefix           base URL for the enclosure; for versioned GitHub Release
#                      assets this is https://github.com/<org>/<repo>/releases/download/v<version>/  (required)
#   --dmg              path to the signed DMG                                           (repeatable)
#   --account          named login-keychain account used with Sparkle's signing tools (default: rasc-sparkle)
#   --ed-key-file      raw base64 Ed25519 private key file (escape hatch; NOT used in routine signing)
#   --public-key-pem   PEM public key used by the verifier (default: derived via `generate_keys -p --account`)
#   --feed-dir         working directory for DMGs + appcast.xml                (default: build/updater-rc/feed)
#   --tamper-evidence  directory for tamper-verification output                 (default: <feed-dir>/../evidence)
#   --dry-run          print what would be run, perform no changes
#
# The script never touches git, GitHub, rasc.app, or the public download link.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
GEN="${ROOT_DIR}/build/sparkle-tools/bin/generate_appcast"
FEED_DIR=""
TAMPER_OUT=""
VERSION=""
PREFIX=""
ACCOUNT="rasc-sparkle"
ED_KEY_FILE=""
PUBLIC_KEY_PEM=""
DRY_RUN=0
DMGS=()

usage() { sed -n '2,32p' "${BASH_SOURCE[0]}" >&2; exit "${1:-1}"; }

while [[ $# -gt 0 ]]; do
  case "$1" in
    --version) VERSION="${2:?missing value}"; shift 2 ;;
    --prefix) PREFIX="${2:?missing value}"; shift 2 ;;
    --dmg) DMGS+=("${2:?missing value}"); shift 2 ;;
    --account) ACCOUNT="${2:?missing value}"; shift 2 ;;
    --ed-key-file) ED_KEY_FILE="${2:?missing value}"; shift 2 ;;
    --public-key-pem) PUBLIC_KEY_PEM="${2:?missing value}"; shift 2 ;;
    --feed-dir) FEED_DIR="${2:?missing value}"; shift 2 ;;
    --tamper-evidence) TAMPER_OUT="${2:?missing value}"; shift 2 ;;
    --dry-run) DRY_RUN=1; shift ;;
    -h|--help) usage 0 ;;
    *) echo "error: unknown argument: $1" >&2; usage 2 ;;
  esac
done

if [[ -z "${VERSION}" || -z "${PREFIX}" || ${#DMGS[@]} -eq 0 ]]; then
  echo "error: --version, --prefix, and at least one --dmg are required" >&2
  usage 2
fi
if [[ "${PREFIX: -1}" != "/" ]]; then
  echo "error: --prefix must end with '/' (generate_appcast concatenates file names directly)" >&2
  exit 2
fi
if ! [[ "${VERSION}" =~ ^[0-9]+\.[0-9]+(\.[0-9]+)?(-[A-Za-z0-9.]+)?$ ]]; then
  echo "error: --version does not look like a marketing version: ${VERSION}" >&2
  exit 2
fi

FEED_DIR="${FEED_DIR:-${ROOT_DIR}/build/updater-rc/feed}"
TAMPER_OUT="${TAMPER_OUT:-${FEED_DIR}/../evidence}"
mkdir -p "${FEED_DIR}" "${TAMPER_OUT}"

for dmg in "${DMGS[@]}"; do
  [[ -f "${dmg}" ]] || { echo "error: DMG not found: ${dmg}" >&2; exit 1; }
done

if [[ ! -x "${GEN}" ]]; then
  echo "error: Sparkle command-line tools not found at ${GEN}" >&2
  echo "       download and verify Sparkle 2.9.4 (see docs/SPARKLE-RELEASE.md):" >&2
  echo "       mkdir -p build/sparkle-tools && \\" >&2
  echo "       curl -L -o build/Sparkle-2.9.4.tar.xz \\" >&2
  echo "         https://github.com/sparkle-project/Sparkle/releases/download/2.9.4/Sparkle-2.9.4.tar.xz" >&2
  exit 1
fi

for dmg in "${DMGS[@]}"; do
  dst="${FEED_DIR}/$(basename "${dmg}")"
  if [[ -f "${dst}" ]] && cmp -s "${dmg}" "${dst}"; then
    continue
  fi
  cp "${dmg}" "${dst}"
done

if [[ "${DRY_RUN}" == "1" ]]; then
  echo "would run:"
  if [[ -n "${ED_KEY_FILE}" ]]; then
    echo "  ${GEN} --ed-key-file ${ED_KEY_FILE} --download-url-prefix ${PREFIX} ${FEED_DIR}"
  else
    echo "  ${GEN} --account ${ACCOUNT} --download-url-prefix ${PREFIX} ${FEED_DIR}"
  fi
  exit 0
fi

URL_MAP_FILE="$(mktemp "${TMPDIR:-/tmp}/rasc-appcast-urls.XXXXXX")"
if [[ -f "${FEED_DIR}/appcast.xml" ]]; then
  python3 - "${FEED_DIR}/appcast.xml" "${URL_MAP_FILE}" <<'PY'
import json
import sys
import xml.etree.ElementTree as ET
from pathlib import Path
from urllib.parse import unquote, urlparse

feed_path, output_path = map(Path, sys.argv[1:])
root = ET.parse(feed_path).getroot()
urls = {}
for enclosure in root.iter("enclosure"):
    url = enclosure.get("url")
    if url:
        urls[unquote(urlparse(url).path.rsplit("/", 1)[-1])] = url
output_path.write_text(json.dumps(urls))
PY
else
  printf '{}' > "${URL_MAP_FILE}"
fi

echo "==> Generating appcast fragment in ${FEED_DIR}"
if [[ -n "${ED_KEY_FILE}" ]]; then
  echo "warning: using --ed-key-file (raw private key). Routine signing should use --account instead." >&2
  "${GEN}" --ed-key-file "${ED_KEY_FILE}" --download-url-prefix "${PREFIX}" \
    --maximum-versions 0 --maximum-deltas 6 "${FEED_DIR}"
else
  "${GEN}" --account "${ACCOUNT}" --download-url-prefix "${PREFIX}" \
    --maximum-versions 0 --maximum-deltas 6 "${FEED_DIR}"
fi

python3 - "${FEED_DIR}/appcast.xml" "${URL_MAP_FILE}" <<'PY'
import json
import re
import sys
from pathlib import Path
from urllib.parse import unquote, urlparse

feed_path, map_path = map(Path, sys.argv[1:])
old_urls = json.loads(map_path.read_text())
feed = feed_path.read_text()

def restore_url(match):
    tag = match.group(0)
    url_match = re.search(r'\burl="([^"]+)"', tag)
    if not url_match:
        return tag
    filename = unquote(urlparse(url_match.group(1)).path.rsplit("/", 1)[-1])
    old_url = old_urls.get(filename)
    if old_url:
        return tag[:url_match.start(1)] + old_url + tag[url_match.end(1):]
    return tag

feed_path.write_text(re.sub(r"<enclosure\b[^>]*>", restore_url, feed))
map_path.unlink(missing_ok=True)
PY

echo "==> Verifying appcast signatures..."
VERIFY_ARGS=( --feed "${FEED_DIR}" --account "${ACCOUNT}" --sparkle-tools-path "${ROOT_DIR}/build/sparkle-tools/bin" )
if [[ -n "${PUBLIC_KEY_PEM}" ]]; then
  VERIFY_ARGS=( --feed "${FEED_DIR}" --public-key "${PUBLIC_KEY_PEM}" )
fi
python3 "${ROOT_DIR}/Scripts/sparkle-proof/verify-appcast.py" "${VERIFY_ARGS[@]}" --tamper --tamper-output "${TAMPER_OUT}"

cat <<EOF

appcast generated at: ${FEED_DIR}/appcast.xml

Manual publishing steps (see docs/SPARKLE-RELEASE.md):
  1. Upload the updater DMG to the GitHub Release v${VERSION}. Do not publish otherwise.
  2. Upload appcast.xml fragment to the rasc.app web repository feed location.
     Base URL for this release: ${PREFIX}
  3. Prefer re-running this script with the same --feed-dir for the next release:
     existing entries keep their upload URLs and signatures.

This script never uploads anything on its own.
