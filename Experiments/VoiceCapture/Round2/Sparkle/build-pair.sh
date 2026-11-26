#!/usr/bin/env bash
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
repo="$(cd "${1:?Rasc checkout}" && pwd)"
out="${2:?Fresh test directory}"
tools="${3:?Sparkle 2.9.4 CLI bin path}"
port="${4:-18589}"
openssl="$(brew --prefix openssl@3)/bin/openssl"
mkdir -p "$out"/{install,update,feed}
umask 077
"$openssl" genpkey -algorithm ED25519 -out "$out/key.pem"
"$openssl" pkey -in "$out/key.pem" -outform DER | tail -c 32 | base64 > "$out/seed"
public_key="$("$openssl" pkey -in "$out/key.pem" -pubout -outform DER | tail -c 32 | base64)"
source_framework="$repo/Vendor/Sparkle/Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework"
xcrun clang -target arm64-apple-macosx26.0 -fobjc-arc -O2 \
  -F "$(dirname "$source_framework")" -framework AppKit -framework AVFoundation -framework Sparkle \
  -Wl,-rpath,@executable_path/../Frameworks "$here/Probe.m" -o "$out/VoiceUpdateProbe"
for version in 1 2; do
  if [[ "$version" == 1 ]]; then variant=install; else variant=update; fi
  app="$out/$variant/Rasc Voice Update Probe.app"
  frameworks="$app/Contents/Frameworks"
  mkdir -p "$app/Contents/MacOS" "$frameworks"
  cp "$out/VoiceUpdateProbe" "$app/Contents/MacOS/"
  python3 - "$app" "$version" "$port" "$public_key" <<'PY'
import plistlib
from pathlib import Path
import sys
app, version, port, public = sys.argv[1:]
identity = "com.rasc.research.voiceupdate"
target = Path(app) / "Contents/Info.plist"
target.write_bytes(plistlib.dumps({
 "CFBundleIdentifier": identity, "CFBundleName": "Rasc Voice Update Probe",
 "CFBundleVersion": version, "CFBundleShortVersionString": "0.0." + version,
 "CFBundleExecutable": "VoiceUpdateProbe", "LSUIElement": True, "CFBundlePackageType": "APPL",
 "SUFeedURL": f"http://127.0.0.1:{port}/appcast.xml", "SUPublicEDKey": public,
 "SUEnableInstallerLauncherService": True, "SUEnableDownloaderService": True,
 "SUEnableAutomaticChecks": False, "SUAllowsAutomaticUpdates": False, "SUVerifyUpdateBeforeExtraction": True,
 "NSAppTransportSecurity": {"NSAllowsLocalNetworking": True},
 "NSMicrophoneUsageDescription": "Check microphone permission continuity on this isolated update fixture. This app does not record audio.",
}))
(target.parent.parent.parent / "fixture-entitlements.plist").write_bytes(plistlib.dumps({
 "com.apple.security.app-sandbox": True,
 "com.apple.security.device.audio-input": True,
 "com.apple.security.cs.disable-library-validation": True,
 "com.apple.security.temporary-exception.mach-lookup.global-name": [identity + "-spki", identity + "-spks"],
}))
PY
  framework="$frameworks/Sparkle.framework"
  ditto "$source_framework" "$framework"
  for object in Versions/B/XPCServices/Installer.xpc Versions/B/XPCServices/Downloader.xpc Versions/B/Autoupdate Versions/B/Updater.app; do
    codesign --force --sign - --options runtime --preserve-metadata=identifier,entitlements "$framework/$object"
  done
  codesign --force --sign - --options runtime --preserve-metadata=identifier,entitlements "$framework"
  cdhash="$(codesign -dvvv "$framework/Versions/B/Sparkle" 2>&1 | awk -F= '/^CDHash=/{print $2}')"
  python3 - "$out/llc.plist" "$cdhash" <<'PY'
import plistlib, sys
with open(sys.argv[1], "wb") as handle:
    plistlib.dump({"cdhash": {"$in": [bytes.fromhex(sys.argv[2])]}}, handle)
PY
  codesign --validate-constraint "$out/llc.plist"
  codesign --force --sign - --options runtime --library-constraint "$out/llc.plist" \
    --entitlements "$out/$variant/fixture-entitlements.plist" "$app"
  codesign --verify --deep --strict "$app"
  codesign -d -r- "$app" > "$out/build-$version.txt" 2>&1
done
ditto -c -k --keepParent "$out/update/Rasc Voice Update Probe.app" "$out/feed/RascVoiceUpdate.zip"
"$tools/generate_appcast" --ed-key-file "$out/seed" --download-url-prefix "http://127.0.0.1:$port/" "$out/feed"
