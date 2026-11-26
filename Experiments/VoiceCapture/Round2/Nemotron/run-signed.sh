#!/usr/bin/env bash
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
bin="${1:?Path to the compiled Nemotron probe}"
model="${2:?Path to the staged 560ms model}"
fixtures="${3:?Path to the fixtures}"
out="${4:?Output scratch directory}"
shift 4
app="$out/NemotronProbe.app"
resources="$app/Contents/Resources"
mkdir -p "$app/Contents/MacOS" "$resources"
cp "$bin" "$app/Contents/MacOS/NemotronProbe"
if [[ ! -d "$resources/model" ]]; then cp -cR "$model" "$resources/model"; fi
cp "$fixtures"/*.wav "$resources/"
cat > "$app/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>com.rasc.research.voicestudy.nemotron</string>
<key>CFBundleExecutable</key><string>NemotronProbe</string>
<key>CFBundleName</key><string>Nemotron Probe</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleVersion</key><string>1</string>
</dict></plist>
PLIST
codesign --force --sign - --options runtime --entitlements "$here/../../design/design.entitlements" "$app"
codesign --verify --deep --strict "$app"
exec /usr/bin/time -l "$app/Contents/MacOS/NemotronProbe" "$@"
