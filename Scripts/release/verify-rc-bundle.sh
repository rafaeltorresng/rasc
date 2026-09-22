#!/usr/bin/env bash
set -euo pipefail

source "$(dirname "$0")/common.sh"

APP_PATH="${1:-${BETA_APP_PATH:-}}"

if [[ -z "${APP_PATH}" || ! -d "${APP_PATH}" ]]; then
  echo "usage: $0 path-to-Rasc.app" >&2
  exit 1
fi

EXECUTABLE="${APP_PATH}/Contents/MacOS/Rasc"
if [[ ! -f "${EXECUTABLE}" ]]; then
  echo "error: main executable not found at ${EXECUTABLE}" >&2
  exit 1
fi

echo "==> RC bundle policy checks"

MARKETING_VERSION="$(marketing_version_from_app "${APP_PATH}")"
BUILD_NUMBER="$(build_number_from_app "${APP_PATH}")"
echo "Version: ${MARKETING_VERSION} (${BUILD_NUMBER})"

if [[ "${MARKETING_VERSION}" != "$(marketing_version_from_project)" ]]; then
  echo "error: marketing version mismatch with project" >&2
  exit 1
fi

echo "==> Architecture"
file "${EXECUTABLE}"

echo "==> Rejected M12C-002 preference must be absent"
FORBIDDEN_STRINGS=(
  'refineStylePreference'
  'RefinePreferenceSettingsStore'
  'refine-v2-global-preference'
  '<refine_preference>'
  'Refine preferences'
)
for needle in "${FORBIDDEN_STRINGS[@]}"; do
  if grep -Fq "${needle}" < <(strings "${EXECUTABLE}"); then
    echo "error: found rejected M12C-002 string in binary: ${needle}" >&2
    exit 1
  fi
done
echo "M12C-002 strings absent"

echo "==> M12C-001 / refine-v2 baseline present"
if ! grep -Fq 'refine-v2-language-preference' < <(strings "${EXECUTABLE}"); then
  echo "error: expected production prompt version refine-v2-language-preference" >&2
  exit 1
fi
if ! grep -Fq 'RefineLanguageSettingsStore' < <(strings "${EXECUTABLE}"); then
  echo "error: RefineLanguageSettingsStore not found in binary" >&2
  exit 1
fi
echo "M12C-001 language preference wiring present"

echo "==> DEBUG eval CLI must be unreachable in Release"
DEBUG_STRINGS=(
  '--run-refine-evals'
  '--run-refine-review'
  'RefineEvalCommandLine'
)
for needle in "${DEBUG_STRINGS[@]}"; do
  if grep -F -- "${needle}" < <(strings "${EXECUTABLE}"); then
    echo "error: DEBUG eval path string found in Release binary: ${needle}" >&2
    exit 1
  fi
done
echo "DEBUG eval CLI strings absent"

echo "==> Release configuration"
if find "${APP_PATH}" -name '*.debug.dylib' -print -quit | grep -q .; then
  echo "error: debug dylib found in Release bundle" >&2
  exit 1
fi
if [[ -d "${APP_PATH}/Contents/PlugIns" ]] && find "${APP_PATH}/Contents/PlugIns" -name '*Tests*' -print -quit | grep -q .; then
  echo "error: test plug-in found in bundle" >&2
  exit 1
fi

echo "RC bundle verification passed for ${APP_PATH}"
