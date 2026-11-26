# Everyday Efficiency Evaluation (`perf/everyday-efficiency`)

Reproducible Release-build resource and responsiveness evaluation for Rasc across startup, steady idle (Voice Off / Voice On / Single-Modifier Shortcut active), active Scratchpad/Home/Search/Batch workflows, local Voice Capture & Dictate, on-device Apple Foundation Models Refine, sleep/wake/memory-pressure reclamation, and compressed workday endurance.

## Directory Layout

- `scripts/sampler.py` — External macOS sampler using `proc_pid_rusage(..., RUSAGE_INFO_V6)` + `mach_timebase_info()`, `footprint`, `vmmap --summary`, `leaks`, `lsof`, and `ps`.
- `scripts/run_efficiency_suite.py` — Builds both the **unmodified shipping Release** app (for launch and idle windows) and the **opt-in benchmark Release** app (`-DRASC_EFFICIENCY_BENCHMARK` for the 8-phase workday endurance loop) in an isolated App Sandbox container (`com.rafaeltorres.rasc.efficiency`), verifying before and after that neither personal SQLite database is touched.
- `scripts/summarize_results.py` — Generates `results/comparison.json` and the `rasc-web`-ready dataset [docs/evidence/efficiency-web-data.json](../../docs/evidence/efficiency-web-data.json).
- `results/baseline/` — Raw Release CSVs, `report.json`, and `footprint`/`vmmap`/`leaks`/`lsof` diagnostics from `main @ 1cee496` prior to optimizations.
- `results/optimized/` — Identical Release suite run after implementing the grounded efficiency improvements.
- `results/comparison.json` — Machine-readable before/after deltas across all key metrics.
- `METHODOLOGY.md` — Hardware, software versions, metric definitions, and measurement boundaries.

## Reproducing Locally

Prerequisites: Xcode 26.2+, macOS 26+, Python 3, resolved SPM checkouts in `.derivedData/Rasc/SourcePackages`, and the pinned `Fluid Speech Pro` model (`3b9d38a93d606f84011e5a0a669b7ea146375a22`) installed in Rasc's Application Support or Container folder.

```sh
# 1. Re-run the full Release efficiency suite into an isolated container (no personal data touched)
python3 Experiments/Efficiency/scripts/run_efficiency_suite.py --label optimized

# 2. Regenerate comparison.json and docs/evidence/efficiency-web-data.json
python3 Experiments/Efficiency/scripts/summarize_results.py
```

Read [METHODOLOGY.md](METHODOLOGY.md) and [docs/performance/EVERYDAY-EFFICIENCY.md](../../docs/performance/EVERYDAY-EFFICIENCY.md) for the full analysis, scopes, and limitations.
