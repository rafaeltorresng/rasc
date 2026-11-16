#!/usr/bin/env bash
# Build a Sparkle-enabled Rasc release candidate with the proven ad-hoc signing
# approach (see docs/SPARKLE-LLC.md and docs/SPARKLE-RELEASE.md).
#
# Keeps every existing release invariant:
#   - App Sandbox + Hardened Runtime
#   - no network entitlement on the main app (Sparkle's XPC services do network I/O)
#   - ad-hoc signature with an Apple-documented Library Load Constraint (LLC) that
#     pins the exact cdhash(es) of the final signed Sparkle binary
#   - the Sparkle mach-lookup exceptions and the default user-selected read-only
#     entitlement; nothing else
#
# This is NOT the default Release build: the default keeps Rasc/Rasc.entitlements,
# embeds nothing, and is untouched by this script.
#
# Usage:
#   ./Scripts/release/build-updater-rc.sh                      # current project version (0.1.6, build 12)
#   RASC_RC_VERSION=0.1.7 RASC_RC_BUILD=13 ./Scripts/release/build-updater-rc.sh
#
# Environment overrides:
#   RASC_RC_VERSION                  marketing version                   (default: from project)
#   RASC_RC_BUILD                    build number                       (default: from project)
#   RASC_RC_ARCHS                    shipped architectures, e.g. arm64  (default: arm64; an
#                                    LLC entry is computed per shipped slice of the final
#                                    signed Sparkle framework)
#   RASC_RC_FEED_URL                 SUFeedURL                            (default: https://rasc.app/appcast.xml)
#   SPARKLE_ACCOUNT                  named login-keychain account used for public-key lookup
#                                    and Sparkle's signing tools        (default: rasc-sparkle)
#   RASC_RC_ED25519_PUBLIC_KEY       base64 Ed25519 public key to stamp  (default: looked up from
#                                    the login keychain via generate_keys -p --account; overrides
#                                    the keychain value for staging/test use)
#   RASC_RC_ED25519_ENFORCE          "1" refuses to build without a key  (default: 1)
#
# The RC artifacts are deliberately not publishable: they must be rebuilt with a
# production key and a stable HTTPS feed before any release.
set -euo pipefail

source "$(dirname "$0")/common.sh"

require_command xcodebuild
require_command codesign
require_command ditto
require_command hdiutil
require_command lipo
require_command python3
require_command /usr/libexec/PlistBuddy

RC_VERSION="${RASC_RC_VERSION:-$(marketing_version_from_project)}"
RC_BUILD="${RASC_RC_BUILD:-$(build_number_from_project)}"
RC_ARCHS="${RASC_RC_ARCHS:-arm64}"
RC_FEED_URL="${RASC_RC_FEED_URL:-https://rasc.app/appcast.xml}"
RC_DIR="${BUILD_DIR}/updater-rc/${RC_VERSION}"
RC_DERIVED_DATA="${RC_DIR}/DerivedData"
RC_EXPORT_DIR="${RC_DIR}/export"
RC_APP_PATH="${RC_EXPORT_DIR}/Rasc.app"
RC_STAGING_DIR="${RC_DIR}/dmg-staging"
DMG_PATH="${RC_DIR}/Rasc-${RC_VERSION}-updater.dmg"
CHECKSUM_PATH="${DMG_PATH}.sha256"

SPARKLE_FRAMEWORK_SOURCE="${ROOT_DIR}/Vendor/Sparkle/Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework"
SPARKLE_ENTITLEMENTS_SOURCE="${ROOT_DIR}/Rasc/Rasc.sparkle.entitlements"
SPARKLE_TOOLS_BIN="${ROOT_DIR}/build/sparkle-tools/bin"
SPARKLE_ACCOUNT="${SPARKLE_ACCOUNT:-rasc-sparkle}"

echo "==> Updater RC: version ${RC_VERSION} (build ${RC_BUILD}), archs='${RC_ARCHS}'"
echo "==> Feed URL: ${RC_FEED_URL}"
echo "==> Sparkle keychain account: ${SPARKLE_ACCOUNT}"

# Resolve the public key from the login keychain unless the caller provided one.
# Routine use never requires a raw private-key file.
GEN_KEYS="${SPARKLE_TOOLS_BIN}/generate_keys"
if [[ -z "${RASC_RC_ED25519_PUBLIC_KEY:-}" && -f "${GEN_KEYS}" ]]; then
  RASC_RC_ED25519_PUBLIC_KEY="$("${GEN_KEYS}" -p --account "${SPARKLE_ACCOUNT}" 2>/dev/null || true)"
  if [[ "${RASC_RC_ED25519_PUBLIC_KEY}" == *"ERROR"* || "${RASC_RC_ED25519_PUBLIC_KEY}" == *"No existing signing key"* ]]; then
    RASC_RC_ED25519_PUBLIC_KEY=""
  fi
fi

if [[ ! -d "${SPARKLE_FRAMEWORK_SOURCE}" ]]; then
  echo "error: vendored Sparkle framework not found at ${SPARKLE_FRAMEWORK_SOURCE}" >&2
  exit 1
fi
if [[ ! -f "${SPARKLE_ENTITLEMENTS_SOURCE}" ]]; then
  echo "error: updater entitlements not found at ${SPARKLE_ENTITLEMENTS_SOURCE}" >&2
  exit 1
fi

# Fail fast, before compiling: refuse to build an updater candidate without a
# real Ed25519 public key. Otherwise a silent placeholder key produces a build
# whose updater never works.
RASC_RC_ED25519_ENFORCE="${RASC_RC_ED25519_ENFORCE:-1}"
if [[ -z "${RASC_RC_ED25519_PUBLIC_KEY:-}" ]] && [[ "${RASC_RC_ED25519_ENFORCE}" == "1" ]]; then
  echo "error: no Ed25519 public key available; refusing to build." >&2
  echo "       Look in the login keychain under account '${SPARKLE_ACCOUNT}' via:" >&2
  echo "         build/sparkle-tools/bin/generate_keys -p --account ${SPARKLE_ACCOUNT}" >&2
  echo "       or set an explicit override:" >&2
  echo "         export RASC_RC_ED25519_PUBLIC_KEY=\"<base64 Ed25519 public key>\"" >&2
  echo "       (or set RASC_RC_ED25519_ENFORCE=0 for an intentionally inert RC)" >&2
  exit 1
fi

if [[ -d "${RC_DIR}" ]]; then
  echo "error: ${RC_DIR} already exists. Move it aside first to retain the artifact:" >&2
  echo "       mv ${RC_DIR} ${RC_DIR}-retained-\$(date +%Y%m%d%H%M%S)" >&2
  exit 1
fi
mkdir -p "${RC_EXPORT_DIR}"

echo "==> Clean Release build (ARCHS=${RC_ARCHS}, ad-hoc signing, Sparkle entitlements)..."
xcodebuild \
  -project "${PROJECT_PATH}" \
  -scheme "${SCHEME}" \
  -configuration "${CONFIGURATION}" \
  -derivedDataPath "${RC_DERIVED_DATA}" \
  -destination "platform=macOS,arch=arm64" \
  clean build \
  ARCHS="${RC_ARCHS}" \
  ONLY_ACTIVE_ARCH=NO \
  CODE_SIGN_STYLE=Manual \
  CODE_SIGN_IDENTITY=- \
  DEVELOPMENT_TEAM= \
  CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO \
  CODE_SIGN_ENTITLEMENTS="${SPARKLE_ENTITLEMENTS_SOURCE}" \
  MARKETING_VERSION="${RC_VERSION}" \
  CURRENT_PROJECT_VERSION="${RC_BUILD}"

BUILT_APP="${RC_DERIVED_DATA}/Build/Products/${CONFIGURATION}/Rasc.app"
XCENT="${RC_DERIVED_DATA}/Build/Intermediates.noindex/Rasc.build/${CONFIGURATION}/Rasc.build/Rasc.app.xcent"

if [[ ! -d "${BUILT_APP}" ]]; then
  echo "error: built app not found at ${BUILT_APP}" >&2
  exit 1
fi
if [[ ! -f "${XCENT}" ]]; then
  echo "error: expanded entitlements not found at ${XCENT}" >&2
  exit 1
fi

echo "==> Expanded entitlements:"
plutil -p "${XCENT}"
if grep -q '\$(' "${XCENT}"; then
  echo "error: build settings were not expanded in ${XCENT}" >&2
  exit 1
fi

echo "==> Verifying no network entitlement on the main app..."
BUILT_ENTITLEMENTS_OUT="$(codesign -d --entitlements :- "${BUILT_APP}" 2>/dev/null)"
if grep -q 'network.client' <<< "${BUILT_ENTITLEMENTS_OUT}"; then
  echo "error: the main app must not have com.apple.security.network.client" >&2
  exit 1
fi

echo "==> Pointing the RC at the configured feed and public key..."
/usr/libexec/PlistBuddy -c "Set :SUFeedURL ${RC_FEED_URL}" "${BUILT_APP}/Contents/Info.plist"

if [[ -n "${RASC_RC_ED25519_PUBLIC_KEY:-}" ]]; then
  /usr/libexec/PlistBuddy -c "Set :SUPublicEDKey ${RASC_RC_ED25519_PUBLIC_KEY}" "${BUILT_APP}/Contents/Info.plist"
  echo "==> SUPublicEDKey injected (from keychain account ${SPARKLE_ACCOUNT} or via RASC_RC_ED25519_PUBLIC_KEY override)."
else
  RASC_RC_ED25519_ENFORCE="${RASC_RC_ED25519_ENFORCE:-1}"
  if [[ "${RASC_RC_ED25519_ENFORCE}" == "1" ]]; then
    echo "error: no Ed25519 public key injected and none found in keychain account ${SPARKLE_ACCOUNT}." >&2
    echo "       Create it with: build/sparkle-tools/bin/generate_keys --account ${SPARKLE_ACCOUNT}" >&2
    exit 1
  fi
  echo "==> SUPublicEDKey: keeping the production placeholder (updater inert)."
fi

echo "==> Copying app to ${RC_APP_PATH}..."
ditto "${BUILT_APP}" "${RC_APP_PATH}"

embed_and_sign_sparkle() {
  local app="$1"
  local framework="${app}/Contents/Frameworks/Sparkle.framework"
  mkdir -p "${app}/Contents/Frameworks"
  ditto "${SPARKLE_FRAMEWORK_SOURCE}" "${framework}"
  codesign --force --sign - --options runtime \
    --preserve-metadata=identifier,entitlements \
    "${framework}/Versions/B/XPCServices/Installer.xpc"
  codesign --force --sign - --options runtime \
    --preserve-metadata=identifier,entitlements \
    "${framework}/Versions/B/XPCServices/Downloader.xpc"
  codesign --force --sign - --options runtime \
    --preserve-metadata=identifier,entitlements \
    "${framework}/Versions/B/Autoupdate"
  codesign --force --sign - --options runtime \
    --preserve-metadata=identifier,entitlements \
    "${framework}/Versions/B/Updater.app"
  codesign --force --sign - --options runtime \
    --preserve-metadata=identifier,entitlements \
    "${framework}"
}

cdhash_of() {
  # cdhash of one arch slice (codesign reports the arm64 slice for fat binaries)
  codesign -dvvv --arch "$1" "$2" 2>&1 | awk -F= '/^CDHash=/{print $2}'
}

embed_and_sign_sparkle "${RC_APP_PATH}"
FRAMEWORK_BIN="${RC_APP_PATH}/Contents/Frameworks/Sparkle.framework/Versions/B/Sparkle"

echo "==> Computing the Library Load Constraint for shipped archs..."
SPARKLE_ARCHES="$(lipo -info "${FRAMEWORK_BIN}" | awk -F: '{print $2}')"
echo "    framework archs: ${SPARKLE_ARCHES}"

LLC_PLIST="${RC_DIR}/library-constraint.plist"
python3 - "${LLC_PLIST}" "${RC_ARCHS}" "${FRAMEWORK_BIN}" <<'PY'
import plistlib
import subprocess
import sys

destination, shipped_archs, framework = sys.argv[1], sys.argv[2].split(), sys.argv[3]
entries = []
for arch in shipped_archs:
    result = subprocess.run(
        ["codesign", "-dvvv", "--arch", arch, framework],
        capture_output=True, text=True, check=True,
    )
    cdhash = None
    for line in result.stderr.splitlines():
        if line.startswith("CDHash="):
            cdhash = line.split("=", 1)[1].strip()
            break
    if cdhash is None:
        print(f"error: could not read cdhash for arch {arch}", file=sys.stderr)
        sys.exit(1)
    entries.append(bytes.fromhex(cdhash))
constraint = {"cdhash": {"$in": entries}}
with open(destination, "wb") as handle:
    plistlib.dump(constraint, handle)
print(f"pinned {len(entries)} arch slice(s): {', '.join(e.hex() for e in entries)}")
PY

codesign --validate-constraint "${LLC_PLIST}"

echo "==> Re-signing the app with the LLC..."
codesign --force --sign - --options runtime \
  --entitlements "${XCENT}" \
  --library-constraint "${LLC_PLIST}" \
  "${RC_APP_PATH}"

echo "==> Verifying the signed app matches the pinned constraint..."
codesign --verify --deep --strict --verbose=2 "${RC_APP_PATH}"

DISPLAY_OUT="$(codesign -dvvv "${RC_APP_PATH}" 2>&1)"
if ! grep -q 'Has Library Load Constraints' <<< "${DISPLAY_OUT}"; then
  echo "error: the bundle is signed but shows no Library Load Constraints" >&2
  echo "       the constraint was not embedded; refusing to package" >&2
  exit 1
fi

python3 - "${LLC_PLIST}" "${RC_ARCHS}" "${FRAMEWORK_BIN}" <<'PY'
import plistlib
import subprocess
import sys

plist_path, shipped_archs, framework = sys.argv[1], sys.argv[2].split(), sys.argv[3]
with open(plist_path, "rb") as handle:
    constraint = plistlib.load(handle)
pinned = {bytes(v).hex() for v in constraint["cdhash"]["$in"]}
missing = []
for arch in shipped_archs:
    result = subprocess.run(
        ["codesign", "-dvvv", "--arch", arch, framework],
        capture_output=True, text=True, check=True,
    )
    cdhash = None
    for line in result.stderr.splitlines():
        if line.startswith("CDHash="):
            cdhash = line.split("=", 1)[1].strip()
            break
    if cdhash not in pinned:
        missing.append(cdhash)
if missing:
    print("error: shipped-arch cdhashes not found in the embedded pin:", ", ".join(missing), file=sys.stderr)
    sys.exit(1)
print("constraint covers every shipped-arch cdhash of the final signed Sparkle framework")
PY

echo "==> Confirming no network entitlement on the signed main app..."
ENTITLEMENTS_OUT="$(codesign -d --entitlements :- "${RC_APP_PATH}" 2>/dev/null)"
if grep -q 'network.client' <<< "${ENTITLEMENTS_OUT}"; then
  echo "error: the main app must not have com.apple.security.network.client" >&2
  exit 1
fi

echo "==> Packaging DMG..."
package_dmg "${RC_APP_PATH}" "${DMG_PATH}" "${RC_STAGING_DIR}"

echo "==> Writing SHA-256 checksum..."
write_sha256_checksum "${DMG_PATH}" "${CHECKSUM_PATH}"

cat <<EOF

Updater RC ready:

  App:        ${RC_APP_PATH}
  DMG:        ${DMG_PATH}
  Checksum:   ${CHECKSUM_PATH}
  LLC plist:  ${LLC_PLIST}

  Version:    ${RC_VERSION}
  Build:      ${RC_BUILD}
  Archs:      ${RC_ARCHS}
  Feed:       ${RC_FEED_URL}

Next steps (see docs/SPARKLE-RELEASE.md):
  1. Record \"spctl --assess\" + DMG SHA-256; attach DMG + .sha256 to the test
     GitHub release (never a public one for RC artifacts).
  2. Generate appcast keychain-solved: ./Scripts/release/generate-release-appcast.sh \\
       --version ${RC_VERSION} \\
       --prefix https://github.com/rafaeltorresng/rasc/releases/download/v${RC_VERSION}/ \\
       --dmg ${DMG_PATH} \\
       --account ${SPARKLE_ACCOUNT} \\
       --public-key-pem <public-key.pem>
  3. Publish only after the clean-Mac test in docs/SPARKLE-RELEASE.md passes.

Routine signing reads the login-keychain account '${SPARKLE_ACCOUNT}' — no
raw private key is required. Read it out with:
  build/sparkle-tools/bin/generate_keys -p --account ${SPARKLE_ACCOUNT}

This artifact is a release candidate, not a public release. Do not upload it to
the rasc.app feed or GitHub Releases without the maintainer's sign-off.
EOF
