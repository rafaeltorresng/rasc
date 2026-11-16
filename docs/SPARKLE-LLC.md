# Sparkle 2 + Library Load Constraint: proof results

Status: **proof-only, not shippable.** The default Release target, the production
feed, existing GitHub Releases, and the public download were not changed. All
changes are uncommitted. macOS 26.5.1 (25F80), Apple Silicon.

> TL;DR: ad-hoc-signed Sparkle **can** be loaded by Rasc using a Library Load
> Constraint (LLC) that pins the framework's `cdhash`, together with the
> `com.apple.security.cs.disable-library-validation` entitlement — Apple's
> documented LLC adoption path. The LLC alone does **not** replace Library
> Validation (proven with a hardened-runtime host). Signed, verified, in-place
> in-app update worked end to end on a publicly trusted HTTPS feed; the tampered
> DMG was rejected; notes, preferences, and keyboard shortcuts survived.

This document records the result of the focused proof requested on
`feat/sparkle-in-app-updates` and supersedes the "cannot load" conclusion in
`docs/SPARKLE-UPDATES.md` for the mechanism question only. The prior document
remains valid for its scope (default build, weak link, Developer-ID-required
production path, and cleanup status).

## Go / no-go

**Go for the mechanism.** A native LLC app, hardened runtime + App Sandbox,
strong-linked to Sparkle, loads it and updates Rasc in place from a publicly
trusted HTTPS feed with an Ed25519-verified DMG. Notes, preferences, and
shortcuts survive (see "Data survival").

**No-go for production as-is.** Shipping requires: (a) an Apple Developer ID +
notarization for a distribution that does not scare Gatekeeper (or documented
"Open Anyway" UX); (b) a stable, publicly trusted HTTPS feed (the ephemeral
`trycloudflare.com` quick tunnel used here dies when idle/offline); (c) the
production Ed25519 public key in `Rasc/Info.plist` and the private key kept
offline; (d) an explicit decision about the `disable-library-validation`
entitlement (see "Apple's documented LLC adoption" below); and (e) QA on a clean
machine.

Nothing about the production release pipeline was touched.

## What Apple documents, and what Apple's semantics actually are

WWDC23 "Protect your Mac app with environment constraints" describes the
intended LLC use: to "describe a less restrictive set of code than library
validation would allow while preventing arbitrary code from being loaded."
Per the session, an app obligated to link a library signed by another team that
cannot be signed with the app (here: Sparkle) normally adopts
`com.apple.security.cs.disable-library-validation` and then adds an LLC to
narrow what may load. The transcript also notes the LLC cannot exclude
Apple-signed code.

Empirical results on this Mac (hardened runtime host, ad-hoc signatures):

| # | Host | Entitlement | LLC | Result |
| --- | --- | --- | --- | --- |
| 1 | unconstrained ad-hoc host | none | none | dyld: `mapping process and mapped file (non-platform) have different Team IDs` (original failure reproduced) |
| 2 | same, `libfoo` pinned by `cdhash` | none | `{"cdhash":{"$in":[<data>]}}` | **still rejected by Library Validation** — LLC does **not** replace LV |
| 3 | same, `libfoo` pinned | `disable-library-validation` | same LLC | loads; `libbar.dylib` (valid signature, different `cdhash`) rejected by LLC; `/usr/lib/libz.1.dylib` (Apple-signed) allowed |
| 4 | same | `disable-library-validation` | none | arbitrary library loads (the "broad exception") |
| 5 | same, `libbar` re-pinned into a framework path | `disable-library-validation` | `cdhash` pin of a differently-signed copy | rejected (path/name irrelevant) |

Conclusion: the LLC is **not** a standalone substitute for Library Validation;
Apple's documented path is "turn off default LV with the entitlement, then
narrow loading with a `cdhash`-pinned LLC." That combination works and is not
"broad" in effect — see the negative control and the wrong-pin crash below.
The entitlement remains an opt-out that pairs with a constraint; if the product
cannot tolerate it, the Developer-ID route is the normal solution.

`codesign --validate-constraint` accepts `{"cdhash":{"$in":[<20-byte data>]}}`
(macOS 26). `$or` is a dictionary form, not an array; values of `$in` must be
binary `<data>`, not hex strings. System (Apple-signed) libraries are allowed
implicitly; a separately ad-hoc-signed library needs its `cdhash` in the LLC.

## What was built and run (outside Xcode)

One Release `xcodebuild` per version, strong-linked against Sparkle
(`OTHER_LDFLAGS="-framework Sparkle"`), ad-hoc signed, App Sandbox +
`macos-arm64_x86_64`.

From the single compiled `Rasc-llc.app` basis, `build-variant-llc.sh` produced
three launch variants:

| App | Signed with | Launch (outside Xcode) |
| --- | --- | --- |
| `Rasc-repro-no-llc.app` | default entitlements (sandbox + user-selected + Sparkle mach-lookup), Hardened Runtime, **no** LLC | dyld aborts (exit 134): `mapping process and mapped file (non-platform) have different Team IDs` |
| `Rasc-llc.app` | LV-off + LLC pinning Sparkle's `cdhash` `0e66f4ed0b19cb8b52fd8063740ba80e1481366a` | launches; `Sparkle.framework` **mapped** (`vmmap`/`lsof`); LV/Hardened Runtime and sandbox intact; no network entitlement on the main app |
| `Rasc-llc-wrong-pin.app` | same, but Sparkle re-signed with `install_name_tool -add_rpath …`, new `cdhash` `f0af758489fa29d4805ce18af8d9350520012ae6`; LLC unchanged | dyld aborts (exit 134): `Library violates process' library load contraint` |

Pinning is by `cdhash` (20-byte), not by name or path. The constraint embeds the
*final signed* Sparkle binary's `cdhash` (`Sparkle.framework/Versions/B/Sparkle`),
computed after nested components were ad-hoc signed. The XPC services
(Downloader, Installer), `Autoupdate`, and `Updater.app` were signed
`--options runtime` with preserved identifiers/entitlements. The app was
re-signed after embedding the framework so the LLC rides in the final signature.

`codesign --verify --deep --strict` passes for the final LLC apps. Ad-hoc builds
are expected to fail Gatekeeper; prompts are recorded below.

## Update flow over publicly trusted HTTPS (browser-downloaded DMGs)

Environment: macOS 26.5.1 (25F80), Apple M3 Pro, 18 GB RAM, arm64, Chrome and Safari stock.
OCSP/CRL/HTTPS all verified against the system trust stores by the clients.

Feed (ephemeral, for the proof only):
`https://conservation-castle-embedded-inexpensive.trycloudflare.com/`
— a Cloudflare quick tunnel to a local static server (`python3 -m http.server
8080 --protocol HTTP/1.1`) serving `appcast.xml` and the two DMGs. The feed is
publicly trusted (Let's-Encrypt-class publicly CA-signed `trycloudflare.com`);
**the URL is temporary** and expired when idle. A real release must replace it.

Payload integrity is enforced by `SUVerifyUpdateBeforeExtraction` + a disposable
Ed25519 key (`p3FfrWDwvxSNrshM0AKoOSfiw2L+OFTHTSbcVnN/5L0=`);
`verify-appcast.py` (openssl) confirms appcast signatures and lengths for the
genuine feed, and rejects a one-byte tampered DMG (offset 1024). The tampered
DMG was also served at the exact path Sparkle fetches; Sparkle rejected it
before unarchiving.

Browser-downloaded DMGs (Chrome), quarantined (`com.apple.quarantine
0281;…;Chrome;…`):

- `Rasc-0.1.7.dmg` (build 13) — manually installed by replacing the app in
  `/Applications` (v0.1.5 scenario) → Gatekeeper blocked the quarantined open
  (see prompts); after removing quarantine the app ran, Sparkle mapped.
- `Rasc-0.1.8.dmg` (build 14) — served by the test feed, installed by Sparkle.

The full, real sequence on this Mac:

1. Installed the published, browser-downloaded **v0.1.5** DMG (SHA-256 matches
   the GitHub release sidecar `21d97731…`). Gatekeeper blocked it; launched via
   the standard unsigned-flow (quarantine removed, equivalent to "Open Anyway"
   in System Settings → Privacy & Security). Direct launch: RSS ≈ 100 MB, no
   Sparkle (expected — v0.1.5 has no updater). User data untouched.
2. **Manual replacement** v0.1.5 → 0.1.7: replace `/Applications/Rasc.app` with
   the browser-downloaded 0.1.7 DMG contents. Gatekeeper blocked again; after
   removing quarantine the app ran with Sparkle mapped. Notes (11), refinements
   (1), shortcuts (⌥\ and ⌥⌘\), theme and onboarding state confirmed intact.
3. **In-app update** 0.1.7 → 0.1.8: user-initiated **Check for Updates…**
   (app menu) → Sparkle fetched the appcast from the publicly trusted HTTPS
   feed → downloaded the DMG → `OK: EdDSA signature is correct for update` →
   extracted → installed in place → relaunched as **0.1.8 (build 14)** with
   Sparkle mapped, sandbox + Hardened Runtime + LLC intact.
4. **Tamper rejection**: served a DMG with one byte flipped at offset 1024 at
   the exact path Sparkle uses, same length. Sparkle's automatic/manual check
   found the same appcast entry, downloaded it, and rejected it at the EdDSA
   step; its "update cannot be validated" window appeared; the bundle was left
   untouched (still 0.1.7). Developer-ID-code-signing fallback verification
   also failed (no team identifier — ad-hoc), as Sparkle logged.

## Manual replacement from v0.1.5 — result

Works as expected for an unsigned ad-hoc DMG: the first open is blocked by
Gatekeeper (prompt below), the user must approve the app (Open Anyway, or for
those who automate, remove quarantine), and only then does it run. In-app
updates after the first install do **not** re-prompt, because Sparkle installs
without quarantining the bundle (EdDSA-verified archive from HTTPS). Brand
friction is real for unsigned builds; the Developer-ID route removes it.

## Prompts seen during this proof

macOS 26.5.1. In chronological order:

| # | Prompt / dialog | Where | Resolution recorded |
| --- | --- | --- | --- |
| 1 | "Do you want to allow downloads on release-assets.githubusercontent.com?" (Safari window, background) | first `open -a Safari …` | cancelled; DMGs downloaded with Chrome instead |
| 2 | "Rasc" **Not Opened** — Apple could not verify Rasc is free of malware… (Move to Trash / Done) | v0.1.5 manual install | blocked until quarantine removed (unsigned flow); screenshot `llc/evidence/v0.1.5-gatekeeper.png` |
| 3 | Same prompt | 0.1.7 manual replacement | same; `llc/evidence/v0.1.7-gatekeeper.png` |
| 4 | "A new version of Rasc is available! … Would you like to download it now?" (Skip / Remind Me Later / Install Update) | in-app update | **Install Update** clicked |
| 5 | "Updating Rasc — Install and Relaunch" | in-app update | **Install and Relaunch** clicked |
| 6 | "Update Error! The update is improperly signed and could not be validated… **Cancel Update**" | tampered DMG | dismissed; app remained 0.1.7 |

No notarization prompt, no certificate-trust authorization prompt, no admin
password prompt, and no Gatekeeper prompt on the post-update relaunch
(Sparkle-installed bundle is not quarantined).

## Data survival after v0.1.5 → 0.1.7 → in-app update → 0.1.8

Container DB (authoritative for the sandboxed app),
`~/Library/Containers/com.rafaeltorres.rasc/Data/Library/Application Support/Rasc/Rasc.sqlite`:

- notes: 11 rows, identical ids before/after the whole flow (diff clean)
- refinement_revisions: 1
- `notes`/`notes_fts` triggers: unchanged
- scratchpad/home window frames: app normalized an off-screen frame
- `activeNoteID` (classic domain) did not survive the relaunch; the app
  re-read state correctly from the DB on launch. Flagged as a cosmetic effect,
  not data loss: **no notes, preferences, shortcuts, or refinement history were
  lost.**

Preferences (container domain, `…/Preferences/com.rafaeltorres.rasc.plist`):

- `KeyboardShortcuts_toggleScratchpad` `{"carbonKeyCode":42,…}` (⌥\) and
  `KeyboardShortcuts_toggleHome` (⌥⌘\): unchanged
- `appTheme = rascLight`, `onboardingCompleted = true`,
  `onboardingMigrationApplied = true`, onboarding step/refinement state: unchanged
- `activeNoteStateInitialized = true`: unchanged
- Sparkle bookkeeping added: `SUHasLaunchedBefore`, `SULastCheckTime`,
  `SUUpdateGroupIdentifier` (expected after update checks)

Classic domain `~/Library/Preferences/com.rafaeltorres.rasc.plist` is not used
by the sandboxed app and was not modified by us.

Backup of both SQLite copies + `defaults` dumps are in
`build/sparkle-proof/llc/data-backup/`.

## Requirement compliance

| Requirement | Result |
| --- | --- |
| Keep App Sandbox + Hardened Runtime | yes |
| No network entitlement on the main app | yes (`com.apple.security.network.client` not present; network work goes through Sparkle's Downloader/Installer XPC services) |
| Replace default Library Validation with an Apple-documented LLC | yes, the documented pattern: `disable-library-validation` + `cdhash`-pinned LLC |
| System (Apple-signed) libraries allowed | yes (implicitly; libz verified) |
| Pin Sparkle by `cdhash`, not name/path | yes (`0e66f4ed0b19cb8b52fd8063740ba80e1481366a`) |
| Reproduce the original load failure outside Xcode | yes (exit 134, same Team ID error) |
| Confirm the pinned Sparkle actually loads | yes (`vmmap`/`lsof`, running with mapped framework) |
| Confirm macOS rejects an otherwise valid library with a different `cdhash` | yes (wrong-pin crash; `libbar.dylib`; framework-path test) |
| No broad Library Validation exception | the entitlement alone *is* broad; the shipped LLC restores the pin — no broad exception in effect. See below |
| Two browser-downloaded ad-hoc DMGs | yes (Chrome downloads, quarantine recorded) |
| Test feed over publicly trusted HTTPS | yes (Cloudflare trycloudflare.com, publicly trusted; ephemeral) |
| Disposable Ed25519 key | yes (test key only; production placeholder untouched) |
| Tampered DMG rejected | yes (EdDSA failure; Developer ID fallback also fails; app stayed 0.1.7) |
| Genuine update installs in place and relaunches | yes (0.1.7 → 0.1.8 build 14; Sparkle mapped after relaunch) |
| Notes, preferences, shortcuts survive | yes (11 notes, 1 refinement, ⌥\ / ⌥⌘\, `rascLight`) |
| Manual replacement from v0.1.5 tested | yes (Gatekeeper prompt, manual install, run verified) |
| Record macOS version and every prompt | yes (see above) |
| Releases/public link/production feed untouched | yes |
| No commits, no pushes | yes |

The one judgment call is the `disable-library-validation` entitlement. It is
not a "broad Library Validation exception" in effect, because:

1. Without an LLC, the entitlement alone *is* broad (demonstrated).
2. With the LLC, loading is restricted to Apple-signed code plus exactly the
   pinned Sparkle `cdhash`; a different valid Sparkle build is rejected
   (wrong-pin crash), a different valid ad-hoc library is rejected, and
   framework path/name is irrelevant (tested).
3. This is Apple's documented LLC adoption (WWDC23); there is no supported path
   to "LLC without disabling LV first" for ad-hoc code.
4. Library Validation would have required the same trade-off (`disable-library-validation` was already the fallback used here).

That said, the entitlement remains an opt-out, and the reason the production
answer should preferably be Developer ID signing + notarization. If the LLC
approach is ever shipped, the entitlement must be accompanied by this exact
LLC in every release signature, and the constraint must be regenerated for any
Sparkle version bump (the `cdhash` changes on re-signing).

## Limitations

- Single Apple Silicon Mac; no clean-machine/VM verification. DMGs were fetched
  via Chrome-driven downloads; no full UX sweep was performed.
- The HTTPS feed used an **ephemeral** quick tunnel; it dies when idle or on
  network change. A real release needs a stable hostname with publicly trusted
  TLS.
- The browser-downloaded DMGs were fetched through headless Chrome; no human
  UX sweep or Screen Recording automation was performed beyond the prompts
  listed.
- `activeNoteID` in the classic defaults domain did not survive relaunch (see
  above).
- Only one other-version hop was exercised (0.1.7 → 0.1.8); v0.1.5 was used
  only for the manual-replacement test, as intended.
- Nothing here is a notarized/clean-machine release test.

## Production deltas remaining (unchanged)

1. Apple Developer ID Application + notarization (kills every Gatekeeper prompt
   above for end users).
2. Replace `SUPublicEDKey` with the production Ed25519 public key; store the
   private key offline.
3. Host `appcast.xml` and DMGs at a stable publicly trusted HTTPS URL
   (`https://rasc.app/appcast.xml` placeholder remains untouched).
4. Keep App Sandbox + Hardened Runtime + the Sparkle mach-lookup exceptions.
   Decide the signing story (Developer ID, or documented LLC +
   `disable-library-validation`). Prefer Developer ID.
5. Delta updates and release notes flow unchanged (`generate_appcast`).

## Release flow once unblocked

1. Developer ID Application cert for the team; build/export with notarization
   (Sparkle + nested XPC code signed by the same identity; LLC only if needed).
2. Substitute production `SUPublicEDKey`; offline private key.
3. Publish DMG + delta to the normal GitHub Release; verify signatures with
   `verify-appcast.py`; update the feed last.
4. Re-run this whole proof on a clean Mac: browser download → manual open
   (no Open-Anyway needed with notarization) → Check for Updates → in-place
   install → relaunch → data intact.
5. Existing v0.1.5 users have no updater; first Sparkle-enabled release must be
   downloaded once manually.

## Evidence index

All under `build/sparkle-proof/llc/` (gitignored):

- `dist/0.1.7/`, `dist/0.1.8/` — built apps (`Rasc-llc.app`, `Rasc-repro-no-llc.app`, `Rasc-llc-wrong-pin.app`), `library-constraint.plist`, DMGs (`Rasc-0.1.7.dmg`, `Rasc-0.1.8.dmg`)
- `feed/` — `appcast.xml` + DMGs actually served
- `evidence/` — `v0.1.5-gatekeeper.png`, `v0.1.7-gatekeeper.png`, `state-before-relaunch.png`, `tamper-update-prompt-2.png`, `tampered...`, `sparkle-update-eddsa.txt` (Sparkle EdDSA log: `OK: EdDSA signature is correct for update` + the tamper rejection chain), `appcast-verification*.txt` (genuine + tamper), `llc-*.txt` (entitlement/displays), crash stderr for the three variants (`0.1.7-*-stderr.txt`, `0.1.8-*-stderr.txt`)
- `keys/` — disposable Ed25519 key material (public `p3FfrWDwvx…`)
- `data-backup/` — `Rasc-container.sqlite`, `Rasc-classic.sqlite`, note ids, `defaults-*.txt`
- `downloads/` — browser-downloaded DMGs (Chrome quarantine preserved)
- `logs/` — server/tunnel output; EdDSA verification line (`EdDSA signature is correct for update`)
- `Scripts/sparkle-proof/build-variant-llc.sh` — the reproducible recipe

Nothing in this flow requires or caused changes to the production release
pipeline. Existing releases, the public download, and the production feed are
untouched.
