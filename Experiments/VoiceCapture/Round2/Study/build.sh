#!/usr/bin/env bash
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
base="$(cd "${1:?Baseline Rasc checkout}" && pwd)"
build="$(cd "${2:?Initialized study build directory}" && pwd)"
output="${3:?Output study .app}"
models="${4:?Stage model packs first}"
fixtures="${5:-}"
mkdir -p "$output/Contents/MacOS" "$output/Contents/Resources/Models"
for source in "$here"/{Audio,Recognition,StudySession,VoiceStudy,LocalBenchmark}.swift \
  "$base"/Rasc/{UI/TransientSurfaceStyle,UI/RascSurfaceShell,UI/ShortcutKeycapView,UI/RascMotion,Settings/ThemeSettings,Domain/Note,Domain/NoteExport,Domain/RefinementRevision,Data/AppDatabase}.swift; do
    ln -sfn "$source" "$build/Sources/$(basename "$source")"
done
cat "$base/Rasc/Data/NoteRepository.swift" "$here/../../Persistence/RepositoryExtension.swift" \
  "$here/StudyRepository.swift" > "$build/Sources/NoteRepository.swift"
sed -n '/^struct RefinementMetadata/,/^}/p' "$base/Rasc/Domain/Refinement.swift" > "$build/Sources/RefinementMetadata.swift"
if [[ -e "$build/Sources/Bootstrap.swift" ]]; then mv "$build/Sources/Bootstrap.swift" "$build/Bootstrap.swift"; fi
swift build --package-path "$build" -c release -j 5
cp "$build/.build/release/VoiceStudy" "$output/Contents/MacOS/VoiceStudy"
for pack in fluid-pro ultra; do
  target="$output/Contents/Resources/Models/$pack"
  if [[ -d "$models/$pack" && ! -d "$target" ]]; then
    cp -cR "$models/$pack" "$target"
  fi
done
ultra="$output/Contents/Resources/Models/ultra"
if [[ -d "$ultra/JointDecisionv3.mlmodelc" && ! -e "$ultra/JointDecision.mlmodelc" ]]; then
  ln -s JointDecisionv3.mlmodelc "$ultra/JointDecision.mlmodelc"
fi
cp "$here/NOTICES.md" "$output/Contents/Resources/ThirdPartyNotices.md"
if [[ -n "$fixtures" ]]; then cp "$fixtures"/*.wav "$output/Contents/Resources/"; fi
cat > "$output/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>com.rasc.research.voicestudy</string>
<key>CFBundleExecutable</key><string>VoiceStudy</string>
<key>CFBundleName</key><string>Rasc Voice Study</string>
<key>CFBundleDisplayName</key><string>Rasc Voice Study</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleVersion</key><string>1</string>
<key>CFBundleShortVersionString</key><string>0.2.0</string>
<key>LSMinimumSystemVersion</key><string>26.0</string>
<key>LSMultipleInstancesProhibited</key><true/>
<key>NSMicrophoneUsageDescription</key><string>Rasc Voice Study uses the microphone only when you start a test recording. Transcription runs on this Mac.</string>
</dict></plist>
PLIST
codesign --force --sign - --options runtime --entitlements "$here/../../probe.entitlements" "$output"
codesign --verify --deep --strict "$output"
