# Everyday Efficiency Evaluation (`perf/everyday-efficiency`)

Reproducible Release-build resource and responsiveness evaluation for Rasc across startup, steady idle (Voice Off / Voice On / Single-Modifier Shortcut active), active Scratchpad/Home/Search/Batch workflows, local Voice Capture & Dictate, on-device Apple Foundation Models Refine, sleep/wake/memory-pressure reclamation, compressed workday endurance (`~4 min`, `n=3` replications), Sparkle + Library Load Constraints distribution verification, and non-blocking long-running soak / 24h idle monitoring.

## Directory Layout

- [scripts/sampler.py](scripts/sampler.py) — External macOS sampler using `proc_pid_rusage(..., RUSAGE_INFO_V6)` + `mach_timebase_info()`, streaming line-flushed CSV output, wall-clock sleep-gap detection, `detect_screen_locked()`, periodic `footprint`/`vmmap`/`leaks`/`lsof`/`ps` diagnostics, and graceful `SIGINT`/`SIGTERM` partial flushes.
- [scripts/run_efficiency_suite.py](scripts/run_efficiency_suite.py) — Builds both the **unmodified shipping Release** app (standard or `--sparkle-distribution` with `cdhash`-pinned Library Load Constraints) and the **opt-in benchmark Release** app (`-DRASC_EFFICIENCY_BENCHMARK` for `--run-efficiency-bench`) in an isolated App Sandbox container (`com.rafaeltorres.rasc.efficiency`), supports `--replications N` and `--audit-only`, and verifies before/after that neither personal SQLite database is touched.
- [scripts/run_long_running.py](scripts/run_long_running.py) — Non-blocking long-running orchestrator (`start`, `status`, `stop`, `summarize`) for `soak-8h` (`--run-soak-bench`), `idle-24h-voice-on`, and chained `full-32h` in isolated container `com.rafaeltorres.rasc.longrun` with detached execution, optional `caffeinate -i -s` guard (`--prevent-idle-sleep`), live JSON telemetry, and clean `SIGTERM` stop.
- [scripts/summarize_results.py](scripts/summarize_results.py) — Generates [results/comparison.json](results/comparison.json) and the `rasc-web` dataset [docs/evidence/efficiency-web-data.json](../../docs/evidence/efficiency-web-data.json).
- [results/baseline/](results/baseline/) — Baseline Release results (`main @ 1cee496`) before optimizations.
- [results/optimized/](results/optimized/) — Updated `n=3` Release replications (`rep_1..rep_3`, `replications.json`) and representative `report.json` (`rep_1`).
- [results/sparkle_distribution.json](results/sparkle_distribution.json) — Sanitized Sparkle + Library Load Constraints bundle, entitlement, launch, and idle audit.
- [results/long_running_smoke/](results/long_running_smoke/) — Sanitized summaries from the completed `soak-8h` (`150 s`) and detached + stopped `idle-24h-voice-on` smoke tests.
- [METHODOLOGY.md](METHODOLOGY.md) — Hardware, software versions, metric definitions, and measurement boundaries.

## Reproducing Locally

Prerequisites: Xcode 26.2+, macOS 26+, Python 3, resolved SPM checkouts in `.derivedData/Rasc/SourcePackages`, and the pinned `Fluid Speech Pro` model (`3b9d38a93d606f84011e5a0a669b7ea146375a22`) installed in Rasc's Application Support or Container folder.

```sh
# 1. Re-run controlled Release suite across n=3 replications (no personal data touched)
python3 Experiments/Efficiency/scripts/run_efficiency_suite.py --label optimized --replications 3

# 2. Audit Sparkle distribution + Library Load Constraints (isolated container)
python3 Experiments/Efficiency/scripts/run_efficiency_suite.py --label sparkle_distribution --sparkle-distribution --audit-only --output /tmp/rasc-sparkle-audit

# 3. Start / monitor / stop / summarize a detached 8h soak + 24h Voice-On idle run
python3 Experiments/Efficiency/scripts/run_long_running.py start --profile full-32h --detach --prevent-idle-sleep
python3 Experiments/Efficiency/scripts/run_long_running.py status
python3 Experiments/Efficiency/scripts/run_long_running.py stop
python3 Experiments/Efficiency/scripts/run_long_running.py summarize

# 4. Regenerate comparison.json and docs/evidence/efficiency-web-data.json
python3 Experiments/Efficiency/scripts/summarize_results.py
```

Read [METHODOLOGY.md](METHODOLOGY.md) and [docs/performance/EVERYDAY-EFFICIENCY.md](../../docs/performance/EVERYDAY-EFFICIENCY.md) for the full analysis, scopes, and limitations.