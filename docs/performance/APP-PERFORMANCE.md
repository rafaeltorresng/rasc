# Application performance evaluation

**Scope.** Rasc app-level resource use on **Release** builds representative of distribution (`App Sandbox` enabled, no telemetry, no background network). **Not extrapolated** to hardware/OS not tested. **No user data.** Combines the new multi-sample & long-running Release suite ([EVERYDAY-EFFICIENCY.md](EVERYDAY-EFFICIENCY.md)) with prior Round 3 / Round 4 / M13A benchmarks. **Full-SoC wall energy/thermal not measured** (`sudo powermetrics` unavailable; Xcode `Power Profiler` unsupported on macOS) — XNU per-process CPU energy (`ri_energy_nj`) is reported where applicable.

## Environment (Current Suite + Reused)

- `Mac15,6` Apple M3 Pro (11 cores, 18 GiB RAM); macOS `26.5.1` (`25F80`); Xcode `26.2` (`17C52`); Rasc **0.1.16 build 22** (`perf/everyday-efficiency` from `1cee496`); **Release (`-O`)** (ad-hoc signed with `Rasc.entitlements`, sandboxed, no Sparkle in local build; distributed build adds Sparkle only on Sparkle target).
- **Physical memory footprint (`phys_footprint`)** vs **RSS** vs **App bundle size** vs **Separate speech model on disk** vs **Auxiliary processes** distinguished.
- **App size:** Release `.app` **`40.5 MiB`** (`41,476 KiB`; `42,326,236` bytes total). Speech model **`652,304,885` bytes (`622.09 MiB`)** stored separately under `Application Support/Rasc/VoiceModels/<rev>` when opted in. Voice model downloader XPC is transient only. **No bundled model in standard build** (preview builds bundle it; not measured). No persistent third-party helper.

## Verified Release Resource States (Optimized `perf/everyday-efficiency`, Mac15,6)

| State | Physical footprint | RSS | CPU / Wakeups | Notes |
|---|---:|---:|---|---|
| **Launch settle (`n=5` cold starts)** | **`22.44 MiB`** p50 `@8 s` (`22.22–22.67`) | **`104.02 MiB`** p50 | `67.53%` peak → idle in **`0.51 s` p50** | Unmodified shipping Release binary; `178.09 ms` p50 CPU over 8 s. |
| **Idle, no window, Voice Off (`90 s` @ 1 Hz)** | **`22.44 MiB`** p50 (`22.41–22.50`) | **`104.09 MiB`** p50 | **`0.0045%`** CPU · `0.011 pkg_wkup/s` · `0.01 mW` XNU CPU | Zero background polling when hidden; `0` Rasc leaks (`leaks`). |
| **Idle, no window, Voice On (`90 s` @ 1 Hz)** | **`47.59 MiB`** p50 (`+25.15 MiB` vs off) | **`117.11 MiB`** p50 | **`0.0045%`** CPU · **`0.000 pkg_wkup/s`** · `0.08 mW` XNU CPU | Core ML model warm (`11.81 MiB` steady / `598.44 MiB` peak `neural_footprint`); `0` Rasc leaks. |
| **Idle, `Option` modifier active (`45 s` @ 1 Hz)** | **`37.63 MiB`** p50 | **`114.14 MiB`** p50 | **`0.0014%`** CPU · `0.136 int_wkup/s` (`0.02 mW`) | Down from `0.5471%` CPU & `10.89 int_wkup/s` after candidate-only scroll monitoring. |
| **Home open/search (`n=20`, 100+ notes)** | **`35.85 MiB`** p50 (`36.08` max) | `~140–170 MiB` | `open 24.47 ms p50` · `search 17.06 ms p50` | Down from `78.70 MiB` FP & `600 ms` open / `163 ms` search (`LazyVStack` + hidden release). |
| **8-phase workday endurance (`~4 min`, 225 notes + 35 FLEURS Voice + 6 Refine + sleep/wake)** | **`136.38 MiB` peak** (`294.99 MiB` before) | `322 MiB` p95 | `17.24 s` cum CPU (`66.96 s` before) | `-53.8%` peak footprint, `-74.3%` CPU time, `-81.4%` XNU CPU energy. |
| **Post-workload cooldown (`60 s` idle)** | **`92.44 MiB`** end (`189.22 MiB` before) | `~160 MiB` | `0.21%` mean CPU (`0.00%` at `cooldown_done`) | `CoreAnimation` dropped `20 MB → 448 KB`; SQLite `192,512 B`, WAL `0 B`; `0` Rasc leaks. |

See [EVERYDAY-EFFICIENCY.md](EVERYDAY-EFFICIENCY.md) and [Experiments/Efficiency/METHODOLOGY.md](../../Experiments/Efficiency/METHODOLOGY.md) for full time-series data, per-phase breakdown, and before/after comparisons.

## Startup, Persistence, Voice & Refine Context (M13A + Round 3 + Round 4)

### Startup & persistence shell (`AppReliabilityScaleTests` + `Rasc.sqlite`)
- `AppReliabilityScaleTests` passes on `10 / 100 / 1,000` notes (`~6.7–8.5 ms` bootstrap, `~0.9–1.7 ms` FTS5 search, `~0.4–0.46 ms` note switch, `~0.66–0.83 ms` autosave in temp SQLite).
- GRDB/SQLite FTS5 `unicode61(diacritics:.remove)` with prefixes `2/3/4`, 500-result cap, single-transaction batch discard + atomic Undo, migrations preserve user data, `AppDiagnostics` never logs note content.

### Voice Capture model lifecycle
- **Model size:** `652,304,885` bytes; `~25 MiB` `phys_footprint` added when warm (`22.44 → 47.59 MiB` idle on `18 GiB` M3 Pro); **keeps model warm while enabled (`VoiceModel(retention: nil)` per [VOICE-CAPTURE.md](../VOICE-CAPTURE.md)) and releases on system sleep, `.warning`/`.critical` memory pressure, disable, or model removal**, proactively re-preparing on wake / `.normal` memory pressure (`~2.08 s` in sleep/wake cycle incl. `1.5 s` delay).
- **Cold / warm `model.prepare()`:** Initial cold Release prepare `15.8–16.7 s` (`28.8 s` first uncached container prepare); warm `0.013–0.016 ms`; Round 4 CLI warm `model.prepare()` after `release()` `11.34 s` initial vs `107.7 ms` warm-OS-cache; warm FLEURS transcription latency remains `~55–56 ms p50` / `~106 ms p95` (`0.005` RTF p50).
- **MicBuffer tail compaction:** Short captures (`<50%` of 90 s preallocated capacity) now compact off the CoreAudio callback upon stop instead of retaining `~17 MB` preallocated slack.

### Refine (Apple Foundation Models)
- Live smoke + `6` sequential refinements executed in Release (`1,081 ms p50`, `3,047 ms p95` on M3 Pro macOS `26.5.1`). External process model residency managed by macOS; Capture/Keep/Search remain independent of Refine.

## Not Measured / Cannot Claim

- **Full-SoC wall power / battery hours / thermal watts:** `sudo powermetrics` requires root and Xcode `Power Profiler` does not run on macOS.
- **Other hardware / OS versions:** Not measured on 8 GiB Macs, M1/M2/M4, Intel Macs, or macOS 14/15; Voice Capture requires Apple silicon + macOS 26.
- **Interactive desktop hardware conditions:** Live physical mic routes (Bluetooth/USB), physical keyboard modifier taps across third-party apps, interactive TCC prompts, fullscreen Spaces/Stage Manager, and VoiceOver navigation require manual macOS desktop testing.
- **Competitor resource comparisons:** Never run head-to-head.

## Honest Bottom Line

Rasc stays a **~40.5 MiB native app** (with Voice's **622 MiB** model downloaded separately only on opt-in) that sits at **`~22.4 MiB` `phys_footprint` (`Voice Off`) or `~47.6 MiB` (`Voice On`) with `<0.005%` idle CPU and ~0 package idle wakeups** on M3 Pro macOS 26.5.1. Eliminating eager `HomeView` list rendering, retaining hidden `Home` SwiftUI state, always-on `.scrollWheel` monitoring, hidden `PanelController` window queries, and oversized `MicBuffer` tails cut peak workday `phys_footprint` by **`53.8%`**, cumulative CPU by **`74.3%`**, Home open latency by **`24.5×`**, and single-modifier idle wakeups by **`98.7%`**. Whole-SoC wattage/battery life and interactive multi-app hardware checks remain explicitly outside automated scope.
