# Application performance evaluation

**Scope.** Rasc app-level resource use on **Release** builds representative of distribution (`App Sandbox` enabled, no telemetry, no background network). **Not extrapolated** to hardware/OS not tested. **No user data.** Combines controlled `n=3` Release efficiency replications ([EVERYDAY-EFFICIENCY.md](EVERYDAY-EFFICIENCY.md)), Sparkle + Library Load Constraints auditing, and non-blocking long-running smoke harnesses with Round 3 / Round 4 / M13A benchmarks. **Full-SoC wall energy/thermal not measured** (`sudo powermetrics` unavailable; Xcode `Power Profiler` unsupported on macOS) — XNU per-process CPU energy (`ri_energy_nj`) is reported where applicable.

## Environment & Packaging Variants

- `Mac15,6` Apple M3 Pro (11 cores, 18 GiB RAM); macOS `26.5.1` (`25F80`); Xcode `26.2` (`17C52`); Rasc **0.1.16 build 22** (`perf/everyday-efficiency`, `screen_locked: false`); **Release (`-O`)**.
- **Standard local Release `.app`:** **`40.54 MiB`** (`41,516 KiB` / `42,367,708 B`), ad-hoc signed with `Rasc.entitlements`, no bundled Sparkle.
- **Sparkle distribution Release `.app`:** **`44.40 MiB`** (`45,468 KiB` / `46,207,958 B`), embeds `Sparkle.framework` (`3.12 MB`) pinned via `Has Library Load Constraints` (`arm64 CDHash`), zero `network.client` on main app, isolated `VoiceModelDownloader.xpc`.
- **Optional Speech model on disk:** **`652,304,885` bytes (`622.09 MiB`)** stored separately under `Application Support/Rasc/VoiceModels/<rev>` only when the user opts into Voice. Zero persistent background daemons.

## Verified Release Resource States (`n=3` Medians & Sparkle Audit, `Mac15,6`)

| State | Physical footprint (`phys_footprint`) | RSS | CPU / Wakeups | Notes |
|---|---:|---:|---|---|
| **Launch settle (`n=5` cold starts, `n=3` reps)** | **`24.59 MiB`** median `@8 s` (`24.47–24.72`) | **`106.53 MiB`** median | `78.39%` peak → idle in **`0.74 s`** median | Unmodified Release (`25.20 MiB` / `0.83 s` on Sparkle + LLC build). |
| **Idle, no window, Voice Off (`90 s` @ 1 Hz)** | **`24.49 MiB`** median (`24.42–24.53`) | **`106.53 MiB`** median | **`0.0024%`** CPU · **`0.000 pkg_wkup/s`** · `0.01 mW` | Zero background polling; `25.19 MiB` / `0.0026%` CPU on Sparkle + LLC. |
| **Idle, no window, Voice On (`90 s` @ 1 Hz)** | **`50.17 MiB`** median (`42.45–50.22`) | **`123.58 MiB`** median | **`0.0017%`** CPU · **`0.000 pkg_wkup/s`** · `0.00 mW` | Core ML warm (`11.81 MiB` steady / `598.44 MiB` max `neural`); `49.16 MiB` on Sparkle + LLC. |
| **Idle, `Option` modifier active (`45 s` @ 1 Hz, `rep_1`)** | **`42.44 MiB`** p50 | **`118.81 MiB`** p50 | **`0.0048%`** CPU · `0.068 int_wkup/s` · `0.01 mW` | Down from `0.5471%` CPU & `10.89 int_wkup/s` after candidate-only scroll monitoring. |
| **Home open / search / close (`n=20`, `n=3` medians)** | `41.80 MiB` p50 open/search (`rep_1`) | `~140–170 MiB` | `open 4.26 ms` · `search 11.56 ms` · `close 5.77 ms` | Deferred `2.0 s` teardown eliminates `396.37 ms` close regression & keeps `LazyVStack` open speed. |
| **Workday endurance (`~4 min`, `n=3` medians)** | **`143.16 MiB`** peak (`294.99 MiB` before) | `~191 MiB` p50 (`rep_1`) | **`19.58 s`** cum CPU (`66.96 s` before) | **`−51.5%`** peak footprint, **`−70.8%`** CPU time, **`−74.7%`** XNU CPU energy (`52.14 J`). |
| **Post-workload cooldown (`60 s` idle, `n=3` medians)** | **`63.70 MiB`** end (`189.22 MiB` before) | `~160 MiB` | **`0.0048%`** mean CPU (`rep_1`) | **`−66.3%`** cooldown RAM; `CoreAnimation` **`256 KB (16)`** vs `20 MB (855)`; `288` system-only framework cycles (`14.1 KiB`), `0` Rasc leaks. |

## Startup, Persistence, Voice & Long-Running Summary

- **Long-running smoke validations (`run_long_running.py`):** Completed `soak-8h` smoke (`152.1 s`, `60.11 MiB` end after `84.97 MiB` peak = `−24.86 MiB` recovery delta, `3/3` deferred Home releases verified, `3×` Voice/Refine bursts) and detached `idle-24h-voice-on` smoke (`start --detach` → live `status` → graceful `SIGTERM` `stop` flushing `49.31 MiB` end / `0.0 pkg_wkup/s`), preserving personal DBs untouched. Multi-hour `8h` + `24h` data awaits completion of the detached `full-32h` run.
- **Persistence (`AppReliabilityScaleTests` + SQLite):** `10 / 100 / 1,000` notes bootstrap in `6.8–8.8 ms`, FTS5 search `0.94–1.74 ms`, note switch `0.39–0.45 ms`, autosave `0.70–1.34 ms`; post-225-note workday `Rasc.sqlite` is `192,512 B` with `0 B` WAL/SHM after checkpoint.
- **Voice lifecycle:** Warm transcription `55.65–56.32 ms p50` / `106–113 ms p95` (`rep_1` Release); cold prepare `11.96 s` (`0.04 ms` warm); releases cleanly on sleep/memory pressure and compacts short `<50%` `MicBuffer` allocations off the CoreAudio callback.
- **Refine (Apple Foundation Models):** On-device `SystemLanguageModel`, `1,094.66 ms p50` / `3,056.83 ms p95` across 6 sequential invocations in `rep_1`; Capture/Keep/Search never depend on Refine.

## Not Measured / Cannot Claim

- **Full-SoC wall power / battery hours / thermal watts:** `sudo powermetrics` requires root and Xcode `Power Profiler` does not run on macOS.
- **Multi-hour 8h / 24h totals before run completion:** Smoke runs validate the harness; do not cite `8h` soak or `24h` idle results until `build/efficiency-long-running/<run-id>/summary.json` is produced.
- **Other hardware / OS / interactive physical desktop scenarios:** 8 GiB Macs, M1/M2/M4, Intel, macOS 14/15, live third-party hotkeys, physical mic routes, OS TCC prompts, fullscreen Spaces/multi-monitor focus, and VoiceOver traversal.

See [EVERYDAY-EFFICIENCY.md](EVERYDAY-EFFICIENCY.md) and [Experiments/Efficiency/METHODOLOGY.md](../../Experiments/Efficiency/METHODOLOGY.md) for full details.