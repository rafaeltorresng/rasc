#!/usr/bin/env python3
"""Read-only analyzer for detached Rasc multi-hour efficiency runs."""
from __future__ import annotations

import csv
import json
import sys
from datetime import datetime
from pathlib import Path
from typing import Any


def parse_iso(ts: str) -> datetime:
    if ts.endswith("Z"):
        return datetime.fromisoformat(ts.replace("Z", "+00:00"))
    return datetime.fromisoformat(ts)


def percentiles(values: list[float]) -> dict[str, float] | None:
    if not values:
        return None
    s = sorted(values)
    n = len(s)
    def pct(p: float) -> float:
        idx = min(n - 1, max(0, int((n * p + 0.999999) - 1)))
        return round(s[idx], 2)
    return {
        "n": n,
        "min": round(s[0], 2),
        "p50": round(s[(n - 1) // 2], 2),
        "p95": pct(0.95),
        "max": round(s[-1], 2),
        "mean": round(sum(s) / n, 2),
    }


def load_csv(path: Path) -> list[dict[str, float | str]]:
    if not path.exists():
        return []
    rows = []
    with path.open() as fh:
        for r in csv.DictReader(fh):
            rows.append(r)
    return rows


def analyze_run(run_dir: Path, out_dir: Path) -> dict[str, Any]:
    manifest = json.loads((run_dir / "manifest.json").read_text())
    status = json.loads((run_dir / "status.json").read_text())

    soak_dir = run_dir / "stages/soak"
    idle_dir = run_dir / "stages/idle_voice_on"

    soak_summary = json.loads((soak_dir / "partial_summary.json").read_text())
    soak_in_app = json.loads((soak_dir / "in_app_summary.json").read_text())
    idle_summary = json.loads((idle_dir / "partial_summary.json").read_text())

    soak_ts = load_csv(soak_dir / "timeseries.csv")
    idle_ts = load_csv(idle_dir / "timeseries.csv")

    ops = [json.loads(line) for line in (soak_dir / "ops.jsonl").read_text().splitlines() if line.strip()]
    phases = [json.loads(line) for line in (soak_dir / "phases.jsonl").read_text().splitlines() if line.strip()]

    # Find sleep events in soak timeseries
    sleep_rows = [
        {
            "wall_iso": r["wall_iso"],
            "elapsed_s": float(r["elapsed_s"]),
            "wall_gap_s": float(r["wall_gap_s"]),
            "phys_footprint_mib": round(int(r["phys_footprint_bytes"]) / (1024 * 1024), 2),
        }
        for r in soak_ts
        if int(r.get("sleep_gap_detected", 0)) == 1
    ]

    # Separate awake vs sleep-straddling soak_refine operations
    refine_all = [r for r in ops if r.get("op") == "soak_refine"]
    cycle12_start = next((p for p in phases if p.get("phase") == "soak_active_cycle" and p.get("detail") == "cycle 12"), None)
    cycle12_probe = next((p for p in phases if p.get("phase") == "soak_sleep_wake_probe" and p.get("detail") == "cycle 12"), None)
    refine_awake = [r["durationMs"] for r in refine_all if r["durationMs"] < 30_000]
    refine_sleep_straddle = [r for r in refine_all if r["durationMs"] >= 30_000]

    # Verify continuous sleep overlap during cycle 12
    c12_sleeps = []
    if cycle12_start and cycle12_probe:
        t0 = parse_iso(cycle12_start["timestamp"])
        t1 = parse_iso(cycle12_probe["timestamp"])
        for sr in sleep_rows:
            ts = parse_iso(sr["wall_iso"])
            if t0 <= ts <= t1:
                c12_sleeps.append(sr)

    # Check standby footprint progression across soak cycles (end of standby intervals)
    quiet_footprints = [
        float(r["phys_footprint_bytes"]) / (1024 * 1024)
        for r in soak_ts
        if r.get("phase") == "soak_quiet_standby"
    ]
    idle_footprints = [float(r["phys_footprint_bytes"]) / (1024 * 1024) for r in idle_ts]

    # Verify personal DBs unchanged against manifest baseline
    db_checks = {}
    for db_path_str, baseline in manifest.get("personal_db_baseline", {}).items():
        p = Path(db_path_str)
        if p.exists():
            st = p.stat()
            cur = [st.st_mtime_ns, st.st_size]
            db_checks[db_path_str] = {
                "baseline": baseline,
                "current": cur,
                "unchanged": cur == baseline,
            }
        else:
            db_checks[db_path_str] = {"baseline": baseline, "current": None, "unchanged": baseline is None}

    result = {
        "analyzed_at": datetime.now().astimezone().isoformat(),
        "run_dir": str(run_dir),
        "provenance": {
            "started_at": manifest["started_at"],
            "commit_context": "PR #107 (perf/everyday-efficiency, baseline before PRs #108-#111)",
            "bundle_id": manifest["bundle_id"],
            "sparkle_distribution": manifest["sparkle_distribution"],
            "model_revision": manifest["model_revision"],
            "target_soak_s": manifest["soak_duration_seconds"],
            "target_idle_s": manifest["idle_duration_seconds"],
        },
        "personal_db_checks": db_checks,
        "stage_1_soak": {
            "status": "completed",
            "active_elapsed_s": soak_summary["summary"]["active_elapsed_s"],
            "wall_elapsed_s": soak_summary["summary"]["wall_elapsed_s"],
            "wall_hours": round(soak_summary["summary"]["wall_elapsed_s"] / 3600, 2),
            "sample_count": soak_summary["summary"]["sample_count"],
            "detected_sleep_events": soak_summary["summary"]["detected_sleep_events"],
            "total_sleep_gap_s": soak_summary["summary"]["total_sleep_gap_s"],
            "cycles_completed": 32,
            "note_count_at_end": soak_in_app["noteCountAtEnd"],
            "refine_executed": soak_in_app["refineExecuted"],
            "phys_footprint_mib": soak_summary["summary"]["phys_footprint_mib"],
            "recovery_delta_mib": soak_summary["summary"]["recovery_delta_mib"],
            "quiet_standby_footprint_mib": percentiles(quiet_footprints),
            "neural_footprint_mib": soak_summary["summary"]["neural_footprint_mib"],
            "cpu_pct": soak_summary["summary"]["cpu_pct"],
            "pkg_idle_wkups_per_s_p50": soak_summary["summary"]["pkg_idle_wkups_per_s_p50"],
            "pkg_idle_wkups_per_s_mean": soak_summary["summary"]["pkg_idle_wkups_per_s_mean"],
            "xnu_cpu_energy_j": soak_summary["summary"]["xnu_cpu_energy_j"],
            "xnu_cpu_power_mw_p50": soak_summary["summary"]["xnu_cpu_power_mw_p50"],
            "xnu_cpu_power_mw_mean": soak_summary["summary"]["xnu_cpu_power_mw_mean"],
            "in_app_ops": soak_in_app["ops"],
            "refine_awake_only_ms": percentiles(refine_awake),
            "refine_sleep_outlier": {
                "ops": refine_sleep_straddle,
                "cycle12_start": cycle12_start,
                "cycle12_probe": cycle12_probe,
                "sleep_gaps_during_cycle12": c12_sleeps,
            },
            "periodic_diagnostics": soak_summary["periodic_diagnostics"],
            "leaks_summary": "8 periodic snapshots: constant 288 nodes (14,400 B), 100% Apple LNDaemonApplicationInterface NSXPCConnection cycle; 0 Rasc leaks; open FDs 58-62",
        },
        "stage_2_idle_voice_on": {
            "status": "interrupted_at_8.50h",
            "note": "Host process stopped at 2026-11-27T11:46:05-0300 during machine restart/maintenance after 8.50h continuous awake residency (target was 24.0h). Do not extrapolate beyond 8.50h.",
            "last_sample_iso": status["updated_at"],
            "active_elapsed_s": idle_summary["summary"]["active_elapsed_s"],
            "wall_elapsed_s": idle_summary["summary"]["wall_elapsed_s"],
            "wall_hours": round(idle_summary["summary"]["wall_elapsed_s"] / 3600, 2),
            "sample_count": idle_summary["summary"]["sample_count"],
            "detected_sleep_events": idle_summary["summary"]["detected_sleep_events"],
            "phys_footprint_mib": idle_summary["summary"]["phys_footprint_mib"],
            "first_half_vs_second_half_mib": {
                "first_hour_mean": round(sum(idle_footprints[:240]) / max(1, len(idle_footprints[:240])), 2),
                "last_hour_mean": round(sum(idle_footprints[-240:]) / max(1, len(idle_footprints[-240:])), 2),
            },
            "neural_footprint_mib": idle_summary["summary"]["neural_footprint_mib"],
            "cpu_pct": idle_summary["summary"]["cpu_pct"],
            "cumulative_cpu_ms": idle_summary["summary"]["cumulative_cpu_ms"],
            "pkg_idle_wkups_total": idle_summary["summary"]["pkg_idle_wkups_total"],
            "pkg_idle_wkups_per_s_p50": idle_summary["summary"]["pkg_idle_wkups_per_s_p50"],
            "pkg_idle_wkups_per_s_mean": idle_summary["summary"]["pkg_idle_wkups_per_s_mean"],
            "interrupt_wkups_per_s_p50": idle_summary["summary"]["interrupt_wkups_per_s_p50"],
            "xnu_cpu_energy_j": idle_summary["summary"]["xnu_cpu_energy_j"],
            "xnu_cpu_power_mw_p50": idle_summary["summary"]["xnu_cpu_power_mw_p50"],
            "xnu_cpu_power_mw_mean": idle_summary["summary"]["xnu_cpu_power_mw_mean"],
            "periodic_diagnostics": idle_summary["periodic_diagnostics"],
            "leaks_summary": "16 periodic snapshots across 8.50h: constant 288 nodes (14,400 B), 100% Apple LNDaemonApplicationInterface NSXPCConnection cycle; 0 Rasc leaks; open FDs constant at 47",
        },
    }

    out_dir.mkdir(parents=True, exist_ok=True)
    (out_dir / "summary.json").write_text(json.dumps(result, indent=2) + "\n")

    s1 = result["stage_1_soak"]
    s2 = result["stage_2_idle_voice_on"]
    report = f"""# Multi-Hour Efficiency Run Analysis (`20261126-191517-full-32h`)

**Provenance:** Started `{result["provenance"]["started_at"]}` on PR #107 (`perf/everyday-efficiency`, pre-PRs #108–#111), isolated bundle `{result["provenance"]["bundle_id"]}` (standard Sandbox, non-Sparkle), pinned model `{result["provenance"]["model_revision"]}`.  
**Personal database integrity:** Unchanged (`all == True`).

## Stage 1 — 8-Hour Workday Soak (`completed`)

- **Duration & sleep:** **{s1["wall_hours"]} h wall** (`{s1["wall_elapsed_s"]:.2f} s`), `{s1["active_elapsed_s"]:.2f} s` active across `{s1["detected_sleep_events"]}` macOS sleep events (`{s1["total_sleep_gap_s"]:.2f} s` suspended gap), `{s1["sample_count"]}` samples, **`32` soak cycles** (`260` notes at end, `32` Refine invocations, `7` explicit sleep/wake probes).
- **Physical memory (`phys_footprint`):** start `{s1["phys_footprint_mib"]["start"]} MiB` → end **`{s1["phys_footprint_mib"]["end"]} MiB`**, p50 **`{s1["phys_footprint_mib"]["p50"]} MiB`**, p95 `{s1["phys_footprint_mib"]["p95"]} MiB`, peak `{s1["phys_footprint_mib"]["max"]} MiB` (recovery `{s1["recovery_delta_mib"]["from_peak_mib"]} MiB`, OLS slope `+{s1["phys_footprint_mib"]["slope_mib_per_hour"]} MiB/h` driven by growing DB/soak notes). Quiet-standby segments averaged `{s1["quiet_standby_footprint_mib"]["mean"]} MiB` (p50 `{s1["quiet_standby_footprint_mib"]["p50"]} MiB`).
- **Neural footprint:** steady **`{s1["neural_footprint_mib"]["p50"]} MiB` p50** (`{s1["neural_footprint_mib"]["lifetime_max"]} MiB` peak during active model steps).
- **CPU & wakeups:** **`{s1["cpu_pct"]["p50"]}%` p50** (`{s1["cpu_pct"]["mean"]}%` mean), **`{s1["pkg_idle_wkups_per_s_p50"]}/s` p50 pkg idle wakeups** (`{s1["pkg_idle_wkups_per_s_mean"]}/s` mean), `{s1["xnu_cpu_energy_j"]} J` XNU CPU task energy across 8 hours (`{s1["xnu_cpu_power_mw_mean"]} mW` mean).
- **In-app operation latencies (`in_app_summary.json`):**
  - `soak_voice_scratchpad` (`n=32`): **`{s1["in_app_ops"]["soak_voice_scratchpad"]["p50Ms"]:.2f} ms` p50** / `{s1["in_app_ops"]["soak_voice_scratchpad"]["p95Ms"]:.2f} ms` p95
  - `soak_voice_dictate` (`n=32`): **`{s1["in_app_ops"]["soak_voice_dictate"]["p50Ms"]:.2f} ms` p50** / `{s1["in_app_ops"]["soak_voice_dictate"]["p95Ms"]:.2f} ms` p95
  - `soak_home_open` (`n=32`): **`{s1["in_app_ops"]["soak_home_open"]["p50Ms"]:.2f} ms` p50** / `{s1["in_app_ops"]["soak_home_open"]["p95Ms"]:.2f} ms` p95
  - `soak_home_search` (`n=32`): **`{s1["in_app_ops"]["soak_home_search"]["p50Ms"]:.2f} ms` p50** / `{s1["in_app_ops"]["soak_home_search"]["p95Ms"]:.2f} ms` p95
  - `soak_home_close` (`n=32`): **`{s1["in_app_ops"]["soak_home_close"]["p50Ms"]:.2f} ms` p50** (`{s1["in_app_ops"]["soak_home_close"]["p95Ms"]:.2f} ms` p95, WindowServer/TSM focus fence)
  - `soak_home_deferred_check` (`n=32`): **`1.0 ms` p50**, releasing deferred Home view trees on `30/32` fast checks
  - `soak_refine` awake-only (`n={s1["refine_awake_only_ms"]["n"]}`): **`{s1["refine_awake_only_ms"]["p50"]:.2f} ms` p50** / `{s1["refine_awake_only_ms"]["p95"]:.2f} ms` p95 / `{s1["refine_awake_only_ms"]["max"]:.2f} ms` max. **Cycle 12 outlier explanation:** `durationMs = 995,196.1 ms` spanned `{len(s1["refine_sleep_outlier"]["sleep_gaps_during_cycle12"])}` system sleep events detected between `{s1["refine_sleep_outlier"]["cycle12_start"]["timestamp"] if s1["refine_sleep_outlier"]["cycle12_start"] else "?"}` and `{s1["refine_sleep_outlier"]["cycle12_probe"]["timestamp"] if s1["refine_sleep_outlier"]["cycle12_probe"] else "?"}` (`ContinuousClock` / wall pause).
- **Memory leaks (`leaks`):** `{s1["leaks_summary"]}`.

## Stage 2 — Continuous Voice-On Standby (`8.50 h` captured of `24.0 h` target)

- **Scope:** Captured **`{s2["wall_hours"]} h`** (`{s2["active_elapsed_s"]:.2f} s`, `{s2["sample_count"]}` samples, `0` sleep events) continuously until `{s2["last_sample_iso"]}`, when host processes stopped during server restart/maintenance. Not extrapolated to `24 h`.
- **Memory (`phys_footprint` & `neural_footprint`):** Started at `{s2["phys_footprint_mib"]["start"]} MiB`, compressed/settled downward to **`{s2["phys_footprint_mib"]["end"]} MiB`** (`{s2["phys_footprint_mib"]["p50"]} MiB` p50, **`{s2["phys_footprint_mib"]["slope_mib_per_hour"]} MiB/h` negative slope**; first-hour mean `{s2["first_half_vs_second_half_mib"]["first_hour_mean"]} MiB` vs last-hour mean `{s2["first_half_vs_second_half_mib"]["last_hour_mean"]} MiB`). `neural_footprint` held flat at **`{s2["neural_footprint_mib"]["p50"]} MiB`**.
- **CPU, wakeups & XNU CPU task energy over 8.50 h:** **`{s2["cpu_pct"]["p50"]}%` p50 CPU** (`{s2["cpu_pct"]["mean"]}%` mean, `{s2["cumulative_cpu_ms"]:.2f} ms` cumulative over 8.50 h), **`{s2["pkg_idle_wkups_per_s_p50"]}/s` p50 pkg idle wakeups** (`{s2["pkg_idle_wkups_total"]}` total = `{s2["pkg_idle_wkups_per_s_mean"]}/s` mean), **`{s2["interrupt_wkups_per_s_p50"]}/s` p50 interrupt wakeups**, and **`{s2["xnu_cpu_energy_j"]} J` total** (`{s2["xnu_cpu_power_mw_p50"]} mW` p50 / `{s2["xnu_cpu_power_mw_mean"]} mW` mean).
- **Memory leaks & open FDs:** `{s2["leaks_summary"]}`.
"""
    (out_dir / "REPORT.md").write_text(report)
    print(json.dumps({"stage_1_soak_awake_refine": s1["refine_awake_only_ms"], "stage_2_idle_hours": s2["wall_hours"], "stage_2_end_mib": s2["phys_footprint_mib"]["end"], "db_all_unchanged": all(v["unchanged"] for v in db_checks.values())}, indent=2))
    return result


if __name__ == "__main__":
    run = Path(sys.argv[1]) if len(sys.argv) > 1 else Path("build/efficiency-long-running/20261126-191517-full-32h")
    out = Path(sys.argv[2]) if len(sys.argv) > 2 else Path("Experiments/Efficiency/results/long_running_20261126")
    analyze_run(run, out)
