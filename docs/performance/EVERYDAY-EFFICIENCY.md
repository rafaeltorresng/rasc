# Everyday Efficiency — Resource & Responsiveness Evaluation

**Date:** 2026-11-26  
**Branch:** `perf/everyday-efficiency` (from `main @ 1cee496`)  
**Hardware / OS:** Apple M3 Pro (`Mac15,6`, 11 cores, 18 GiB RAM) · macOS `26.5.1` (`25F80`) · Xcode `26.2` (`17C52`)  
**Session & Builds:** Sandboxed Release (`-O`) `com.rafaeltorres.rasc.efficiency` with desktop unlocked (`screen_locked: false`). Unmodified shipping binary (standard + Sparkle LLC distribution) tested alongside `-DRASC_EFFICIENCY_BENCHMARK` workday (`n=3` replications) and `--run-soak-bench` runners. Zero personal SQLite database files modified (`verified`).

---

## 1. Executive Summary

Evaluating Rasc across `n=3` controlled Release replications, Sparkle + Library Load Constraints packaging, and non-blocking long-running smoke harnesses confirmed ultra-quiet idle behavior and fixed both Home retention bloat and synchronous close latency:

- **Standby footprint & idle wakeups (Unmodified Shipping Release, `n=3` unlocked medians):**
  - **Voice disabled (`90 s`):** **`24.49 MiB`** p50 `phys_footprint` (`24.42–24.53 MiB`, `106.53 MiB` RSS), **`0.0024%`** mean CPU, **`0.000/s`** package idle wakeups, **`0.01 mW`** XNU CPU power.
  - **Voice enabled & prepared (`90 s`):** **`50.17 MiB`** p50 `phys_footprint` (`42.45–50.22 MiB`, `123.58 MiB` RSS, `11.81 MiB` steady / `598.44 MiB` lifetime-peak `neural_footprint`), **`0.0017%`** mean CPU, **`0.000/s`** package idle wakeups (`0` over `90 s`), **`0.00 mW`** XNU CPU power (`0.1 mJ`).
  - **On-disk bundle separation:** Standard local Release `.app` is **`40.54 MiB`** (`41,516 KiB` / `42,367,708 B`). Sparkle distribution with `cdhash`-pinned Library Load Constraints is **`44.40 MiB`** (`45,468 KiB` / `46,207,958 B`). The `Fluid Speech Pro` Core ML pack (`652,304,885 B` / `622.09 MiB`) is never bundled inside `.app` and downloads once only on explicit opt-in via isolated `VoiceModelDownloader.xpc`.
- **Root-cause optimizations & post-optimization `home_close` fix:**
  1. **Lazy Home list rendering (`LazyVStack`):** Replaced eager `VStack` in [HomeView.swift:501](../../Rasc/Features/Home/HomeView.swift#L501), cutting `home_open` from `600.17 ms` to **`4.26 ms` median** (`3.79–4.28 ms`) and `home_search` from `162.97 ms` to **`11.56 ms` median** (`10.91–12.33 ms`).
  2. **Deferred Home teardown (`2.0 s` grace + memory-pressure flush):** Earlier synchronous `window.contentViewController = nil` inside `close()`/`windowShouldClose(_:)` triggered `396.37 ms` p50 AppKit/TSM stalls on active closes. Moving `releaseHiddenContent(of:)` onto a cancellable `2.0 s` deferred task with `NSHostingController` reuse, `HomeSession.focusSearchRequestID` focus refresh, and immediate `DispatchSourceMemoryPressure` eviction brought `home_close` back to **`5.77 ms` median** (`4.81–6.18 ms`, vs `6.63 ms` baseline) while cutting cooldown footprint even further to **`63.70 MiB` median** (`62.19–88.05 MiB`, **`−66.3%`** vs `189.22 MiB` baseline) and `CoreAnimation` regions from `20 MB (855)` to **`256 KB (16)`**.
  3. **Candidate-only `.scrollWheel` monitoring (`ModifierShortcutMonitor`):** Armed global/local `.scrollWheel` monitors strictly while a configured modifier candidate is held down (`Option` idle CPU dropped from `0.5471%` / `10.89 int_wkup/s` to **`0.0048%`** / **`0.068 int_wkup/s`** in representative `rep_1`).
  4. **Hidden `PanelController` short-circuit & timer coalescing:** Guarded `CGWindowListCopyWindowInfo` and display observers on `panel.isVisible`, added `occlusionTimer.tolerance = 0.15`, and cleaned observers in `deinit`.
  5. **`MicBuffer` compaction & status window cleanup:** Compacted `<50%` buffers off the CoreAudio callback upon stop instead of retaining `~17 MB` preallocated capacity, and cleared `previousApp = nil` when hiding `VoiceCaptureWindows`.
- **Measured Before (`1cee496`) → After (`2a1bddf`, `n=3` unlocked medians):**
  - Workday peak `phys_footprint`: **`294.99 MiB` → `143.16 MiB` median** (`140.09–143.97 MiB`, **`−51.5%`**)
  - Post-workload cooldown `phys_footprint`: **`189.22 MiB` → `63.70 MiB` median** (`62.19–88.05 MiB`, **`−66.3%`**)
  - Workday cumulative CPU time: **`66,961.56 ms` → `19,581.35 ms` median** (`−70.8%`)
  - Workday XNU CPU energy: **`206.51 J` → `52.14 J` median** (`−74.7%`)
  - `home_open` (`n=20`): **`600.17 ms` → `4.26 ms` median** (`3.79–4.28 ms`, **`141×` faster**)
  - `home_close` (`n=20`): **`6.63 ms` baseline** / `396.37 ms` pre-fix → **`5.77 ms` median** (`4.81–6.18 ms`)
  - `home_search` (`n=20`): **`162.97 ms` → `11.56 ms` median** (`10.91–12.33 ms`, **`14.1×` faster**)

---

## 2. Empirical Results (`n=3` Replications + Sparkle + Smokes)

### 2.1 Multi-Replication Stability (`n=3`, `results/optimized/replications.json`)

| Metric | Baseline (`1cee496`) | Optimized Median (`rep_1..rep_3`) | Min – Max (IQR) |
|---|---:|---:|---|
| Launch to idle p50 (`<1.5%` CPU) | `0.60 s` | **`0.74 s`** | `0.73–0.76 s` (`0.015`) |
| Launch settled `phys_footprint` (`@8 s`) | `22.38 MiB` | **`24.59 MiB`** | `24.47–24.72 MiB` (`0.13`) |
| Idle Voice Off `phys_footprint` p50 | `22.41 MiB` | **`24.49 MiB`** | `24.42–24.53 MiB` (`0.06`) |
| Idle Voice Off CPU / pkg wkup | `0.2531%` / `0.045/s` | **`0.0024%` / `0.000/s`** | `0.0018–0.0046%` / `0.0–0.0/s` |
| Idle Voice On `phys_footprint` p50 | `48.64 MiB` | **`50.17 MiB`** | `42.45–50.22 MiB` (`3.89`) |
| Idle Voice On `neural_footprint` p50 | `11.81 MiB` | **`11.81 MiB`** | `11.81–11.81 MiB` (`0.00`) |
| Idle Voice On CPU / pkg wkup | `0.0022%` / `0.000/s` | **`0.0017%` / `0.000/s`** | `0.0013–0.0022%` / `0.0–0.0/s` |
| Workday peak `phys_footprint` | `294.99 MiB` | **`143.16 MiB`** | `140.09–143.97 MiB` (`1.94`) |
| Post-cooldown `phys_footprint` end | `189.22 MiB` | **`63.70 MiB`** | `62.19–88.05 MiB` (`12.93`) |
| Endurance OLS slope | `−3.89 MiB/min` | **`−24.38 MiB/min`** | `−26.62` to `−0.89` (`12.87`) |
| `home_open` p50 | `600.17 ms` | **`4.26 ms`** | `3.79–4.28 ms` (`0.24`) |
| `home_search` p50 | `162.97 ms` | **`11.56 ms`** | `10.91–12.33 ms` (`0.71`) |
| `home_close` p50 | `6.63 ms` | **`5.77 ms`** | `4.81–6.18 ms` (`0.68`) |
| Workday cumulative CPU ms | `66,961.56 ms` | **`19,581.35 ms`** | `19,540–22,336 ms` (`1,398`) |
| Workday XNU CPU task energy | `206.51 J` | **`52.14 J`** | `42.54–53.13 J` (`5.30`) |

### 2.2 Representative `rep_1` Per-Operation Breakdown vs Baseline

| Operation | Count | Baseline (p50 / p95 ms) | Optimized `rep_1` (p50 / p95 ms) | Notes |
|---|---:|---:|---:|---|
| `home_open` | 20 | `600.17` / `640.63` | **`3.79` / `7.16`** | Warm reused VC + `LazyVStack` (`10.48 ms` max) |
| `home_search` | 20 | `162.97` / `667.15` | **`10.91` / `21.73`** | FTS5 + lazy row tree |
| `home_close` *(note 1)* | 20 | `6.63` / `501.02` | **`6.18` / `506.28`** | Fixes `396.37 ms` p50 synchronous teardown stall |
| `home_batch_copy_discard_undo` | 10 | `541.43` / `699.44` | **`195.60` / `224.26`** | **`−63.9%` p50** |
| `endurance_home_cycle` | 20 | `1,219.88` / `1,449.53` | **`56.92` / `573.09`** | **`−95.3%` p50** (`178.13 ms` mean) |
| `scratchpad_cycle` | 30 | `45.15` / `529.78` | **`39.90` / `523.43`** | TextKit + SQLite autosave |
| `voice_scratchpad_transcribe` | 8 | `56.00` / `128.61` | **`55.65` / `106.49`** | On-device `Fluid Speech Pro` |
| `voice_dictate_transcribe` | 7 | `61.11` / `118.88` | **`56.32` / `112.89`** | Clipboard + local copy preserved |
| `endurance_voice` | 20 | `78.82` / `608.38` | **`86.56` / `168.10`** | **`−72.4%` p95** |
| `voiceColdPrepareMs` | 1 | `16,673.85 ms` | **`11,960.07 ms`** | Initial Core ML load (`0.041 ms` warm) |
| `refine_invoke` | 6 | `1,090.43` / `3,221.04` | **`1,094.66` / `3,056.83`** | On-device Apple Foundation Models |

*(Note 1: `p95Ms` `506.28 ms` reflects occasional WindowServer/TSM focus fences on unlocked macOS also observed in baseline `501.02 ms` p95; deferred teardown runs safely `2.0 s` later when hidden.)*

### 2.3 Sparkle Distribution + Library Load Constraints Audit (`results/sparkle_distribution.json`)

- **Signing & Entitlements Verified (`codesign --verify --deep --strict`):**
  - `Has Library Load Constraints: true` (`cdhash` pinning `arm64` `Sparkle.framework` slice `0e66f4ed0b19cb8b52fd8063740ba80e1481366a`).
  - Main app carries **no** `com.apple.security.network.client`; `com.rafaeltorres.rasc.VoiceModelDownloader.xpc` keeps `com.apple.security.network.client` and **no** `device.audio-input`.
- **Disk footprint:** **`44.40 MiB`** (`45,468 KiB` / `46,207,958 B`; includes `3.12 MB` `Sparkle.framework`, `42.39 MB` main binary, `311 KB` XPC, `359 KB` resources); `622.09 MiB` speech model remains external.
- **Launch & Idle (`n=5` launches, `90 s` windows, `screen_locked: false`):**
  - Cold launch: `0.83 s` p50 to idle, `25.20 MiB` p50 `phys_footprint` (`107.31 MiB` RSS), `0` pkg idle wakeups over 8 s.
  - Idle Voice Off: **`25.19 MiB`** p50 `phys_footprint` (`107.06 MiB` RSS), **`0.0026%`** CPU, **`0.000/s`** pkg idle wakeups, `0.00 mW` XNU CPU power.
  - Idle Voice On: **`49.16 MiB`** p50 `phys_footprint` (`125.67 MiB` RSS, `11.81 MiB` `neural`), **`0.0020%`** CPU, **`0.000/s`** pkg idle wakeups, `0.00 mW` XNU CPU power.

### 2.4 Non-Blocking Long-Running Infrastructure & Smoke Validation (`results/long_running_smoke/`)

To distinguish `~4–5 min` accelerated suites from multi-hour macOS residency, [run_long_running.py](../../Experiments/Efficiency/scripts/run_long_running.py) + `--run-soak-bench` provide reproducible detached `8h` soak and `24h` Voice-On idle monitoring (`build/efficiency-long-running/<run-id>/`):

- **Completed `soak-8h` smoke (`152.1 s`, `2 s` streaming CSV + periodic `120 s` diagnostics):** Executed 3 full cycles (`Scratchpad`, `Home` open/search/batch/close + `3/3` verified `2 s` deferred teardown releases, `Voice` Scratchpad & Dictate clips, `3×` on-device `Refine`). Settled from `84.97 MiB` max to **`60.11 MiB` end** (`−24.86 MiB` recovery delta; `slope −116.78 MiB/h`; `4.73%` mean CPU; `0.026 pkg_wkup/s`; `20.94 J` XNU CPU energy; `personal_db_unchanged: true`).
- **Detached `idle-24h-voice-on` smoke (`start --detach`, live `status`, `stop` via `SIGTERM`):** Confirmed background `supervisor_pid` + `child_pid` liveness, graceful signal shutdown flushing `20.1 s` post-settle samples (`49.31 MiB` end / `49.34 MiB` p50 `phys_footprint`, `11.81 MiB` `neural`, `0.000/s` pkg idle wakeups, `personal_db_unchanged: true`).
- Full `8h` soak + `24h` idle metrics are reported only once the detached multi-hour run finishes; smoke runs validate correctness, isolation, signal safety, and telemetry fidelity without claiming 8h/24h totals prematurely.

---

## 3. Leaks, VM Categories & Auxiliary Processes

- **Memory leaks (`leaks` tool):**
  - Across `idle_voice_off`, `idle_voice_on`, `idle_modifier_on`, `workday_cooldown`, `sparkle_distribution`, and `soak_t000120s`, `leaks` reported **zero Rasc-owned leaks**.
  - All `288` reported nodes (`14,400 bytes` / `14.1 KiB`) trace to Apple's system framework `NSXPCConnection` / `LNDaemonApplicationInterface` (`AppIntents` metadata daemon retain cycle, identical to baseline `288`).
- **VM breakdown at `rep_1` cooldown (`/usr/bin/footprint`: `59 MB` total):**
  - `CoreAnimation`: `20 MB (855 regions)` → **`256 KB (16 regions)`**
  - `CG image` + `CoreImage`: `3,584 KB (224)` + `3,568 KB (223)` → **`48 KB (3)`** + **`0 B`**
  - `MALLOC_SMALL`: `173 MB` → **`46 MB`**
- **Zero persistent background daemons.** Auxiliary processes exist only on-demand (`VoiceModelDownloader.xpc`).

---

## 2.5 Multi-Hour Longevity, `5,000`-Note Scale & Streaming `mono16k()` Follow-Up (2026-11-27)

- **Multi-hour run analysis ([`Experiments/Efficiency/results/long_running_20261126/REPORT.md`](../../Experiments/Efficiency/results/long_running_20261126/REPORT.md), `20261126-191517-full-32h`):**
  - **Stage 1 Active Soak (`completed`, `8.00 h` / `28,801.45 s` wall, `15,594.13 s` active, `3,112` samples, `15` macOS sleep events, `32` cycles, `260` notes, `32` Refine, `7` sleep/wake probes):** `phys_footprint` p50 **`73.70 MiB`** / end **`73.77 MiB`** / max `125.99 MiB` (`recovery -52.22 MiB`); `neural_footprint` `11.81 MiB` p50 (`598.44 MiB` peak); CPU **`0.0295%` p50** (`0.9485%` mean); wakeups **`0.0/s` p50** (`0.0065/s` mean); `471.5331 J` XNU CPU energy; FDs `58–62`; **`0` Rasc leaks** (`288` Apple `LNDaemonApplicationInterface` XPC nodes constant).
  - **Stage 2 Voice-On Idle Standby (`interrupted_at_8.50h` of `24.0h`, `30,611.08 s` wall, `2,041` samples, host stop `2026-11-27T11:46:05-0300` — not extrapolated beyond `8.50h`):** `phys_footprint` dropped from `61.88 MiB` to **`30.94 MiB` end** (**`33.66 MiB` p50**, slope **`−1.0611 MiB/h`**); `neural_footprint` flat **`11.81 MiB`**; **`0.0%` p50 CPU** (`0.0048%` mean, `1,461.2 ms` total across `8.50h`); **`0.0/s` p50 wakeups** (`7` total in `8.50h` = `0.0002/s`); **`1.9586 J`** total XNU CPU energy (**`0.06 mW` mean**); FDs `47 → 46`; **`0` Rasc leaks**.
- **Release `5,000`-Note Scale (`30c5c14`, `scale_1k_5k_final.json`):** At `5,000` notes (`1,000` kept), `bootstrap` `6.39 ms`, `fetchMostRecentP50` **`0.041 ms`**, `fetchAllNonDeleted` `11.54 ms`, `search(20)` **`4.48 ms`**, `search(500)` **`6.62 ms`**, `batchDiscard50` `0.59 ms`, `restore50` `3.93 ms`, `purge500` `8.06 ms`, `backup` **`6.24 ms`** (`3,227,648 B`), WAL truncate checkpoint `5.00 ms` (`2,282,512 B → 0 B`).
- **Release Streaming `VoiceAudio.mono16k()` (`30c5c14`, `final_streaming_mono16k.json`):** Replacing full-buffer non-16 kHz conversion with reusable `15 s` chunked `AVAudioConverter` passes preserved **`4,800,000 / 4,800,000` (`100.0%`)** frames on `300 s @ 48 kHz` (`norm_en_us_300s_48k_mono`) in **`21.66 ms`**, settling at **`32.30 MiB`** post-release footprint with zero WER loss (`9.605%` across `longform_norm`).

---

## 4. Limitations & Open Manual Desktop Checks

1. **Whole-SoC power / thermal / battery hours:** Not measured (`sudo powermetrics` unavailable; Xcode `Power Profiler` unsupported on macOS). XNU `ri_energy_nj` reflects per-process CPU energy only.
2. **Stage 2 standby boundary:** Stage 1 completed its full `8.00 h` wall target; Stage 2 recorded `8.50 h` of continuous Voice-On standby before the host stopped cleanly, so claims are bounded strictly to the observed `8.50 h`.
3. **Interactive desktop checks:** Live third-party modifier key taps, physical Bluetooth/USB audio routing, OS TCC modal approvals, external AX insertion, fullscreen Spaces/multi-monitor transitions, and VoiceOver traversal still require interactive macOS desktop testing.
4. **Hardware scope:** Results reflect `Mac15,6` M3 Pro (18 GiB, macOS `26.5.1`). Do not extrapolate verbatim to 8 GiB Apple silicon Macs, Intel Macs, or macOS 14/15.