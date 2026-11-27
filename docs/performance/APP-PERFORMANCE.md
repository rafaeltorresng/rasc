# Application performance evaluation

**Scope.** Rasc app-level resource use on **Release** builds representative of distribution (`App Sandbox` enabled, no telemetry, no background network). **Not extrapolated** to hardware/OS not tested. **No user data.** Combines controlled `n=3` Release efficiency replications ([EVERYDAY-EFFICIENCY.md](EVERYDAY-EFFICIENCY.md)), Sparkle + Library Load Constraints auditing, and non-blocking long-running smoke harnesses with Round 3 / Round 4 / M13A benchmarks. **Full-SoC wall energy/thermal not measured** (`sudo powermetrics` unavailable; Xcode `Power Profiler` unsupported on macOS) — XNU per-process CPU energy (`ri_energy_nj`) is reported where applicable.

## Environment & Packaging Variants

- `Mac15,6` Apple M3 Pro (11 cores, 18 GiB RAM); macOS `26.5.1` (`25F80`); Xcode `26.2` (`17C52`); Rasc **0.1.16 build 22** (re-verified at `main @ 30c5c14` + `0.1.16-final-rc`, `screen_locked: false`); **Release (`-O`)**.
- **Standard local Release `.app`:** **`40.54 MiB`** (`41,516 KiB` / `42,367,708 B`), ad-hoc signed with `Rasc.entitlements`, no bundled Sparkle.
- **Sparkle distribution Release `.app` (`0.1.16-final-rc`):** **`44.50 MiB`** (`45,908 KiB` / `46,660,045 B`; `13.14 MiB` DMG), embeds `Sparkle.framework` + `libswiftCompatibilitySpan.dylib` pinned via `Has Library Load Constraints` (`arm64 CDHash`), zero `network.client` on main app, isolated `VoiceModelDownloader.xpc`. (`31 MB` footprint / `0.0%` CPU on 15s isolated standby smoke.)
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

- **Multi-hour `20261126-191517-full-32h` results (`Experiments/Efficiency/results/long_running_20261126/`):** Stage 1 `8.00 h` soak completed (`28,801.45 s` wall / `15,594.13 s` active, `15` sleeps, `260` notes, `32` Refine) at **`73.70 MiB` p50** (`73.77 MiB` end, `125.99 MiB` peak, `0.0295%` p50 CPU, `0.0/s` p50 wakeups, `0` Rasc leaks). Stage 2 Voice-On standby captured **`8.50 h`** of `24.0 h` before host stop (`2026-11-27T11:46:05-0300`), settling from `61.88 → 30.94 MiB` (**`33.66 MiB` p50**, `-1.0611 MiB/h` slope, `11.81 MiB` flat `neural_footprint`, **`0.0%` p50 CPU**, **`0.0/s` p50 wakeups**, `1.9586 J` total / `0.06 mW` mean, `0` Rasc leaks). Not extrapolated beyond `8.50 h`.
- **Persistence (`AppReliabilityScaleTests` + `5,000`-note Release scale `scale_1k_5k_final.json` at `30c5c14`):** At `5,000` notes (`1,000` kept), `bootstrap` `6.39 ms`, `fetchMostRecent` **`0.041 ms`**, `search(20)` **`4.48 ms`**, `search(500)` **`6.62 ms`**, `backup` **`6.24 ms`** (`3,227,648 B`), WAL truncate checkpoint `5.00 ms` (`2,282,512 B → 0 B`).
- **Voice lifecycle & Round 5 (`30c5c14`):** Paired M3 Pro Release benchmarks beat built-in `SpeechTranscriber` and local 4-bit `whisper-large-v3-turbo` across VoiceArena (`8.925%` vs `11.456%` / `11.609%`, `p50 65.6 ms`), Round 3 Held (`14.151%`), FLEURS (`4.961%`), and `-20 dBFS` `30s–300s` (`9.605%`). Streaming `VoiceAudio.mono16k()` resamples `300 s @ 48 kHz` (`4,800,000 / 4,800,000` frames) in **`21.66 ms`**, settling at `32.30 MiB` post-release. Warm awake E2E `finish → transcript` `65.55 ms` p50 (`p95 148.10 ms`).
- **Refine (Apple Foundation Models):** On-device `SystemLanguageModel.default` live evals at `30c5c14` reached **`64.9%`** (Val `n=57`, `747 ms` p50) and **`63.9%`** (Holdout `n=72`, `720 ms` p50) vs `54.4%` / `54.2%` `M12B-008`, with **`0` user-visible protected-literal corruptions** and `0.0%` proposal failures. Capture/Keep/Search never depend on Refine.

## Not Measured / Cannot Claim

- **Full-SoC wall power / battery hours / thermal watts:** `sudo powermetrics` requires root and Xcode `Power Profiler` does not run on macOS.
- **Standby beyond `8.50 h`:** Stage 2 (`24.0 h` target) captured `8.50 h` before host stop; no claims beyond `8.50 h` are extrapolated.
- **Other hardware / OS / interactive physical desktop scenarios:** 8 GiB Macs, M1/M2/M4, Intel, macOS 14/15, live third-party hotkeys, physical mic routes, OS TCC prompts, fullscreen Spaces/multi-monitor focus, and VoiceOver traversal.

See [EVERYDAY-EFFICIENCY.md](EVERYDAY-EFFICIENCY.md), [docs/evidence/HANDOFF.md](../evidence/HANDOFF.md), and [Experiments/Efficiency/METHODOLOGY.md](../../Experiments/Efficiency/METHODOLOGY.md) for full details.