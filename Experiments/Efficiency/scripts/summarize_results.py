#!/usr/bin/env python3
"""Compare baseline vs optimized Release efficiency results and generate rasc-web dataset."""
from __future__ import annotations

import argparse
import csv
import json
from pathlib import Path
from typing import Any

ROOT = Path(__file__).resolve().parents[3]


def delta_entry(before: float, after: float, unit: str) -> dict[str, Any]:
    diff = round(after - before, 4)
    pct = round(((after - before) / before) * 100.0, 2) if before else None
    return {
        "before": round(before, 4),
        "after": round(after, 4),
        "delta": diff,
        "delta_pct": pct,
        "unit": unit,
    }


def downsample_timeseries(csv_path: Path, max_points: int = 160) -> list[dict[str, Any]]:
    rows = list(csv.DictReader(csv_path.open()))
    if not rows:
        return []
    step = max(1, len(rows) // max_points)
    out = []
    seen_phases = set()
    for idx, r in enumerate(rows):
        phase = r["phase"]
        is_boundary = phase not in seen_phases
        seen_phases.add(phase)
        if idx % step == 0 or is_boundary or idx == len(rows) - 1:
            out.append({
                "t": round(float(r["elapsed_s"]), 1),
                "phase": phase,
                "footprint_mib": round(int(r["phys_footprint_bytes"]) / (1024 * 1024), 2),
                "rss_mib": round(int(r["resident_size_bytes"]) / (1024 * 1024), 2),
                "neural_mib": round(int(r["neural_footprint_bytes"]) / (1024 * 1024), 2),
                "cpu_pct": round(float(r["cpu_pct"]), 3),
                "idle_wkups_s": round(float(r["idle_wkups_per_s"]), 2),
            })
    return out


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--baseline", type=Path, default=ROOT / "Experiments/Efficiency/results/baseline")
    parser.add_argument("--optimized", type=Path, default=ROOT / "Experiments/Efficiency/results/optimized")
    parser.add_argument("--sparkle-json", type=Path, default=ROOT / "Experiments/Efficiency/results/sparkle_distribution.json")
    parser.add_argument("--long-running-smoke-dir", type=Path, default=ROOT / "Experiments/Efficiency/results/long_running_smoke")
    parser.add_argument("--comparison-out", type=Path, default=ROOT / "Experiments/Efficiency/results/comparison.json")
    parser.add_argument("--web-out", type=Path, default=ROOT / "docs/evidence/efficiency-web-data.json")
    args = parser.parse_args()

    b = json.loads((args.baseline / "report.json").read_text())
    o = json.loads((args.optimized / "report.json").read_text())
    rep_path = args.optimized / "replications.json"
    rep_data = json.loads(rep_path.read_text()) if rep_path.exists() else None
    sparkle_data = json.loads(args.sparkle_json.read_text()) if args.sparkle_json.exists() else None
    long_running_smokes: dict[str, Any] = {}
    if args.long_running_smoke_dir.exists():
        for p in sorted(args.long_running_smoke_dir.glob("*_summary.json")):
            long_running_smokes[p.stem] = json.loads(p.read_text())

    comparison = {
        "baseline_commit": b["environment"]["commit"],
        "optimized_commit": o["environment"]["commit"],
        "optimized_screen_locked": o["environment"].get("screen_locked"),
        "metrics": {
            "app_bundle_mib": delta_entry(
                b["disk_footprint"]["app_bundle"]["app_du_mib"],
                o["disk_footprint"]["app_bundle"]["app_du_mib"],
                "MiB",
            ),
            "launch_time_to_idle_p50_s": delta_entry(
                b["launch"]["time_to_idle_s"]["p50"],
                o["launch"]["time_to_idle_s"]["p50"],
                "s",
            ),
            "launch_settled_footprint_p50_mib": delta_entry(
                b["launch"]["settled_footprint_mib"]["p50"],
                o["launch"]["settled_footprint_mib"]["p50"],
                "MiB",
            ),
            "idle_voice_off_footprint_p50_mib": delta_entry(
                b["idle_voice_off"]["summary"]["phys_footprint_mib"]["p50"],
                o["idle_voice_off"]["summary"]["phys_footprint_mib"]["p50"],
                "MiB",
            ),
            "idle_voice_off_cpu_mean_pct": delta_entry(
                b["idle_voice_off"]["summary"]["cpu_pct"]["mean"],
                o["idle_voice_off"]["summary"]["cpu_pct"]["mean"],
                "%",
            ),
            "idle_voice_off_wkups_per_s": delta_entry(
                b["idle_voice_off"]["summary"]["pkg_idle_wkups_per_s_mean"],
                o["idle_voice_off"]["summary"]["pkg_idle_wkups_per_s_mean"],
                "/s",
            ),
            "idle_voice_on_footprint_p50_mib": delta_entry(
                b["idle_voice_on"]["summary"]["phys_footprint_mib"]["p50"],
                o["idle_voice_on"]["summary"]["phys_footprint_mib"]["p50"],
                "MiB",
            ),
            "idle_voice_on_cpu_mean_pct": delta_entry(
                b["idle_voice_on"]["summary"]["cpu_pct"]["mean"],
                o["idle_voice_on"]["summary"]["cpu_pct"]["mean"],
                "%",
            ),
            "idle_voice_on_wkups_per_s": delta_entry(
                b["idle_voice_on"]["summary"]["pkg_idle_wkups_per_s_mean"],
                o["idle_voice_on"]["summary"]["pkg_idle_wkups_per_s_mean"],
                "/s",
            ),
            "workday_peak_footprint_mib": delta_entry(
                b["workday"]["overall_sample_summary"]["lifetime_max_phys_footprint_mib"],
                o["workday"]["overall_sample_summary"]["lifetime_max_phys_footprint_mib"],
                "MiB",
            ),
            "workday_cooldown_end_footprint_mib": delta_entry(
                b["workday"]["phase_summaries"].get("post_workload_cooldown", {}).get("phys_footprint_mib", {}).get("end", 0.0),
                o["workday"]["phase_summaries"].get("post_workload_cooldown", {}).get("phys_footprint_mib", {}).get("end", 0.0),
                "MiB",
            ),
            "workday_endurance_slope_mib_per_min": delta_entry(
                b["workday"]["phase_summaries"].get("workday_endurance_loop", {}).get("phys_footprint_mib", {}).get("slope_mib_per_min", 0.0),
                o["workday"]["phase_summaries"].get("workday_endurance_loop", {}).get("phys_footprint_mib", {}).get("slope_mib_per_min", 0.0),
                "MiB/min",
            ),
            "workday_cum_cpu_ms": delta_entry(
                b["workday"]["overall_sample_summary"]["cumulative_cpu_ms"],
                o["workday"]["overall_sample_summary"]["cumulative_cpu_ms"],
                "ms",
            ),
            "workday_xnu_cpu_energy_j": delta_entry(
                b["workday"]["overall_sample_summary"]["xnu_cpu_energy_j"],
                o["workday"]["overall_sample_summary"]["xnu_cpu_energy_j"],
                "J",
            ),
            "workday_cooldown_leaks": delta_entry(
                float(b["workday"]["diagnostics_cooldown"].get("leaks_count", -1)),
                float(o["workday"]["diagnostics_cooldown"].get("leaks_count", -1)),
                "leaks",
            ),
        },
    }
    if rep_data is not None:
        comparison["replications"] = rep_data
    if sparkle_data is not None:
        comparison["sparkle_distribution"] = sparkle_data
    if long_running_smokes:
        comparison["long_running_smoke"] = long_running_smokes
    args.comparison_out.write_text(json.dumps(comparison, indent=2))

    # Build curated editorial dataset for rasc-web
    opt_phases = o["workday"]["phase_summaries"]
    opt_ops = o["workday"]["in_app_summary"].get("ops", {})
    web_data: dict[str, Any] = {
        "schema_version": 2,
        "generated_at": o["generated_at"],
        "environment": o["environment"],
        "scope": {
            "hardware": o["environment"]["machine_cpu"],
            "memory_gb": round(o["environment"]["memory_bytes"] / (1024 ** 3), 1),
            "macos": f"{o['environment']['macos_version']} ({o['environment']['macos_build']})",
            "build_configuration": "Release (App Sandbox enabled, ad-hoc signed; Sparkle + LLC audited separately)",
            "workload_distinction": (
                "Standard accelerated workday suite (~4-5 min) is distinct from the detached long-running "
                "8h soak + 24h Voice-On idle harness; full 8h/24h data is reported separately once completed."
            ),
            "not_measured": [
                "Full-SoC wall power / battery-life hours (sudo powermetrics unavailable without elevated privileges; Xcode Power Profiler does not support macOS)",
                "Other Apple silicon SKUs (8 GB M1/M2/M4), Intel Macs, or macOS 14/15 idle behavior",
                "Continuous network-sync or multi-week hibernation without process restart",
            ],
        },
        "storage_distinction": {
            "app_bundle_mib": o["disk_footprint"]["app_bundle"]["app_du_mib"],
            "app_bundle_bytes": o["disk_footprint"]["app_bundle"]["total_file_bytes"],
            "sparkle_app_bundle_mib": (
                sparkle_data["disk_footprint"]["app_bundle"]["app_du_mib"]
                if sparkle_data
                else None
            ),
            "speech_model_separate_bytes": o["disk_footprint"]["speech_model_bytes"],
            "speech_model_separate_mib": o["disk_footprint"]["speech_model_mib"],
            "note": (
                "Standard local Release Rasc.app does not embed Sparkle or the 622 MiB speech model; "
                "GitHub Release builds embed Sparkle + cdhash-pinned Library Load Constraints (~26 MiB), "
                "and the speech model remains an opt-in one-time download."
            ),
        },
        "states": {
            "idle_voice_off": {
                "phys_footprint_p50_mib": o["idle_voice_off"]["summary"]["phys_footprint_mib"]["p50"],
                "rss_p50_mib": o["idle_voice_off"]["summary"]["rss_mib"]["p50"],
                "cpu_mean_pct": o["idle_voice_off"]["summary"]["cpu_pct"]["mean"],
                "idle_wkups_per_s": o["idle_voice_off"]["summary"]["pkg_idle_wkups_per_s_mean"],
                "xnu_cpu_power_mw": o["idle_voice_off"]["summary"]["xnu_cpu_power_mw_mean"],
                "leaks_count": o["idle_voice_off"]["diagnostics_end"].get("leaks_count"),
            },
            "idle_voice_on": {
                "phys_footprint_p50_mib": o["idle_voice_on"]["summary"]["phys_footprint_mib"]["p50"],
                "rss_p50_mib": o["idle_voice_on"]["summary"]["rss_mib"]["p50"],
                "neural_footprint_p50_mib": o["idle_voice_on"]["summary"]["neural_footprint_mib"]["p50"],
                "cpu_mean_pct": o["idle_voice_on"]["summary"]["cpu_pct"]["mean"],
                "idle_wkups_per_s": o["idle_voice_on"]["summary"]["pkg_idle_wkups_per_s_mean"],
                "xnu_cpu_power_mw": o["idle_voice_on"]["summary"]["xnu_cpu_power_mw_mean"],
                "leaks_count": o["idle_voice_on"]["diagnostics_end"].get("leaks_count"),
            },
            "launch": o["launch"],
            "workday_peak_footprint_mib": o["workday"]["overall_sample_summary"]["lifetime_max_phys_footprint_mib"],
            "workday_endurance_slope_mib_per_min": opt_phases.get("workday_endurance_loop", {}).get("phys_footprint_mib", {}).get("slope_mib_per_min"),
            "workday_cooldown_end_footprint_mib": opt_phases.get("post_workload_cooldown", {}).get("phys_footprint_mib", {}).get("end"),
            "workday_cooldown_cpu_mean_pct": opt_phases.get("post_workload_cooldown", {}).get("cpu_pct", {}).get("mean"),
            "workday_cooldown_leaks": o["workday"]["diagnostics_cooldown"].get("leaks_count"),
        },
        "before_vs_after": comparison["metrics"],
        "workday_phase_bars": [
            {
                "phase": phase,
                "footprint_p50_mib": vals["phys_footprint_mib"]["p50"],
                "footprint_max_mib": vals["phys_footprint_mib"]["max"],
                "cpu_mean_pct": vals["cpu_pct"]["mean"],
                "idle_wkups_per_s": vals["pkg_idle_wkups_per_s_mean"],
                "elapsed_s": vals["elapsed_s"],
            }
            for phase, vals in opt_phases.items()
        ],
        "operation_latencies_ms": opt_ops,
        "workday_timeseries": downsample_timeseries(args.optimized / "workday_timeseries.csv"),
    }
    if rep_data is not None:
        web_data["replications"] = rep_data
    if sparkle_data is not None:
        web_data["sparkle_distribution"] = {
            "disk_footprint": sparkle_data["disk_footprint"],
            "llc_audit": sparkle_data.get("llc_audit"),
            "launch": sparkle_data["launch"],
            "idle_voice_off": sparkle_data["idle_voice_off"]["summary"],
            "idle_voice_on": sparkle_data["idle_voice_on"]["summary"],
        }
    if long_running_smokes:
        web_data["long_running_smoke"] = long_running_smokes
    args.web_out.parent.mkdir(parents=True, exist_ok=True)
    args.web_out.write_text(json.dumps(web_data, indent=2))
    print(f"Wrote {args.comparison_out} and {args.web_out}")


if __name__ == "__main__":
    main()
