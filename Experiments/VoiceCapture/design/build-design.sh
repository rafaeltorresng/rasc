#!/usr/bin/env bash
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
base="${1:?Path to Rasc source checkout}"
output="${2:?Output .app path}"
package_dir="${3:-}"
mkdir -p "$output/Contents/MacOS"
cat > "$output/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>com.rasc.research.voicedesign</string>
<key>CFBundleExecutable</key><string>VoiceDesign</string>
<key>CFBundleName</key><string>Rasc Voice Capture Lab</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleVersion</key><string>1</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
</dict></plist>
PLIST
sources=("$here/VoiceDesign.swift" "$base/Rasc/Settings/ThemeSettings.swift"
         "$base/Rasc/UI/TransientSurfaceStyle.swift" "$base/Rasc/UI/RascSurfaceShell.swift"
         "$base/Rasc/UI/ShortcutKeycapView.swift" "$base/Rasc/UI/RascMotion.swift")
if [[ -n "$package_dir" ]]; then
  mkdir -p "$package_dir/Sources"
  for source in "${sources[@]}"; do
    ln -sfn "$source" "$package_dir/Sources/$(basename "$source")"
  done
  cp "$here/Package.swift.template" "$package_dir/Package.swift"
  swift build --package-path "$package_dir" -c debug
  cp "$package_dir/.build/debug/VoiceDesign" "$output/Contents/MacOS/VoiceDesign"
else
  xcrun swiftc -swift-version 6 -Onone -target arm64-apple-macosx14.0 -parse-as-library \
    "${sources[@]}" -o "$output/Contents/MacOS/VoiceDesign"
fi
codesign --force --sign - --options runtime --entitlements "$here/design.entitlements" "$output"
codesign --verify --deep --strict "$output"
