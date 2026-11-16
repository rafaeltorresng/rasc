#!/usr/bin/env bash
# Generate a Sparkle appcast fragment for a versioned GitHub Release asset.
#
# Routine signing reads the private key directly from the login keychain via
# Sparkle's official tools (generate_appcast --account). No raw key file is
# required. For a headless/CI fallback, pass --ed-key-file explicitly.
#
# Debian-style archives layout (build/updater-rc/feed) accumulates DMGs and one
# appcast.xml across releases. Re-running for a new version appends a new entry;
# entries for previous releases keep their original GitHub download URLs and
# signatures, because appcast entries record the full download URL at creation
# time.
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

echo "==> Generating appcast fragment in ${FEED_DIR}"
if [[ -n "${ED_KEY_FILE}" ]]; then
  echo "warning: using --ed-key-file (raw private key). Routine signing should use --account instead." >&2
  "${GEN}" --ed-key-file "${ED_KEY_FILE}" --download-url-prefix "${PREFIX}" "${FEED_DIR}"
else
  "${GEN}" --account "${ACCOUNT}" --download-url-prefix "${PREFIX}" "${FEED_DIR}"
fi

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
