# Sparkle 2 proof: build, sign, feed, verify

This directory contains the reproducible zero-cost proof for Sparkle 2 in-app
updates. It is **not** a production release procedure.

Status: superseded by the Library Load Constraint proof (docs/SPARKLE-LLC.md)
and the updater RC pipeline (Scripts/release/build-updater-rc.sh +
docs/SPARKLE-RELEASE.md). This directory and doc are kept for the historical
evidence trail.

Previous status: the integration is implemented, but an actual in-place update cannot run
under ad-hoc signing. Hardened Runtime enables Library Validation, and an
ad-hoc signature has no Team ID, so macOS rejects `Sparkle.framework`. With the
current weak link the app still launches, `dyld` skips Sparkle, and updates are
unavailable. See [../../docs/SPARKLE-UPDATES.md](../../docs/SPARKLE-UPDATES.md)
for the full report and evidence.

Run every command from the repository root.

## Prerequisites

- Apple Silicon Mac running macOS 14 or later.
- Xcode with the macOS SDK.
- `python3`, `curl`, and **OpenSSL 3** (`openssl version` must report 3.x;
  Homebrew's `openssl@3` is fine). The verifier uses Ed25519 `pkeyutl -rawin`.
- Sparkle **2.9.4** command-line tools. The framework is vendored at
  `Vendor/Sparkle/Sparkle.xcframework`; the CLI tools are not.

Download and verify the official tools once (the archive is also the source of
the vendored framework):

```bash
mkdir -p build/sparkle-tools
curl -L --fail -o build/Sparkle-2.9.4.tar.xz \
  https://github.com/sparkle-project/Sparkle/releases/download/2.9.4/Sparkle-2.9.4.tar.xz
echo "ce89daf967db1e1893ed3ebd67575ed82d3902563e3191ca92aaec9164fbdef9  build/Sparkle-2.9.4.tar.xz" \
  | shasum -a 256 -c -
tar -xf build/Sparkle-2.9.4.tar.xz -C build/sparkle-tools --strip-components=1
test -x build/sparkle-tools/bin/generate_appcast
```

No Apple Developer identity is required for this proof. No paid service,
notarization, or backend is used.

## 1. Create a disposable Ed25519 key

The proof avoids the login keychain. `generate_appcast` accepts a raw base64
private key via `--ed-key-file`. The file is the base64 encoding of the 32-byte
Ed25519 seed; the public key is the base64 encoding of the 32-byte public key.

```bash
mkdir -p build/sparkle-proof/keys
cd build/sparkle-proof/keys

openssl genpkey -algorithm ED25519 -out private.pem
openssl pkey -in private.pem -outform DER -out private.der
openssl pkey -in private.pem -pubout -out public.pem
openssl pkey -pubin -in public.pem -outform DER -out public.der

# Ed25519 private DER is a 16-byte prefix followed by the 32-byte seed.
tail -c 32 private.der | base64 | tr -d '\n' > sparkle_private_key
# Ed25519 public DER is a 12-byte prefix followed by the 32-byte public key.
tail -c 32 public.der | base64 | tr -d '\n' > sparkle_public_key

printf '%s\n' 'rasc sparkle proof payload' > payload.txt
openssl pkeyutl -sign -rawin -inkey private.pem -in payload.txt -out payload.sig
openssl pkeyutl -verify -pubin -inkey public.pem -rawin \
  -in payload.txt -sigfile payload.sig

wc -c sparkle_private_key sparkle_public_key   # both are 44 bytes
cd -
```

Expected output ends with `Signature Verified Successfully`. The private key is
disposable; never commit it or use it for a real release.

The proof key in this working tree is:

```text
p3FfrWDwvxSNrshM0AKoOSfiw2L+OFTHTSbcVnN/5L0=
```

Regenerating the key changes this value, so rebuild both apps after changing it.

## 2. Build two ad-hoc Release variants

`build-variant.sh` builds the normal Release configuration with ad-hoc signing,
Hardened Runtime, App Sandbox, and the Sparkle-only entitlements. It then:

1. Verifies that Xcode expanded `$(PRODUCT_BUNDLE_IDENTIFIER)` in the generated
   `.xcent` file.
2. Sets `SUFeedURL` to the local HTTPS feed and `SUPublicEDKey` to the proof key.
3. Embeds `Sparkle.framework` in `Contents/Frameworks`.
4. Signs `Installer.xpc`, `Downloader.xpc`, `Autoupdate`, `Updater.app`, and the
   framework explicitly with `--options runtime`, preserving their identifiers
   and entitlements.
5. Re-signs the app with the expanded entitlements and verifies the bundle
   deeply.
6. Packages a DMG.

```bash
./Scripts/sparkle-proof/build-variant.sh \
  0.1.7 13 build/sparkle-proof/repro/dist/0.1.7
./Scripts/sparkle-proof/build-variant.sh \
  0.1.8 14 build/sparkle-proof/repro/dist/0.1.8
```

Expected: `BUILD SUCCEEDED`, `codesign --verify --deep --strict` passes, and
each DMG is written to the output directory.

Inspect the result:

```bash
APP=build/sparkle-proof/repro/dist/0.1.7/DerivedData/Build/Products/Release/Rasc.app

codesign --verify --deep --strict --verbose=2 "$APP"
codesign -dvvv "$APP" 2>&1 | grep -E 'Identifier|TeamIdentifier|flags'
otool -l "$APP/Contents/MacOS/Rasc" | grep -A3 LC_LOAD_WEAK_DYLIB
/usr/libexec/PlistBuddy -c 'Print :SUFeedURL' "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Print :SUPublicEDKey' "$APP/Contents/Info.plist"
codesign -d --entitlements :- "$APP" 2>/dev/null | plutil -p -
```

Expected:

- `TeamIdentifier=not set` for the app and Sparkle.
- `LC_LOAD_WEAK_DYLIB` for
  `@rpath/Sparkle.framework/Versions/B/Sparkle`.
- `SUFeedURL` is `https://127.0.0.1:8443/appcast.xml`.
- `SUPublicEDKey` is the proof key above.
- Entitlements contain App Sandbox, user-selected read-only, and the two
  mach-lookup exceptions for `com.rafaeltorres.rasc-spks` and
  `com.rafaeltorres.rasc-spki`.

The `TeamIdentifier=not set` line is the blocker. The app can be signed and
packaged, but Hardened Runtime will not load the framework at runtime.

## 3. Generate the appcast and delta

```bash
rm -rf build/sparkle-proof/feed
mkdir -p build/sparkle-proof/feed
cp build/sparkle-proof/repro/dist/0.1.7/Rasc-0.1.7.dmg build/sparkle-proof/feed/
cp build/sparkle-proof/repro/dist/0.1.8/Rasc-0.1.8.dmg build/sparkle-proof/feed/

build/sparkle-tools/bin/generate_appcast \
  --ed-key-file build/sparkle-proof/keys/sparkle_private_key \
  --download-url-prefix https://127.0.0.1:8443/ \
  build/sparkle-proof/feed
```

Expected: `appcast.xml` and a `Rasc14-13.delta` (or similarly named delta) in
`build/sparkle-proof/feed/`. `generate_appcast` may warn that the two ad-hoc
builds have different code-signing identities. That warning is harmless here;
it is comparing ad-hoc CD hashes, not Team IDs.

The appcast must contain Ed25519 signatures and exact lengths for both DMGs and
the delta. Do not hand-edit these values.

## 4. Verify signatures and tamper rejection

The verifier uses OpenSSL, not Sparkle, so it works even though the app cannot
load the framework.

```bash
python3 Scripts/sparkle-proof/verify-appcast.py \
  --feed build/sparkle-proof/feed \
  --public-key build/sparkle-proof/keys/public.pem \
  --tamper
```

Expected output:

```text
Signature Verified Successfully
...
RESULT: PASS
```

The `--tamper` option flips one byte at offset 1024 in the newest DMG, then
checks that the same signature fails. Expected: `PASS: tampered payload
rejected`. The tampered copy is left in
`build/sparkle-proof/evidence/Rasc-0.1.8-tampered.dmg`.

To inspect a single DMG signature, `sign_update` can print the values it would
put in the appcast:

```bash
build/sparkle-tools/bin/sign_update \
  --ed-key-file build/sparkle-proof/keys/sparkle_private_key \
  -p build/sparkle-proof/feed/Rasc-0.1.8.dmg
```

Compare that signature with the `sparkle:edSignature` on the 0.1.8 enclosure in
`appcast.xml`. The Python verifier above is the authoritative check.

## 5. Serve the feed over HTTPS

Sparkle requires HTTPS. A self-signed CA is enough for the transport proof, but
macOS will not trust it until the CA is explicitly trusted. That trust change
requires user authorization and was **not** performed in this proof.

Generate a short-lived test CA and a server certificate for `127.0.0.1`:

```bash
mkdir -p build/sparkle-proof/tls
cd build/sparkle-proof/tls

cat > ca.cnf <<'EOF'
[req]
distinguished_name = dn
x509_extensions = ext
prompt = no
[dn]
CN = Rasc Sparkle Test CA
O = Rasc Test
[ext]
basicConstraints = critical,CA:true
keyUsage = critical,keyCertSign,cRLSign
subjectKeyIdentifier = hash
EOF

cat > server.cnf <<'EOF'
[req]
distinguished_name = dn
prompt = no
[dn]
CN = 127.0.0.1
O = Rasc Test
[ext]
basicConstraints = critical,CA:false
keyUsage = critical,digitalSignature,keyEncipherment
extendedKeyUsage = serverAuth
subjectAltName = @alt
[alt]
IP.1 = 127.0.0.1
DNS.1 = localhost
EOF

openssl req -x509 -newkey rsa:2048 -nodes -days 2 \
  -keyout ca-key.pem -out ca-cert.pem -config ca.cnf
openssl req -newkey rsa:2048 -nodes \
  -keyout server-key.pem -out server.csr -config server.cnf
openssl x509 -req -in server.csr -CA ca-cert.pem -CAkey ca-key.pem \
  -CAcreateserial -out server-cert.pem -days 2 \
  -extfile server.cnf -extensions ext
cat server-cert.pem ca-cert.pem > server-chain.pem
openssl verify -CAfile ca-cert.pem server-cert.pem

cd -
```

Serve it:

```bash
python3 Scripts/sparkle-proof/serve_feed.py \
  build/sparkle-proof/feed 8443 \
  build/sparkle-proof/tls/server-chain.pem \
  build/sparkle-proof/tls/server-key.pem
```

In another terminal, verify the transport:

```bash
curl --cacert build/sparkle-proof/tls/ca-cert.pem -fsS \
  https://127.0.0.1:8443/appcast.xml | head -5

curl --cacert build/sparkle-proof/tls/ca-cert.pem -fsSI \
  https://127.0.0.1:8443/Rasc-0.1.8.dmg

# Expected to fail with a self-signed certificate error:
curl -fsS https://127.0.0.1:8443/appcast.xml
```

For Sparkle itself to fetch this feed, the test CA must be trusted:

```bash
security add-trusted-cert -r trustRoot \
  -k "$HOME/Library/Keychains/login.keychain-db" \
  build/sparkle-proof/tls/ca-cert.pem
```

macOS presents a Touch ID/password authorization dialog for this change. The
prompt was captured at `build/sparkle-proof/evidence/ca-trust-prompt.png` and
cancelled, so Sparkle's own HTTPS fetch was not exercised. Remove the CA
afterwards if it was trusted:

```bash
security delete-certificate -c "Rasc Sparkle Test CA" \
  "$HOME/Library/Keychains/login.keychain-db"
```

## 6. Install and observe the blocker

```bash
pkill -f "/Applications/Rasc.app/Contents/MacOS/Rasc" 2>/dev/null || true
rm -rf /Applications/Rasc.app
ditto \
  build/sparkle-proof/repro/dist/0.1.7/DerivedData/Build/Products/Release/Rasc.app \
  /Applications/Rasc.app
open /Applications/Rasc.app
sleep 3

PID=$(pgrep -f "/Applications/Rasc.app/Contents/MacOS/Rasc" | head -1)
echo "PID=$PID"
lsof -p "$PID" | grep -i sparkle || echo "Sparkle not mapped"
```

Expected: the app is running, but `Sparkle not mapped` is printed. Click the
menu-bar icon and choose **Check for Updates…**. The app shows:

> Updates are not available in this build.

This is the exact blocker. `dyld` rejected `Sparkle.framework` because the app
and framework have no Team ID, and the weak link let the app continue without
it. There is no updater object to check, download, verify, extract, or relaunch.

For comparison, a strong-link build aborts at launch with:

```text
Library not loaded: @rpath/Sparkle.framework/Versions/B/Sparkle
Reason: ... mapping process and mapped file (non-platform) have different Team IDs
```

The recorded crash is
`build/sparkle-proof/evidence/rasc-0.1.7-release-launch-crash.ips`.

### The update test that remains blocked

Once an Apple-issued Team ID is available, run the full test on a clean Mac,
outside Xcode:

1. Browser-download the 0.1.7 DMG and copy **Rasc** to `/Applications`.
2. Launch 0.1.7. Confirm notes, preferences, and shortcuts exist.
3. **Check for Updates…** → 0.1.8 is offered.
4. Confirm the install. Sparkle downloads, verifies the Ed25519 signature before
   extraction, installs, and relaunches.
5. Verify the running version is 0.1.8 and that notes, preferences, and
   shortcuts survived.
6. Repeat from the published v0.1.5 build: it has no updater, so the first
   Sparkle-enabled release must be installed manually and opened with
   **Open Anyway** on first launch.
7. Verify a tampered DMG is rejected and the installed app is unchanged.

None of steps 3–7 can run in this proof.

## 7. Check the default production Release

The normal Release configuration must remain launchable and must not contain
Sparkle:

```bash
xcodebuild \
  -project Rasc.xcodeproj \
  -scheme Rasc \
  -configuration Release \
  -derivedDataPath build/sparkle-proof/DerivedData-default \
  -destination 'platform=macOS,arch=arm64' \
  CODE_SIGN_STYLE=Manual \
  CODE_SIGN_IDENTITY=- \
  DEVELOPMENT_TEAM= \
  CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO \
  clean build

APP=build/sparkle-proof/DerivedData-default/Build/Products/Release/Rasc.app
test ! -e "$APP/Contents/Frameworks/Sparkle.framework"
otool -l "$APP/Contents/MacOS/Rasc" | grep -A3 LC_LOAD_WEAK_DYLIB
codesign -d --entitlements :- "$APP" 2>/dev/null | plutil -p -

open "$APP"
sleep 3
pgrep -fl "$APP/Contents/MacOS/Rasc"
```

Expected:

- No `Contents/Frameworks/Sparkle.framework`.
- `LC_LOAD_WEAK_DYLIB` for Sparkle (the symbol is allowed, but the library is
  absent).
- Entitlements contain only App Sandbox and user-selected read-only. No
  mach-lookup exceptions, no network entitlement.
- The app launches and **Check for Updates…** shows the unavailable alert.

## 8. Run the full test suite

Do **not** pass `CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO` to a Debug test build.
Without Xcode's normal `get-task-allow` entitlement, the test host can hang
before establishing a connection.

Keep DerivedData outside the repository and outside an iCloud-synced Desktop.
A file-provider stall in dyld can otherwise look like a test-runner hang.

Close notification banners and other apps' alerts before running the suite.
`PanelControllerTests` intentionally lowers the scratchpad level when another
app has a modal-level window on screen, so a visible notification can make those
five tests fail.

```bash
TEST_DERIVED_DATA="${TMPDIR:-/tmp}/RascTests-DerivedData"

xcodebuild test \
  -project Rasc.xcodeproj \
  -scheme Rasc \
  -configuration Debug \
  -derivedDataPath "$TEST_DERIVED_DATA" \
  -destination 'platform=macOS,arch=arm64' \
  CODE_SIGN_STYLE=Manual \
  CODE_SIGN_IDENTITY=- \
  DEVELOPMENT_TEAM=
```

Expected: `Test run with 464 tests in 42 suites passed` and
`** TEST SUCCEEDED **`. `SparkleUpdaterConfigurationTests` covers the feed/key
validation.

## 9. Cleanup

```bash
# Stop the feed server (Ctrl-C in its terminal), then:
pkill -f "/Applications/Rasc.app/Contents/MacOS/Rasc" 2>/dev/null || true
rm -rf /Applications/Rasc.app

# Remove the test CA if it was trusted.
security delete-certificate -c "Rasc Sparkle Test CA" \
  "$HOME/Library/Keychains/login.keychain-db" 2>/dev/null || true

# Restore the default keychain search list if a test keychain was used.
security list-keychains -d user -s "$HOME/Library/Keychains/login.keychain-db"

# Remove all proof artifacts (gitignored).
rm -rf build/sparkle-proof build/sparkle-tools build/Sparkle-2.9.4.tar.xz
```

`build/` is gitignored. The proof key, DMGs, appcast, TLS keys, logs, and
evidence are never committed.

## What this proves

- Sparkle 2.9.4 can be vendored and weak-linked without affecting Debug builds.
- Release builds can embed, sign, and package Sparkle's nested XPC services,
  `Autoupdate`, `Updater.app`, and framework with ad-hoc signatures.
- The appcast generator produces valid Ed25519 signatures and lengths, and a
  one-byte tamper is rejected.
- The feed can be served over HTTPS with a test CA, and curl rejects it without
  that CA.
- The default Release does not embed Sparkle, launches normally, and cannot
  update itself.
- The weak link degrades gracefully instead of crashing when Library Validation
  rejects the framework.

## What this does not prove

- That Sparkle can load under the required App Sandbox + Hardened Runtime
  settings with ad-hoc signing. It cannot: Library Validation requires a
  shared Team ID.
- That an update can be downloaded, verified, extracted, installed, and
  relaunched in-app.
- That notes, preferences, and shortcuts survive an in-app update.
- That the feed is reachable from a clean Mac, or that Sparkle's own HTTPS
  stack trusts the test CA.
- That a browser-downloaded DMG installs without Gatekeeper intervention. The
  app remains ad-hoc signed and still requires **Open Anyway** on first launch.

The blocker and the recommended unblock (an Apple-issued Developer ID identity)
are documented in [../../docs/SPARKLE-UPDATES.md](../../docs/SPARKLE-UPDATES.md).
