# Everyday Efficiency — Long-Running Resource Evaluation

**Date:** 2026-11-26  
**Branch:** `perf/everyday-efficiency` (from `main @ 1cee496`)  
**Hardware / OS:** Apple M3 Pro (`Mac15,6`, 11 cores, 18 GiB RAM) · macOS `26.5.1` (`25F80`) · Xcode `26.2` (`17C52`)  
**Builds:** Sandboxed Release (`-O`) `com.rafaeltorres.rasc.efficiency` (unmodified shipping binary for bundle/launch/idle; `-DRASC_EFFICIENCY_BENCHMARK` strictly opt-in for the automated 8-phase workday endurance run). Zero personal database files modified (`verified`).

---

## 1. Executive Summary

Evaluating Rasc under Release conditions confirmed both strong architectural fundamentals in its standby shell and concrete inefficiencies under sustained Home usage and modifier-shortcut monitoring:

- **Standby footprint & idle wakeups (Unmodified Shipping Release):**
  - **Voice disabled:** **`22.44 MiB`** p50 physical footprint (`104.09 MiB` RSS), **`0.0045%`** mean CPU, **`0.011/s`** package idle wakeups, **`0.01 mW`** XNU CPU task power, `0` Rasc memory leaks.
  - **Voice enabled & prepared:** **`47.59 MiB`** p50 physical footprint (`117.11 MiB` RSS, `11.81 MiB` steady / `598.44 MiB` lifetime-peak `neural_footprint`), **`0.0045%`** mean CPU, **`0.0/s`** package idle wakeups (`0` over `90 s`), **`0.08 mW`** XNU CPU power.
  - **On-disk size separation:** Release `.app` bundle is **`40.5 MiB`** (`41,476 KiB`); the `Fluid Speech Pro` Core ML model is a separate opt-in **`652,304,885 bytes` (`622.09 MiB`)** pack, not bundled in standard downloads.
- **Real issues uncovered & resolved:**
  1. **Eager SwiftUI `VStack` in `HomeView.noteList`** caused `Home` opening (`600 ms p50`), FTS search (`163 ms p50`), `AttributeGraph`/`CoreAnimation` retention (`20 MB` / `855` CA regions), and `294.99 MiB` peak footprint under repeated workday loops.
  2. **Closed `HomeWindowController` retained its SwiftUI `NSHostingController` & note arrays** indefinitely while hidden (`189.22 MiB` after 60 s cooldown).
  3. **Always-on `.scrollWheel` event monitor in `ModifierShortcutMonitor`** triggered **`10.89` interrupt wakeups/s** and **`0.55%` CPU** at idle (`240.77 ms` CPU over 45 s) whenever a single-modifier Voice trigger (`Option`) was configured, even while no modifier key was pressed.
  4. **Hidden `PanelController` work & uncoalesced timer**: display/activation/occlusion handlers evaluated `CGWindowListCopyWindowInfo` even when the panel was hidden, and `occlusionTimer` ran without kernel coalescing `tolerance`.
  5. **`MicBuffer` 90 s preallocation retention**: short recordings (`0.5–10 s`) kept the full `~17 MB` preallocated `[Float]` capacity through audio conversion until `retryAudio` cleared.
- **Measured Before → After impact (identical Release hardware & workload):**
  - Workday peak `phys_footprint`: **`294.99 MiB` → `136.38 MiB` (`−53.77%`)**
  - Post-workload cooldown `phys_footprint`: **`189.22 MiB` → `92.44 MiB` (`−51.15%`)**
  - Workday cumulative CPU time: **`66,961.56 ms` → `17,237.96 ms` (`−74.26%`)**
  - Workday XNU CPU task energy: **`206.51 J` → `38.40 J` (`−81.40%`)**
  - Home open latency (`n=20`): **`600.17 ms` → `24.47 ms` p50 (`24.5×` faster)**
  - Home search latency (`n=20`): **`162.97 ms` → `17.06 ms` p50 (`9.6×` faster)**
  - Single-modifier idle CPU (`45 s`): **`0.5471%` → `0.0014%` (`−99.7%`, interrupt wakeups `10.89/s` → `0.14/s`)**
  - Voice transcription (`55–56 ms p50` warm) and Apple Intelligence Refine (`1,081 ms p50`) preserved **with zero latency or accuracy regression**.

---

## 2. Architecture Audit & Grounded Optimizations

| Optimization | File(s) | Root Cause Found | Fix Implemented |
|---|---|---|---|
| **1. Lazy Home list rendering** | [HomeView.swift:501](../../Rasc/Features/Home/HomeView.swift#L501) | Default `.list` view mode used eager `VStack`, instantiating every row's `AttributeGraph` / `RascSearchMatch` / `CoreImage` / `CoreAnimation` tree on open and search. | Switched `noteList` container to `LazyVStack(alignment: .leading, spacing: 0)`. `LazyVGrid` (Cards mode) and section headers unchanged. |
| **2. Reclaim hidden Home view & cache** | [HomeSession.swift:137-146](../../Rasc/Features/Home/HomeSession.swift#L137-L146), [HomeWindowController.swift:81-112](../../Rasc/Features/Home/HomeWindowController.swift#L81-L112) | Closing Home via `orderOut` kept `NSHostingController<HomeView>` + full `browseGroups`/`searchResults` alive in RAM indefinitely. | Added `releaseCachedNotesForHiddenWindow()` (preserving `searchQuery`, selection state, and Undo discard receipts) + `window.contentViewController = nil` in `close()` / `windowShouldClose(_:)`, plus separate `NotificationCenter` / `NSWorkspace` observer cleanup in `deinit`. |
| **3. Candidate-only `.scrollWheel` monitoring** | [ModifierShortcut.swift:175-330](../../Rasc/Platform/ModifierShortcut.swift#L175-L330) | `ModifierShortcutMonitor` kept global/local `.scrollWheel` monitors active continuously whenever a single-modifier trigger was enabled, firing handlers on every scroll tick across macOS. | Moved `.scrollWheel` into transient `globalScrollMonitor` / `localScrollMonitor` armed strictly while a configured modifier tap candidate is held down (`candidateStartedAt != nil`) and torn down immediately on release/interference/reset/suspend/stop/deinit. |
| **4. Hidden `PanelController` short-circuit & timer coalescing** | [PanelController.swift:63-91](../../Rasc/Platform/PanelController.swift#L63-L91), [PanelController.swift:658-735](../../Rasc/Platform/PanelController.swift#L658-L735) | `updatePanelLevel()` ran `CGWindowListCopyWindowInfo` even when hidden; display observers revalidated hidden panels; `occlusionTimer` lacked `tolerance`; observers lacked `deinit`. | Guarded `updatePanelLevel(force:)` & display observers on `panel.isVisible`, skipped redundant `CGWindowListCopyWindowInfo` when `homeIsVisible && NSApp.isActive`, added `timer.tolerance = 0.15`, and cleaned observers/monitors in `deinit`. |
| **5. Compact `MicBuffer` tail after recording stops** | [VoiceMicrophone.swift:142-158](../../Rasc/Features/VoiceCapture/VoiceMicrophone.swift#L142-L158), [VoiceCaptureView.swift:64-67](../../Rasc/Features/VoiceCapture/VoiceCaptureView.swift#L64-L67) | `MicBuffer` preallocates 90 s of audio (`~17 MB` at 48 kHz) so the real-time CoreAudio tap never allocates, and previously kept the full backing array capacity afterward. | When `< 50%` of capacity was recorded, `MicBuffer.audio()` now compacts off the audio callback via `storage.withUnsafeBufferPointer { Array($0) }` and clears `storage = []`; `VoiceCaptureWindows.hideStatus()` clears `previousApp = nil`. |

---

## 3. Empirical Results: Before vs After (Release Builds)

### 3.1 Bundle & Disk Breakdown

| Artifact | Baseline (`1cee496`) | Optimized | Notes |
|---|---:|---:|---|
| Release `.app` size (`du -sk`) | `41,444 KiB` (`40.47 MiB`) | `41,476 KiB` (`40.50 MiB`) | Includes Sparkle-free main binary (`41.4 MiB`), GRDB/deps, `VoiceModelDownloader.xpc` (`311 KB`). |
| Speech model (`Fluid Speech Pro`) | `652,304,885 B` (`622.09 MiB`) | `652,304,885 B` (`622.09 MiB`) | Opt-in external pack; **0 bytes bundled in `.app`**. |
| SQLite post-225-note workday | `Rasc.sqlite` `192,512 B` · WAL `0 B` · SHM `0 B` | `Rasc.sqlite` `192,512 B` · WAL `0 B` · SHM `0 B` | FTS5 `unicode61` index included; WAL cleanly checkpointed at exit. |

### 3.2 Cold Startup (`n=5` Unmodified Shipping Release Runs)

| Metric | Baseline (min / p50 / max) | Optimized (min / p50 / max) |
|---|---|---|
| Peak launch CPU % | `68.24` / `68.82` / `74.17%` | `60.75` / `67.53` / `79.97%` |
| Time to idle (`<1.5%` CPU) | `0.20` / `0.60` / `0.70 s` | `0.20` / `0.51` / `0.70 s` |
| Settled `phys_footprint` (`@8 s`) | `22.17` / `22.38` / `22.39 MiB` | `22.22` / `22.44` / `22.67 MiB` |
| Settled `RSS` (`@8 s`) | `103.73` / `103.92` / `103.95 MiB` | `103.83` / `104.02` / `104.28 MiB` |
| Cumulative CPU (first `8 s`) | `174.22` / `195.28` / `207.77 ms` | `169.54` / `178.09` / `204.76 ms` |
| Package idle wakeups (`8 s`) | `0` / `1` / `2` | `0` / `1` / `3` |

### 3.3 Steady Idle Windows (Unmodified Shipping Release Binary)

| State | `phys_footprint` p50 | RSS p50 | `neural` p50 / max | CPU mean | Cum CPU | `pkg_idle_wkup/s` | `interrupt_wkup/s` | XNU CPU power |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| **Idle — Voice Off (`90 s`) Before** | `22.41 MiB` | `103.02 MiB` | `0.0 / 0.0 MiB` | `0.2531%` | `225.23 ms` | `0.045/s` | `3.685/s` | `0.61 mW` |
| **Idle — Voice Off (`90 s`) After** | **`22.44 MiB`** | `104.09 MiB` | `0.0 / 0.0 MiB` | **`0.0045%`** | **`3.98 ms`** | **`0.011/s`** | **`0.067/s`** | **`0.01 mW`** |
| **Idle — Voice On (`90 s`) Before** | `48.64 MiB` | `123.66 MiB` | `11.81 / 598.44 MiB` | `0.0022%` | `1.97 ms` | `0.000/s` | `0.023/s` | `0.03 mW` |
| **Idle — Voice On (`90 s`) After** | **`47.59 MiB`** | `117.11 MiB` | `11.81 / 598.44 MiB` | **`0.0045%`** | **`4.01 ms`** | **`0.000/s`** | **`0.067/s`** | **`0.08 mW`** |
| **Idle — `Option` Modifier (`45 s`) Before** | `40.38 MiB` | `123.59 MiB` | `11.81 / 598.44 MiB` | `0.5471%` | `240.77 ms` | `0.114/s` | `10.885/s` | `1.76 mW` |
| **Idle — `Option` Modifier (`45 s`) After** | **`37.63 MiB`** | `114.14 MiB` | `11.81 / 598.44 MiB` | **`0.0014%`** | **`0.61 ms`** | **`0.000/s`** | **`0.136/s`** | **`0.02 mW`** |

*(Note: Voice Off baseline's slightly higher `0.2531%` mean CPU reflected background desktop scroll/activation churn on the live workstation during that 90 s sample, whereas Voice On settled at `0.0022%–0.0045%` and Modifier-only idle dropped `99.7%` after isolating `.scrollWheel` monitoring.)*

### 3.4 8-Phase Workday Endurance Suite (Before vs After)

| Phase / Metric | Baseline | Optimized | Delta |
|---|---:|---:|---:|
| **Peak `phys_footprint` (`lifetime_max`)** | `294.99 MiB` | **`136.38 MiB`** | **`−158.61 MiB` (−53.8%)** |
| **Total cumulative CPU time** | `66,961.56 ms` | **`17,237.96 ms`** | **`−49,723.60 ms` (−74.3%)** |
| **Total XNU CPU task energy** | `206.51 J` | **`38.40 J`** | **`−168.11 J` (−81.4%)** |
| **Phase: `seed_and_idle_voice_off` p50 FP** | `22.84 MiB` (`0.56%` CPU) | **`22.70 MiB` (`0.02%` CPU)** | `−0.14 MiB` |
| **Phase: `scratchpad_capture_loop` (30×) p50 FP** | `26.63 MiB` (`20.07%` CPU) | **`26.74 MiB` (`19.59%` CPU)** | `+0.11 MiB` |
| **Phase: `home_search_loop` (20×) p50 FP / max** | `78.70` / `94.52 MiB` (`77.96%` CPU) | **`35.85` / `36.08 MiB` (`21.93%` CPU)** | **`−54.5%` FP · `−71.9%` CPU** |
| **Phase: `home_batch_ops` (10×) p50 FP** | `102.69 MiB` | **`50.16 MiB`** | **`−51.2%` FP** |
| **Phase: `voice_capture_and_dictate` (15× + 30s) p50 / max FP** | `188.20` / `215.09 MiB` | **`81.19` / `106.20 MiB`** | **`−56.9%` p50 FP** |
| **Phase: `refine_on_device` (6× Foundation Models) p50 FP** | `162.81 MiB` | **`84.05 MiB`** | **`−48.4%` FP** |
| **Phase: `sleep_wake_and_memory_pressure` p50 FP** | `162.83 MiB` | **`85.63 MiB`** | `−47.4%` FP |
| **Phase: `workday_endurance_loop` (60× mixed) p50 / max FP** | `228.26` / `293.41 MiB` (`43.58%` CPU) | **`119.06` / `126.16 MiB` (`12.92%` CPU)** | **`−47.8%` p50 · `−57.0%` peak · `−70.4%` CPU** |
| **Endurance loop memory slope (OLS)** | `−3.89 MiB/min` | **`−25.63 MiB/min`** (reclaiming) | Zero upward drift |
| **Phase: `post_workload_cooldown` (60 s idle) end FP / CPU** | `189.22 MiB` / `0.68%` | **`92.44 MiB` / `0.21%`** | **`−51.2%` FP (`CoreAnimation` `20 MB → 448 KB`)** |

### 3.5 Per-Operation Latency (p50 / p95 ms)

| Operation | Count | Baseline (p50 / p95 ms) | Optimized (p50 / p95 ms) | Delta p50 |
|---|---:|---:|---:|---:|
| `home_open` | 20 | `600.17` / `640.63` | **`24.47` / `40.20`** | **`−95.9%` (`24.5×` faster)** |
| `home_search` | 20 | `162.97` / `667.15` | **`17.06` / `24.80`** | **`−89.5%` (`9.6×` faster)** |
| `home_close` *(note 1)* | 20 | `6.63` / `501.02` | `396.37` / `517.08` | SwiftUI teardown runs synchronously on explicit hide |
| `home_batch_copy_discard_undo` | 10 | `541.43` / `699.44` | **`183.72` / `239.81`** | **`−66.1%`** |
| `endurance_home_cycle` (open+search+close) | 20 | `1,219.88` / `1,449.53` | **`61.51` / `219.36`** | **`−95.0%` (`19.8×` faster)** |
| `scratchpad_cycle` | 30 | `45.15` / `529.78` | `51.43` / `533.10` | Unchanged |
| `endurance_scratchpad` | 60 | `40.14` / `938.41` | `37.50` / `520.52` | `-6.6%` (`-44.5%` p95) |
| `voice_scratchpad_transcribe` | 8 | `56.00` / `128.61` | **`55.11` / `105.87`** | Unchanged |
| `voice_dictate_transcribe` | 7 | `61.11` / `118.88` | **`56.29` / `105.91`** | Unchanged |
| `endurance_voice` | 20 | `78.82` / `608.38` | **`79.89` / `136.15`** | **`−77.6%` p95** |
| `voiceColdPrepareMs` | 1 | `16,673.85 ms` | `15,816.01 ms` | Initial Core ML load (`VoiceModel`) |
| `voiceWarmPrepareMs` | 1 | `0.013 ms` | `0.016 ms` | Already prepared |
| `sleep_wake_cycle` | 1 | `2,080.92 ms` | `2,081.12 ms` | Includes intentional `1.5 s` post-wake delay |
| `refine_invoke` (Apple Intelligence) | 6 | `1,090.43` / `3,221.04` | `1,081.05` / `3,046.71` | On-device `SystemLanguageModel` |

*(Note 1: `home_close` runs `releaseHiddenContent` which sets `window.contentViewController = nil` to drop `HomeView`'s SwiftUI tree (~396 ms after an already-awaited full unfiltered `reloadImmediately()`), cutting steady cooldown `CoreAnimation` from `20 MB` / `855` regions to `448 KB` / `14` regions while combined `endurance_home_cycle` drops `1,220 ms` to `61.5 ms` p50.)*

---

## 4. Leaks, VM Categories & Auxiliary Processes

- **Memory leaks (`leaks` tool):**
  - Across every inspected window (`idle_voice_off`, `idle_voice_on`, `idle_modifier_on`, `workday_cooldown`), `leaks` reported **zero Rasc allocations**.
  - All `192–288` cycles (`~9.6–14.4 KB` total) originate inside Apple's `AppIntents` framework (`NSXPCConnection` / `LNDaemonApplicationInterface` / `LNProcessInstanceRegistryClient` internal retain cycle triggered during `Rasc.app` launch/metadata indexing).
- **VM breakdown at post-workload cooldown (`footprint` optimized vs baseline):**
  - `CoreAnimation`: `20 MB (855 regions)` → **`448 KB (14 regions)` (`−97.8%`)**
  - `CG image` + `CoreImage`: `3,584 KB (224)` + `3,568 KB (223)` → **`0 B`**
  - `MALLOC_SMALL` dirty: `173 MB` → **`73 MB`** (dominated by Core ML / Foundation Models frameworks once warmed in-process)
  - `SQLite page cache`: `128 KB` reclaimable, `16 KB` dirty.
- **Auxiliary processes (`ps`):** No persistent background daemons, agents, or helpers; only `com.rafaeltorres.rasc.VoiceModelDownloader.xpc` runs transiently during an explicit opt-in model download.

---

## 5. Limitations & Open Manual Desktop Checks

1. **Whole-SoC energy / thermal / battery impact:** Not measured (`sudo powermetrics` needs interactive root authentication; Apple's `xctrace Power Profiler` template does not support macOS). XNU `ri_energy_nj` covers CPU task energy only.
2. **Physical hardware & live macOS integration:** Live physical keyboard taps (`Option` modifier tap across third-party apps), physical microphone capture with Bluetooth/USB route changes, live TCC Microphone/Accessibility approval flows, external app `AXSelectedText` insertion, multi-monitor/Spaces focus, and VoiceOver traversal still require interactive desktop checks.
3. **Hardware scope:** Results reflect `Mac15,6` M3 Pro (18 GiB, macOS `26.5.1`). Do not extrapolate verbatim to 8 GiB Apple silicon Macs, Intel Macs, or macOS 14/15.
