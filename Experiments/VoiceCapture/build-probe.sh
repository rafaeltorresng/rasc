#!/usr/bin/env bash
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
output="${1:?Pass a fresh output .app path}"
fixtures="${2:-}"
mkdir -p "$output/Contents/MacOS" "$output/Contents/Resources"
if [[ -n "$fixtures" ]]; then
  cp "$fixtures"/*.wav "$output/Contents/Resources/"
fi
cat > "$output/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>com.rasc.research.voiceprobe</string>
<key>CFBundleExecutable</key><string>VoiceProbe</string>
<key>CFBundleName</key><string>Rasc Voice Capture Probe</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleVersion</key><string>1</string>
<key>LSUIElement</key><true/>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>NSMicrophoneUsageDescription</key><string>Measure how quickly the test microphone becomes ready. Samples are discarded.</string>
</dict></plist>
PLIST
xcrun swiftc -swift-version 6 -O -target arm64-apple-macosx14.0 -parse-as-library \
  "$here/AppleProbe.swift" -o "$output/Contents/MacOS/VoiceProbe"
codesign --force --sign - --options runtime --entitlements "$here/probe.entitlements" "$output"
codesign --verify --deep --strict "$output"
