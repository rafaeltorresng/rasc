# Rasc Product Readiness & Competitive Quality Audit · 26–27 November 2026

**Target codebase:** `main` consolidated through `30c5c14` (PRs `#106`–`#113`, `0.1.16 build 22`, macOS deployment target `14.0`).
**Published/retained baseline:** `v0.1.15 build 21` (separate ad-hoc signed DMG); **verified final local RC:** `build/updater-rc/0.1.16-final-rc` (`0.1.16 build 22`, SHA-256 `208d426e4448c6de918b712e7947a84a6631cb7954a1b9055ac76c188a8c839f`).
**Test & measurement host:** MacBook Pro `Mac15,6` (Apple M3 Pro, 18 GiB RAM), macOS `26.5.1` (`25F80`), Xcode `26.2` (`17C52`), GitHub Actions `macos-26` CI runner.
**Live multi-hour efficiency run:** `build/efficiency-long-running/20261126-191517-full-32h` (Stage 1 completed `8.00 h`; Stage 2 captured `8.50 h` of `24.0 h` before host stop; folder preserved untouched).
**Web handoff package:** [`docs/evidence/HANDOFF.md`](../evidence/HANDOFF.md) & [`docs/evidence/EDITORIAL-BRIEF.md`](../evidence/EDITORIAL-BRIEF.md).

---

## 1. Consolidated Changes (PRs #106 – #111)

| PR / Branch | Commit | Focus & Key Changes | Automated Verification |
|---|---|---|---|
| **#106** | `30090a6` | Redesigned first-run onboarding (`OnboardingFocus`, 2-beat capture/resume/Keep exercise, non-blocking async speech model setup via `enableAndDownloadIfMissing()`, contextual Mic & AX prompts, inline *"Try Dictate here"*, non-destructive `replayOnboarding()`, closed Issue `#80`). | Domain & native suite + isolated Release container checks (`onboardingtest`). |
| **#107** | `c2320a1` | Release efficiency optimization: `LazyVStack` in Home (`home_open` `600.17 ms → 4.26 ms`), deferred `2.0 s` Home teardown + memory-pressure eviction (`home_close` `5.77 ms` p50), candidate-only scroll monitoring (`ModifierShortcutMonitor`), hidden `PanelController` short-circuits, `MicBuffer` compaction, `n=3` Release replications, Sparkle LLC audit, and `run_long_running.py`. | `n=3` Release suite (`replications.json`), `leaks` (`0` Rasc leaks), `soak-8h` & `idle-24h-voice-on` smokes, CI `macos` passed. |
| **#108** | `8526a7a` | Scoped `RASC_APP_ENTITLEMENTS` and `RASC_APP_BUNDLE_IDENTIFIER` to the `Rasc` app target so `Scripts/test-native.sh` no longer breaks `VoiceModelDownloader.xpc` copy; fixed `PanelControllerTests` occlusion/palette isolation and `HomeWindowController.defaultObservers` Sendability; blocked Scratchpad text editing (`isEditable`) during Refine/preview. | `python3 Scripts/test-domain.py` (`588` tests / `48` suites + `AppReliabilityScaleTests`), `bash Scripts/test-native.sh` (`116` tests / `16` suites), CI `macos` passed. |
| **#109** | `3205cd1` | Voice Capture & Dictate hardening: `VoiceTranscriptSanitizer.clean`, lazy 5 s-chunked `300 s` `MicBuffer` + USB multi-channel `vDSP.maximumMagnitude` selection + `15 s` warning countdown, `5.5 s` HAL startup watchdog, dynamic `transcriptionTimeoutSeconds`, Secure Input refusal (`IsSecureEventInputEnabled()` + `AXSecureTextField`), Electron `AXManualAccessibility` wake-up, `textWithSmartLeadingSpace`, frontmost-Rasc isolation, `.screenSaver` HUD level, `"Allow…"` Accessibility button, and `Esc` dismissal on `.copiedFallback`. | `python3 Scripts/test-domain.py` (`594` tests / `48` suites + `AppReliabilityScaleTests`), `bash Scripts/test-native.sh` (`116` tests / `16` suites), CI `macos` passed. |
| **#110** | `ca9c93f` | SQLite WAL + `synchronous = NORMAL` + `5.0 s` busy timeout, fail-closed `PRAGMA quick_check(1)` & newer-schema `AppDatabaseError` refusal (never deleting user data), `v11_scale_indexes_and_origin` (partial scale indexes + `Note.Origin` `.scratch`/`.dictation`), `7`-day launch purge of expired discarded notes & `refinement_revisions`, `maxDiscardReceipts = 50` undo cap, sandbox-safe `NoteRepository.backup(to:)` (**Settings → General → Back Up Database…**), 3-button launch recovery alert (**Retry / Reveal Data Folder / Quit Rasc**) + menu-bar retry, Home `> 10` batch-discard confirmation, export smart defaults + `150 ms` search debounce, `-0.15` Kept FTS5 tie-breaker, termination WAL truncate checkpoint. | `python3 Scripts/test-domain.py` (`602` tests / `48` suites + `AppReliabilityScaleTests`), `bash Scripts/test-native.sh` (`116` tests / `16` suites), CI `macos` passed. |
| **#111** | `578d02a` | Inside-out release signing (`sign_app_inside_out`), `build-updater-rc.sh` `RASC_APP_ENTITLEMENTS` scoping + dynamic LLC pinning across **all** `Contents/Frameworks/` `.framework` binaries and `*.dylib` (`Sparkle` + `libswiftCompatibilitySpan.dylib`), `verify-appcast.py` OpenSSL 3 resolver, and canonical docs sync. | `bash -n`, `py_compile`, `verify-appcast.py` (`OpenSSL 3.6.3`), LLC 2-slice pin verification, CI `macos` passed. |
| **#112** | `67283b5` | Read-only analysis of `20261126-191517-full-32h` (`8.00 h` soak + `8.50 h` idle), Release `1k/5k` scale benchmark, Round 5 paired Voice competitive benchmarks (`VoiceArena n=151`, `Round 3 Held n=168`, `FLEURS n=60`, `30s–300s` + `-20 dBFS`), and live `SystemLanguageModel.default` Refine validation (`Validation 57`, `Holdout 72`, `Regression 6`, `PT/Mixed 16`, `Synthetic 8`). | Release `RascBench`, live `SystemLanguageModel.default`, CI `macos` passed. |
| **#113** | `30c5c14` | Stage 4 streaming `15 s` `AVAudioConverter` resampling in `VoiceAudio.mono16k()`, `VoiceAudioPipelineTests`, `v10 → v11` direct migration + backup/restore round-trip tests, and expanded `HomeSnapshotTests` across Light/Dark (`72` snapshots rendered, `38` curated views audited in [`docs/evidence/screenshots/`](../evidence/screenshots/manifest.json)). | `608` domain tests / `49` suites + `AppReliabilityScaleTests`, `116` native tests / `16` suites, CI `macos` passed. |
| **Stage 5** | `docs/final-readiness-rc-and-web-handoff` | Final `0.1.16-final-rc` DMG + Ed25519 appcast + `Rasc22-21.delta` + isolated `0.1.15 → 0.1.16` container upgrade (`com.rafaeltorres.rasc.rcverify`), updated Release `scale_1k_5k_final` + `300 s @ 48 kHz` streaming `mono16k()` (`21.66 ms`), and definitive `docs/evidence/` + docs reconciliation. | `verify-rc-bundle.sh`, `codesign --verify --deep --strict`, `verify-appcast.py --tamper`, SQLite upgrade `integrity_check = ok`, Release `RascBench`, personal DB SHA-256 unchanged. |

---

## 2. Empirical Baseline & Competitive Context

### 2.1 Release Resource Efficiency (`EVERYDAY-EFFICIENCY.md`, `Mac15,6` M3 Pro 18 GiB, macOS `26.5.1`)
- **Standby footprint (`n=3` Release medians, unlocked desktop):**
  - Voice disabled (`90 s`): **`24.49 MiB`** p50 `phys_footprint`, **`0.0024%`** CPU, **`0.000/s`** pkg idle wakeups, `0.01 mW` XNU CPU power.
  - Voice enabled & prepared (`90 s`): **`50.17 MiB`** p50 `phys_footprint` (`11.81 MiB` steady / `598.44 MiB` lifetime-peak `neural_footprint`), **`0.0017%`** CPU, **`0.000/s`** pkg idle wakeups, `0.00 mW` XNU CPU power.
- **Workday & responsiveness (`n=3` medians vs `1cee496`):**
  - `home_open`: `600.17 ms` → **`4.26 ms`** (`141×` faster); `home_search`: `162.97 ms` → **`11.56 ms`** (`14.1×` faster); `home_close`: **`5.77 ms`** (eliminated `396.37 ms` teardown stall).
  - Workday peak footprint: `294.99 MiB` → **`143.16 MiB`** (`−51.5%`); post-cooldown footprint: `189.22 MiB` → **`63.70 MiB`** (`−66.3%`); cumulative CPU time `−70.8%`; XNU CPU energy `−74.7%`; **`0`** Rasc-owned leaks.
- **Distribution separation:** Standard Release `.app` is **`40.54 MiB`**; Sparkle LLC `.app` is **`44.40 MiB`**; `Fluid Speech Pro` Core ML pack (`652,304,885 B` / `622.09 MiB`) is excluded from `.app` and fetched once via isolated `VoiceModelDownloader.xpc`.

### 2.2 Voice Recognition & Competitive Positioning (`Round4` + `COMPETITIVE-EVALUATION.md`)
- **Verbatim WER (real human read speech, `Round4`, FLEURS-EN-30 + PT-30, warm app code):** **`5.354%`** pooled verbatim WER (`EN 6.122%` / `PT-BR 4.581%`; `8.884%` punctuation-sensitive; `0` empty transcripts); perturbations vs `6.383%` base: pauses `5.674%`, `+15 dB` pink noise `8.511%`, speed `±25/20%` `7.447%`.
- **Conversational (`Round3`, same pinned `Fluid Speech Pro` model):** `13.00%` EN meeting, `21.82%` PT conversation, `8.89%` mixed PT-EN (`4` empty PT transcripts in Round 3).
- **Warm app-code latency (`Round4`, `n=60`):** `55.75 ms` p50 / `107.85 ms` p95 inference; `69.90 ms` p50 / `126.34 ms` p95 transcribe-total (`RTF 0.005` p50). Cold `model.prepare()` reached `11.34 s` initial (`fleurs-60`) / `11.96 s` (`rep_1`) vs `~0.04–0.11 s` warm cache.
- **Architectural differentiation vs Wispr Flow, Superwhisper, Aqua Voice, Typeless, Monologue, Handy, VoiceInk, FluidVoice, and Apple Dictation:**
  - Rasc shares `FluidAudio` / `Fluid Speech Pro` with FluidVoice and remains strictly offline/no-telemetry/no-account/no-synthetic-keystrokes (`AXSelectedText` + clipboard fallback), whereas cloud/hybrid competitors (Wispr Flow, Monologue/Superwhisper formatting modes) optimize **Zero Edit Rate (ZER)** via LLM formatting/glossaries at the cost of network egress or heavier multi-model memory. Verbatim WER cannot be conflated numerically with ZER/AMEND.

### 2.3 Release Packaging & LLC Smoke Verification (`/tmp/rasc-llc-verify`, deleted after inspection)
- `RASC_RC_OUTPUT_DIR=/tmp/rasc-llc-verify RASC_RC_ED25519_ENFORCE=0 bash Scripts/release/build-updater-rc.sh` built `0.1.16 (build 22)` (`arm64`), verified cleanly with `verify-rc-bundle.sh`, and discovered **both** embedded Mach-O slices under `Contents/Frameworks/`:
  - `Sparkle.framework/Versions/Current/Sparkle [arm64]`: `0e66f4ed0b19cb8b52fd8063740ba80e1481366a`
  - `libswiftCompatibilitySpan.dylib [arm64]`: `c3228a12b0782b9b402391c99f9627f4c9e2456b` *(previously omitted when LLC only pinned `Sparkle`)*
- Post-sign inspection confirmed `Has Library Load Constraints`, `codesign --verify --deep --strict`, main app free of `network.client`, and `VoiceModelDownloader.xpc` carrying solely `com.apple.security.app-sandbox` and `com.apple.security.network.client`.

---

## 3. Verified Automated Checks vs Pending Physical Desktop Gates

| Area | Verified (Automated / Isolated CLI / CI) | Pending Physical / Clean-Machine / Signing Verification |
|---|---|---|
| **Core Scratchpad, Panels, Home, Search, Export, Onboarding** | `602` domain tests / `48` suites + `AppReliabilityScaleTests`; `116` AppKit tests / `16` suites on unlocked local macOS and GitHub Actions `macos-26`; Settings/Home/Onboarding Light & Dark sizing/snapshot checks; SQLite WAL, `v11`, purge, backup, fail-closed recovery. | Full **VoiceOver** screen-reader traversal, **Full Keyboard Access** tab flow, multi-display / fullscreen **macOS Spaces** / Stage Manager focus transitions across third-party apps. |
| **Voice Capture & Dictate (`300 s`, AX, Secure Input)** | `MicBuffer` chunking, USB channel selection, `VoiceTranscriptSanitizer`, timeout math, `IsSecureEventInputEnabled` & `AXSecureTextField` guards, `textWithSmartLeadingSpace`, frontmost-Rasc editor fallback, `Esc` armed on `.copiedFallback` tested via fixtures/unit tests. | Real physical microphone & **Bluetooth** HFP/A2DP route switches during **5-minute** speech, live OS TCC prompts (**Microphone** & **Accessibility**), live modifier-only physical taps, external-app `AXSelectedText` matrix (Chrome/Electron/Slack/Notes/IDEs) & OS password-field Secure Input tests. |
| **Release, Distribution & Sparkle Updates** | `build-updater-rc.sh` isolated LLC smoke (`Sparkle` + `libswiftCompatibilitySpan.dylib`), `verify-rc-bundle.sh`, `VoiceModelDownloader.xpc` entitlements, OpenSSL 3 resolver (`OpenSSL 3.6.3`). | **Developer ID Application** signing + Apple **notarization** (`spctl --assess`), clean-machine DMG install without Xcode, **macOS 14 / 15** host execution (especially weak-linked `libswiftCompatibilitySpan.dylib` + Liquid Glass fallback), genuine Sparkle update verifying TCC microphone permission continuity ([Apple TN3127](https://developer.apple.com/documentation/technotes/tn3127-inside-code-signing-requirements)). |

---

## 4. Multi-Hour Efficiency Run Summary (`20261126-191517-full-32h`)

Preserved untouched (`Experiments/Efficiency/results/long_running_20261126/REPORT.md`, `personal_db_checks.unchanged = true`):

- **Stage 1 Active Soak (`completed`, `8.00 h` / `28,801.45 s` wall, `15,594.13 s` active, `15` macOS sleeps):** `3,112` samples, `32` cycles, `260` notes, `32` Refine calls, `7` sleep/wake probes; `phys_footprint` **`73.70 MiB`** p50 / **`73.77 MiB`** end (`125.99 MiB` max); `neural_footprint` `11.81 MiB` p50 (`598.44 MiB` peak); **`0.0295%` p50 CPU** (`0.9485%` mean), **`0.0/s` p50 wakeups**, `471.5331 J` XNU CPU energy, FDs `58–62`, **`0` Rasc leaks** (`288` Apple `LNDaemonApplicationInterface` XPC nodes constant).
- **Stage 2 Voice-On Idle Standby (`interrupted_at_8.50h` of `24.0 h`, stopped `2026-11-27T11:46:05-0300` — not extrapolated beyond `8.50 h`):** `2,041` samples across `30,611.08 s`; `phys_footprint` dropped from `61.88 → 30.94 MiB` end (**`33.66 MiB` p50**, `−1.0611 MiB/h` slope), `neural_footprint` flat `11.81 MiB`, **`0.0%` p50 CPU** (`0.0048%` mean, `1,461.2 ms` total), **`0.0/s` p50 wakeups** (`7` total in `8.50 h`), `1.9586 J` (`0.06 mW` mean), FDs `47 → 46`, **`0` Rasc leaks**.

Also verified in Stage 5 on `30c5c14`: Release `scale_1k_5k_final.json` (`5,000` notes, `fetchMostRecent 0.041 ms`, `search(20) 4.48 ms`, `backup 6.24 ms`), streaming `VoiceAudio.mono16k()` (`300 s @ 48 kHz` `4.8M/4.8M` frames in `21.66 ms`), and isolated `0.1.15 → 0.1.16-final-rc` upgrade (`com.rafaeltorres.rasc.rcverify`, `PRAGMA integrity_check = ok`, `v11` applied, 15s standby `31 MB` / `0.0%` CPU).

---

## 5. Strategic Decision Memos (Not Implemented)

### Option A — Local Personal Vocabulary / Custom Glossary
- **Problem:** Round 3 observed proper-noun and technical-term misses (`Supabase`, `Jakarta`, domain identifiers) because `Fluid Speech Pro` runs without custom vocabulary rescoring.
- **Options & Trade-offs:**
  - *Status quo:* Zero Settings complexity, zero risk of phonetic over-biasing false positives; technical edits remain explicit or handled via optional Refine.
  - *Post-ASR / Rescoring local glossary:* Improves recurring project/people names offline, but adds Settings management UI, export/backup expectations, and potential false triggers on short homophones.
- **Recommendation:** Keep out of `v0.1.16`. Evaluate post-release only with a paired human technical/PT-EN benchmark proving net edit-distance improvement without clean-speech WER regression.

### Option B — Optional Formatted / "Refine on Dictate" Mode
- **Problem:** Voice Arena ZER benchmarks penalize verbatim dictation relative to formatted tools (Wispr Flow, Monologue, Superwhisper), where fillers and self-corrections are rewritten automatically.
- **Options & Trade-offs:**
  - *Status quo (verbatim + `VoiceTranscriptSanitizer` + explicit Scratchpad Refine):* Preserves Rasc's core invariant (*Refine is explicit, conservative, and reversible; never rewrite meaning silently before inspection*), keeps median Dictate finish-to-insert latency at `~70 ms`, and requires no Apple Intelligence availability for Dictate.
  - *Auto-formatted Dictate via Foundation Models:* Adds `~1.09 s` p50 (`3.06 s` p95) per dictation on top of transcription, fails or drops on Macs without Apple Intelligence enabled, and risks silent meaning/negation distortion in external apps without Scratchpad's `Changes`/`Original` diff.
- **Recommendation:** Do **not** run automatic LLM rewriting in Dictate. Keep deterministic `VoiceTranscriptSanitizer` improvements only; consider a purely opt-in formatting preference only if future Apple Foundation Models latency and paired edit-time studies justify an explicit diff/undo story.

### Option C — Keeping vs Relaxing App Sandbox (Synthetic Keystrokes)
- **Problem:** Direct `AXSelectedText` insertion depends on target apps implementing Cocoa/Electron Accessibility cleanly (whereas `CGEvent` synthetic keystrokes work even in non-accessible custom views, albeit at the cost of App Sandbox).
- **Trade-offs:**
  - *Keep App Sandbox (`Rasc.entitlements` / `Rasc.sparkle.entitlements` + isolated `VoiceModelDownloader.xpc`):* Cryptographically guarantees the main app has no network egress (`EPERM` verified), confines downloaded binaries to the XPC helper, maintains OS container boundary, and aligns cleanly with Electron `AXManualAccessibility` wake-up + `.copiedFallback` (`⌘V`) UX.
  - *Drop App Sandbox for `CGEvent` keystrokes:* Enables keystroke synthesis in stubborn apps, but removes Rasc's strongest local-first privacy guarantee, still hits `IsSecureEventInputEnabled()` blocks on password fields, and degrades security posture on enterprise/Developer ID review.
- **Recommendation:** **Keep App Sandbox permanently.** Continue strengthening `AXSelectedText` compatibility (as shipped for Electron) and crisp `.copiedFallback` feedback.

### Option D — Apple Developer Program (Developer ID + Notarization) Before Public Launch
- **Current state:** `v0.1.15` shipped as an ad-hoc unnotarized DMG relying on macOS **Open Anyway** and an LLC workaround (`disable-library-validation` + per-slice `cdhash` pinning in `library-constraint.plist`).
- **Evidence:** Ad-hoc builds fail macOS `spctl --assess` Gatekeeper verification out of the box and reset **Microphone** TCC permission across Sparkle in-place updates because ad-hoc designated requirements do not preserve publisher identity ([Apple TN3127](https://developer.apple.com/documentation/technotes/tn3127-inside-code-signing-requirements)).
- **Recommendation:** Treat **Developer ID Application signing + Apple notarization (`notarytool` / `stapler`)** as a top launch priority before broad public marketing and final landing-page launch (`rasc-web`). Keeping LLC pinning intact alongside Developer ID provides defense-in-depth while eliminating `"Open Anyway"` conversion drop-off and fixing Sparkle TCC continuity.
