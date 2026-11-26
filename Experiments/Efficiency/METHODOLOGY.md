# Measurement Methodology & Metric Definitions

## 1. Test Environment

- **Hardware:** `Mac15,6` — Apple M3 Pro (11 CPU cores: 5 performance + 6 efficiency), 18 GiB unified memory (`19,327,352,832` bytes).
- **OS & Toolchain:** macOS `26.5.1` (`25F80`), Xcode `26.2` (`17C52`), Release (`-O`) arm64 builds.
- **Session state recording:** `detect_screen_locked()` queries `CGSessionCopyCurrentDictionary()["CGSSessionScreenIsLocked"]` (`screen_locked: false` recorded during the `n=3` optimized replications, Sparkle + LLC audit, and long-running smoke validations).
- **Sandboxing & Isolation:**
  - Standard builds clone Release `Rasc.app`, set `CFBundleIdentifier` to an isolated ID (`com.rafaeltorres.rasc.efficiency` or `com.rafaeltorres.rasc.longrun`), and ad-hoc sign with `--options runtime --entitlements Rasc/Rasc.entitlements --generate-entitlement-der`.
  - Sparkle distribution builds use `Rasc/Rasc.sparkle.entitlements`, re-sign `VoiceModelDownloader.xpc` with `VoiceModelDownloader/VoiceModelDownloader.entitlements`, embed `Sparkle.framework`, inject `SUPublicEDKey` via `build/sparkle-tools/bin/generate_keys -p --account rasc-sparkle`, and pin the `arm64` Sparkle framework `CDHash` in `--library-constraint` (never overwriting retained artifacts under `build/updater-rc/`).
  - Pre-existing personal databases (`~/Library/Application Support/Rasc/Rasc.sqlite` and `~/Library/Containers/com.rafaeltorres.rasc/Data/Library/Application Support/Rasc/Rasc.sqlite`) are `stat`-verified (`mtime_ns`, `size`) before and after every run.
  - Speech test clips come strictly from CC-BY-4.0 Google FLEURS examples (`Experiments/VoiceCapture/Round4/examples/`) staged inside the isolated sandbox container.

## 2. Workloads & Binary Configurations

1. **Unmodified Shipping Release Binary (zero benchmark code compiled in):**
   - Measures shipping bundle size (`du -sk` + recursive file sum), `n=5` cold launches (`10 Hz` sampling for `8 s`), `90 s` Idle Voice Off (`1 Hz`), `90 s` Idle Voice On after `30 s` Core ML preparation settle (`1 Hz`), `45 s` Idle with single-modifier shortcut (`Option`) active (`1 Hz`), and the `24h` Voice-On idle stage (`idle-24h-voice-on` / `full-32h`) in `run_long_running.py`.
   - UserDefaults flags (`-onboardingCompleted YES`, `-voiceCaptureEnabled YES/NO`, `-globalShortcutModifier.voiceScratchpad option`) use Apple's `NSArgumentDomain` so there are zero `cfprefsd` cache races across runs.
2. **Accelerated Workday Driver (`--run-efficiency-bench` under `#if RASC_EFFICIENCY_BENCHMARK`):**
   - Exercises real `NoteRepository` (SQLite + FTS5), `PanelController`, `ScratchpadSession`, `HomeWindowController`, `HomeSession`, `VoiceModel`, `VoiceTextInsertion`, `FoundationModelsRefinementProvider`, `VoiceCapture.shared` sleep/wake/pressure handlers, and `ModifierShortcutMonitor` across an 8-phase (`~4 min`) sequence ending in a `60 s` cooldown and `leaks`/`footprint`/`vmmap`/`lsof` diagnostics.
   - Executed across `n=3` independent replications (`rep_1..rep_3` with median, min, max, and IQR in `results/optimized/replications.json`).
3. **Long-Running Soak Driver (`--run-soak-bench` under `#if RASC_EFFICIENCY_BENCHMARK` + `run_long_running.py`):**
   - Alternates quiet standby (Voice enabled) with realistic active bursts (Scratchpad capture, Home open/search/batch/close + `3.5 s` check confirming deferred teardown after `2.0 s`, Voice Capture & Dictate on FLEURS WAVs, Refine when available, and periodic sleep/wake resource-constraint cycles), flushing line-by-line CSV + `partial_summary.json` and trapping `SIGTERM`/`SIGINT` cleanly for safe interruption.
   - Distinct from the accelerated `~4 min` suite: short smoke tests validate mechanism, streaming persistence, and signal-safe teardown; multi-hour `8h` soak and `24h` Voice-On idle claims require the completed full-duration run.

## 3. Metric Definitions (Never Conflate)

| Metric | Source | What it actually measures |
|---|---|---|
| **App bundle size** | `du -sk Rasc.app` + recursive file sum | On-disk size of `Rasc.app`: `40.54 MiB` standard local Release vs `44.40 MiB` with embedded Sparkle + LLC. |
| **Speech model on disk** | Verified `VoiceModels/<rev>/` | Separate opt-in one-time download (`652,304,885` bytes / `622.09 MiB`), never bundled inside `.app`. |
| **Physical memory (`phys_footprint`)** | XNU `proc_pid_rusage(..., RUSAGE_INFO_V6).ri_phys_footprint` & `/usr/bin/footprint` | Apple's Jetsam/dirty+compressed memory charged to the app. Reported instead of RSS as real RAM cost. |
| **RSS (`ri_resident_size`)** | XNU `proc_pid_rusage` | Includes shared `dyld` libraries, read-only frameworks, and mapped files. Much larger than `phys_footprint`; always labeled separately. |
| **Neural footprint (`ri_neural_footprint`)** | XNU `proc_pid_rusage` / `footprint` auxiliary data | Apple Neural Engine / unmapped Core ML weight residency reported by XNU (`11.81 MiB` steady warm, `598.44 MiB` lifetime peak). |
| **CPU % & Cumulative CPU ms** | Delta `(ri_user_time + ri_system_time) * numer / denom` | Scaled via `mach_timebase_info()` (`125/3 ns` per tick on Apple silicon). |
| **Wakeups (`/s`)** | `ri_pkg_idle_wkups` & `ri_interrupt_wkups` | Hardware package idle wakeups and process interrupt wakeups reported by XNU. |
| **Memory slope & recovery** | OLS across `elapsed_s` + `end - peak` | Tracks multi-hour drift (`MiB/h`) and post-peak cooldown reclamation (`recovery_delta_mib`). |
| **Wall sleep gap** | `(wall_dt - mono_dt)` when `> max(5s, 3*interval)` | Detects macOS sleep intervals (`time.monotonic()` freezes during system sleep while `time.time()` advances). |
| **XNU CPU energy (`J`, `mW`)** | `ri_energy_nj` | Per-process **CPU task energy** estimated by XNU. **Not** whole-SoC wall power, GPU/ANE/display rail power, or battery hours. |

## 4. Known Measurement & Sandbox Limitations

- **Full-SoC wall power / thermal / battery hours:** `sudo powermetrics` requires interactive root credentials (`sudo -n` unavailable), and `xctrace record --template 'Power Profiler'` is unsupported on macOS. Only XNU per-process CPU energy (`ri_energy_nj`) and wakeup rates are reported.
- **Synthetic vs physical desktop inputs:** Interactive physical modifier taps across third-party apps, physical mic hardware routes, live OS TCC prompts, external AX text insertion, Spaces/multi-monitor focus, and VoiceOver traversal remain manual desktop checks.
- **Hardware & OS scope:** Single `Mac15,6` M3 Pro (18 GiB, macOS `26.5.1`). Not extrapolated to 8 GiB Macs, Intel hardware, or macOS 14/15.