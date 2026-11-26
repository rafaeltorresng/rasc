#!/usr/bin/env bash
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
binary="${1:?Path to compiled ParakeetProbe}"
models="${2:?Staged model directory}"
fixtures="${3:?Synthetic fixture directory}"
results="${4:?Results directory}"
work="$(mktemp -d /tmp/rasc-parakeet-signed.XXXXXX)"
app="$work/RascParakeetProbe.app"
assets="$app/Contents/Resources"
mkdir -p "$app/Contents/MacOS" "$assets" "$results"
cp "$binary" "$app/Contents/MacOS/ParakeetProbe"
cp -cR "$models" "$assets/model"
cp "$fixtures"/*.wav "$assets/"
cat > "$app/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>com.rasc.research.parakeetprobe</string>
<key>CFBundleExecutable</key><string>ParakeetProbe</string>
<key>CFBundleName</key><string>Rasc Parakeet Probe</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleVersion</key><string>1</string>
</dict></plist>
PLIST
codesign --force --sign - --options runtime --entitlements "$here/../design/design.entitlements" "$app"
codesign --verify --deep --strict "$app"
codesign -d --entitlements - -r- "$app" > "$results/parakeet-signing.txt" 2>&1
/usr/bin/time -l "$app/Contents/MacOS/ParakeetProbe" batch "$assets/model" "$assets"/*.wav \
  > "$results/parakeet-batch.jsonl" 2> "$results/parakeet-batch-resources.txt"
