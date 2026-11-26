# Measurement Methodology & Metric Definitions

## 1. Test Environment

- **Hardware:** `Mac15,6` — Apple M3 Pro (11 CPU cores: 5 performance + 6 efficiency), 18 GiB unified memory (`19,327,352,832` bytes).
- **OS & Toolchain:** macOS `26.5.1` (`25F80`), Xcode `26.2` (`17C52`), Release (`-O`) arm64 builds.
- **Sandboxing & Isolation:**
  - App cloned from standard Release `.app`, bundle identifier set to `com.rafaeltorres.rasc.efficiency` via `PlistBuddy`, and ad-hoc signed with `--options runtime --entitlements Rasc/Rasc.entitlements --generate-entitlement-der` (App Sandbox enabled, no network access on the main app).
  - Pre-existing personal databases (`~/Library/Application Support/Rasc/Rasc.sqlite` and `~/Library/Containers/com.rafaeltorres.rasc/Data/Library/Application Support/Rasc/Rasc.sqlite`) are `stat`-verified (`mtime_ns`, `size`) before and after every run.
  - Real human speech clips come strictly from CC-BY-4.0 Google FLEURS examples (`Experiments/VoiceCapture/Round4/examples/`), staged inside the isolated sandbox container. No private notes or audio are accessed.

## 2. Two Complementary Release Binaries

1. **Unmodified Shipping Release Binary (zero benchmark code compiled in):**
   - Measures shipping bundle size (`du -sk` + exact file byte breakdown), `n=5` cold launches (`10 Hz` sampling for `8 s`), `90 s` Idle Voice Off (`1 Hz`), `90 s` Idle Voice On after `30 s` Core ML preparation settle (`1 Hz`), and `45 s` Idle with single-modifier shortcut (`Option`) active (`1 Hz`).
   - UserDefaults flags (`-onboardingCompleted YES`, `-voiceCaptureEnabled YES/NO`, `-globalShortcutModifier.voiceScratchpad option`) are supplied via Apple's `NSArgumentDomain` so there are zero `cfprefsd` cache races across runs.
2. **Release Benchmark Driver (`-DRASC_EFFICIENCY_BENCHMARK`):**
   - Compiles `Rasc/Eval/Efficiency/EfficiencyBenchmarkCommandLine.swift` strictly under `#if RASC_EFFICIENCY_BENCHMARK`.
   - Exercises real `NoteRepository` (SQLite + FTS5), `PanelController`, `ScratchpadSession`, `HomeWindowController`, `HomeSession`, `VoiceModel`, `VoiceTextInsertion`, `FoundationModelsRefinementProvider`, `VoiceCapture.shared` sleep/wake/pressure handlers, and `ModifierShortcutMonitor` across an 8-phase (~4–5 minute) workday sequence ending in a `60 s` cooldown and `leaks`/`footprint`/`vmmap`/`lsof` diagnostics.

## 3. Metric Definitions (Never Conflate)

| Metric | Source | What it actually measures |
|---|---|---|
| **App bundle size** | `du -sk Rasc.app` + recursive file sum | On-disk size of `Rasc.app` (`MacOS/Rasc`, `Frameworks`, `VoiceModelDownloader.xpc`, `Resources`). Standard distribution does **not** bundle the speech model. |
| **Speech model on disk** | Verified `VoiceModels/<rev>/` | Separate one-time download (`652,304,885` bytes / `622.09 MiB`), stored only when user opts in to Voice. |
| **Physical memory (`phys_footprint`)** | XNU `proc_pid_rusage(..., RUSAGE_INFO_V6).ri_phys_footprint` & `/usr/bin/footprint` | Apple's canonical Jetsam/dirty+compressed memory metric charged to the app. Reported instead of RSS when summarizing real RAM cost. |
| **RSS (`ri_resident_size`)** | XNU `proc_pid_rusage` | Includes shared `dyld` libraries, read-only frameworks, and memory-mapped files. Much larger than `phys_footprint`; always labeled separately. |
| **Neural footprint (`ri_neural_footprint`)** | XNU `proc_pid_rusage` / `footprint` auxiliary data | Apple Neural Engine / unmapped Core ML weight residency reported by XNU (separate `(nofootprint)` reclaimable backing). |
| **CPU % & Cumulative CPU ms** | Delta `(ri_user_time + ri_system_time) * numer / denom` | Scaled via `mach_timebase_info()` (required on Apple silicon where Mach ticks are `125/3 ns`, not `1 ns`). `cpu_pct` can exceed 100% during concurrent Swift/SQLite/CoreML work on multi-core M3 Pro. |
| **Wakeups (`/s`)** | `ri_pkg_idle_wkups` & `ri_interrupt_wkups` | Hardware package idle wakeups and process interrupt wakeups reported by XNU. |
| **XNU CPU energy (`J`, `mW`)** | `ri_energy_nj` | Per-process **CPU task energy** in nanojoules estimated by XNU. **Not** whole-SoC wall power, GPU/ANE/display rail power, or battery-life hours. |

## 4. Known Measurement & Sandbox Limitations

- **Full-SoC wall power / thermal / battery hours:** `sudo powermetrics` requires interactive root credentials (`sudo -n` unavailable), and `xctrace record --template 'Power Profiler'` errors on macOS (`"The Power Profiler instrument is not supported on macOS"`). Only XNU per-process CPU energy (`ri_energy_nj`) and wakeup rates are reported here.
- **Synthetic vs physical desktop inputs:** Launch, idle windows, and the 8-phase workload ran unattended without live microphone capture or physical `CGEvent` keyboard taps across external apps; live physical hotkeys, microphone hardware routes, external AX text insertion, and macOS Sleep/Lid-close on real desktops remain manual verification items.
- **Hardware & OS scope:** Single `Mac15,6` M3 Pro (18 GiB, macOS `26.5.1`). Not extrapolated to 8 GiB Macs, Intel hardware, or macOS 14/15.
