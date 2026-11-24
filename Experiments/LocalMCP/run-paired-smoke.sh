#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "$0")" && pwd)"
work="$(mktemp -d "${TMPDIR:-/tmp}/rasc-mcp-spike.XXXXXX")"
trap 'rm -rf -- "$work"' EXIT

swift build --package-path "$root" --scratch-path "$work/build" --configuration release --disable-automatic-resolution
bin="$(swift build --package-path "$root" --scratch-path "$work/build" --configuration release --show-bin-path)"

make_app() {
    local app="$1" executable="$2" identifier="$3"
    mkdir -p "$app/Contents/MacOS"
    cat > "$app/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "https://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>$executable</string>
    <key>CFBundleIdentifier</key>
    <string>$identifier</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
</dict>
</plist>
PLIST
}

cat > "$work/host.entitlements" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<plist version="1.0"><dict>
    <key>com.apple.security.app-sandbox</key><true/>
</dict></plist>
PLIST

cat > "$work/helper.entitlements" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<plist version="1.0"><dict>
    <key>com.apple.security.app-sandbox</key><true/>
    <key>com.apple.security.temporary-exception.mach-lookup.global-name</key>
    <array><string>com.rafaeltorres.rasc.mcpspike</string></array>
</dict></plist>
PLIST

app="$work/Probe.app"
helper="$app/Contents/Helpers/PairedHelper.app"
make_app "$app" PairedMachProbe com.rafaeltorres.rasc.mcpspike
make_app "$helper" RascMCPProbe com.rafaeltorres.rasc.mcpspike.sandboxhelper
xcrun swiftc "$root/Controls/PairedMachProbe.swift" -o "$app/Contents/MacOS/PairedMachProbe"
cp "$bin/RascMCPProbe" "$helper/Contents/MacOS/"

sign_apps() {
    codesign --force --sign - --options runtime --entitlements "$work/helper.entitlements" "$helper"
    codesign --force --sign - --options runtime --entitlements "$work/host.entitlements" "$app"
    codesign --verify --deep --strict "$app"
}

run_smoke() {
    python3 "$root/paired-check.py" "$app/Contents/MacOS/PairedMachProbe" "$helper/Contents/MacOS/RascMCPProbe"
}

sign_apps
run_smoke
mv "$app" "$work/Previous.app"
ditto "$work/Previous.app" "$app"
plutil -insert CFBundleVersion -string 2 "$helper/Contents/Info.plist"
sign_apps
run_smoke
