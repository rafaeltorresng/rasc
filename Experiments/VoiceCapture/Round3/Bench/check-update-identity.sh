#!/usr/bin/env bash
set -euo pipefail
before="${1:?First signed app path}"
after="${2:?Second signed app path}"
verify() { /usr/bin/codesign --verify --deep --strict "$1"; }
requirement() { /usr/bin/codesign -d -r- "$1" 2>&1 | /usr/bin/sed -En 's/^(# )?designated => //p'; }
identifier() { /usr/bin/plutil -extract CFBundleIdentifier raw "$1/Contents/Info.plist"; }
check() {
  local label="$1" actual="$2" expected="$3"
  if /usr/bin/codesign --verify --strict -R "=$expected" "$actual" 2>/dev/null; then
    printf '%s\tmatch\n' "$label"
  else
    printf '%s\tno match\n' "$label"
  fi
}
verify "$before"
verify "$after"
prior="$(requirement "$before")"
next="$(requirement "$after")"
[[ -n "$prior" && -n "$next" ]]
printf 'Bundle before\t%s\nBundle after\t%s\n' "$(identifier "$before")" "$(identifier "$after")"
printf 'Designated requirement before\t%s\nDesignated requirement after\t%s\n' "$prior" "$next"
check 'Build A satisfies its requirement' "$before" "$prior"
check 'Build B satisfies its requirement' "$after" "$next"
check 'Build B satisfies requirement A' "$after" "$prior"
check 'Build A satisfies requirement B' "$before" "$next"
/usr/bin/security find-identity -v -p codesigning | /usr/bin/tail -n 1
