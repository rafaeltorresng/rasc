# Multi-Hour Efficiency Run Analysis (`20261126-191517-full-32h`)

**Provenance:** Started `2026-11-26T19:15:31-0300` on PR #107 (`perf/everyday-efficiency`, pre-PRs #108–#111), isolated bundle `com.rafaeltorres.rasc.longrun` (standard Sandbox, non-Sparkle), pinned model `3b9d38a93d606f84011e5a0a669b7ea146375a22`.  
**Personal database integrity:** Unchanged (`all == True`).

## Stage 1 — 8-Hour Workday Soak (`completed`)

- **Duration & sleep:** **8.0 h wall** (`28801.45 s`), `15594.13 s` active across `15` macOS sleep events (`13207.05 s` suspended gap), `3112` samples, **`32` soak cycles** (`260` notes at end, `32` Refine invocations, `7` explicit sleep/wake probes).
- **Physical memory (`phys_footprint`):** start `0.08 MiB` → end **`73.77 MiB`**, p50 **`73.7 MiB`**, p95 `110.49 MiB`, peak `125.99 MiB` (recovery `-52.22 MiB`, OLS slope `+2.4667 MiB/h` driven by growing DB/soak notes). Quiet-standby segments averaged `74.25 MiB` (p50 `73.67 MiB`).
- **Neural footprint:** steady **`11.81 MiB` p50** (`598.44 MiB` peak during active model steps).
- **CPU & wakeups:** **`0.0295%` p50** (`0.9485%` mean), **`0.0/s` p50 pkg idle wakeups** (`0.0065/s` mean), `471.5331 J` XNU CPU task energy across 8 hours (`30.24 mW` mean).
- **In-app operation latencies (`in_app_summary.json`):**
  - `soak_voice_scratchpad` (`n=32`): **`77.67 ms` p50** / `157.32 ms` p95
  - `soak_voice_dictate` (`n=32`): **`58.79 ms` p50** / `130.68 ms` p95
  - `soak_home_open` (`n=32`): **`30.61 ms` p50** / `60.86 ms` p95
  - `soak_home_search` (`n=32`): **`22.89 ms` p50** / `33.72 ms` p95
  - `soak_home_close` (`n=32`): **`6.35 ms` p50** (`344.12 ms` p95, WindowServer/TSM focus fence)
  - `soak_home_deferred_check` (`n=32`): **`1.0 ms` p50**, releasing deferred Home view trees on `30/32` fast checks
  - `soak_refine` awake-only (`n=31`): **`2775.22 ms` p50** / `3141.64 ms` p95 / `5102.86 ms` max. **Cycle 12 outlier explanation:** `durationMs = 995,196.1 ms` spanned `5` system sleep events detected between `2026-11-27T01:33:01Z` and `2026-11-27T02:57:25Z` (`ContinuousClock` / wall pause).
- **Memory leaks (`leaks`):** `8 periodic snapshots: constant 288 nodes (14,400 B), 100% Apple LNDaemonApplicationInterface NSXPCConnection cycle; 0 Rasc leaks; open FDs 58-62`.

## Stage 2 — Continuous Voice-On Standby (`8.50 h` captured of `24.0 h` target)

- **Scope:** Captured **`8.5 h`** (`30610.97 s`, `2041` samples, `0` sleep events) continuously until `2026-11-27T11:46:05-0300`, when host processes stopped during server restart/maintenance. Not extrapolated to `24 h`.
- **Memory (`phys_footprint` & `neural_footprint`):** Started at `61.88 MiB`, compressed/settled downward to **`30.94 MiB`** (`33.66 MiB` p50, **`-1.0611 MiB/h` negative slope**; first-hour mean `42.55 MiB` vs last-hour mean `32.94 MiB`). `neural_footprint` held flat at **`11.81 MiB`**.
- **CPU, wakeups & XNU CPU task energy over 8.50 h:** **`0.0%` p50 CPU** (`0.0048%` mean, `1461.20 ms` cumulative over 8.50 h), **`0.0/s` p50 pkg idle wakeups** (`7` total = `0.0002/s` mean), **`0.0/s` p50 interrupt wakeups**, and **`1.9586 J` total** (`0.0 mW` p50 / `0.06 mW` mean).
- **Memory leaks & open FDs:** `16 periodic snapshots across 8.50h: constant 288 nodes (14,400 B), 100% Apple LNDaemonApplicationInterface NSXPCConnection cycle; 0 Rasc leaks; open FDs constant at 47`.
