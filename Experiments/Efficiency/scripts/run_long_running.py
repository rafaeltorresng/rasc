#!/usr/bin/env python3
"""Reproducible, non-blocking long-running soak and 24h idle runner for Rasc Release builds."""
from __future__ import annotations

import argparse
import csv
import json
import os
import shutil
import signal
import subprocess
import sys
import threading
import time
from pathlib import Path
from typing import Any

SCRIPT_DIR = Path(__file__).resolve().parent
if str(SCRIPT_DIR) not in sys.path:
    sys.path.insert(0, str(SCRIPT_DIR))

from run_efficiency_suite import (  # noqa: E402
    MODEL_REV,
    build_release_app,
    build_sparkle_release_app,
    container_dir,
    find_voice_model_source,
    snapshot_personal_dbs,
    stage_bench_fixtures,
    stage_voice_model,
    terminate_process,
    verify_personal_dbs_unchanged,
    wait_for_rusage,
    write_container_prefs,
)
from sampler import (  # noqa: E402
    atomic_write_json,
    detect_screen_locked,
    pid_exists,
    sample_process,
    summarize_samples,
)

ROOT = Path(__file__).resolve().parents[3]
LONGRUN_BUNDLE_ID = "com.rafaeltorres.rasc.longrun"
DEFAULT_BASE_DIR = ROOT / "build/efficiency-long-running"


def resolve_run_dir(run_dir: Path | None) -> Path:
    if run_dir is not None:
        return run_dir.resolve()
    if not DEFAULT_BASE_DIR.exists():
        raise FileNotFoundError(f"No long-running runs directory at {DEFAULT_BASE_DIR}")
    candidates = sorted(
        [p for p in DEFAULT_BASE_DIR.iterdir() if p.is_dir() and (p / "manifest.json").exists()],
        key=lambda p: p.name,
        reverse=True,
    )
    if not candidates:
        raise FileNotFoundError(f"No run found under {DEFAULT_BASE_DIR}")
    return candidates[0]


def stage_app_copy(src_app: Path, dst_app: Path, bundle_id: str, sparkle: bool) -> Path:
    if dst_app.exists():
        shutil.rmtree(dst_app)
    dst_app.parent.mkdir(parents=True, exist_ok=True)
    subprocess.run(["ditto", str(src_app), str(dst_app)], check=True)
    subprocess.run(
        [
            "/usr/libexec/PlistBuddy",
            "-c",
            f"Set :CFBundleIdentifier {bundle_id}",
            str(dst_app / "Contents/Info.plist"),
        ],
        check=True,
    )
    if not sparkle:
        subprocess.run(
            [
                "codesign",
                "--force",
                "--sign",
                "-",
                "--options",
                "runtime",
                "--entitlements",
                str(ROOT / "Rasc/Rasc.entitlements"),
                "--generate-entitlement-der",
                str(dst_app),
            ],
            check=True,
            capture_output=True,
        )
    subprocess.run(
        ["codesign", "--verify", "--deep", "--strict", str(dst_app)],
        check=True,
        capture_output=True,
    )
    return dst_app


def prepare_apps_and_container(
    run_dir: Path,
    profile: str,
    shipping_app: Path | None,
    bench_app: Path | None,
    sparkle_distribution: bool,
) -> dict[str, str]:
    apps_dir = run_dir / "apps"
    apps_dir.mkdir(parents=True, exist_ok=True)
    result: dict[str, str] = {}

    if profile in ("idle-24h-voice-on", "full-32h"):
        staged_shipping = apps_dir / "Shipping/Rasc.app"
        if shipping_app:
            if sparkle_distribution:
                # Caller provided already Sparkle-signed bundle? Re-verify strict signature without stripping LLC unless bundle id differs.
                current_bid = subprocess.check_output(
                    ["/usr/libexec/PlistBuddy", "-c", "Print :CFBundleIdentifier", str(shipping_app / "Contents/Info.plist")],
                    text=True,
                ).strip()
                if current_bid != LONGRUN_BUNDLE_ID:
                    raise ValueError(
                        f"--shipping-app with --sparkle-distribution must already target {LONGRUN_BUNDLE_ID} (got {current_bid})"
                    )
                stage_app_copy(shipping_app, staged_shipping, LONGRUN_BUNDLE_ID, sparkle=True)
            else:
                stage_app_copy(shipping_app, staged_shipping, LONGRUN_BUNDLE_ID, sparkle=False)
        else:
            derived = ROOT / ".derivedData/Rasc"
            if sparkle_distribution:
                build_sparkle_release_app(derived, staged_shipping, LONGRUN_BUNDLE_ID)
            else:
                build_release_app(derived, staged_shipping, LONGRUN_BUNDLE_ID)
        result["shipping_app"] = str(staged_shipping)

    if profile in ("soak-8h", "full-32h"):
        staged_bench = apps_dir / "Bench/Rasc.app"
        if bench_app:
            stage_app_copy(bench_app, staged_bench, LONGRUN_BUNDLE_ID, sparkle=False)
        else:
            bench_derived = ROOT / ".derivedData/RascEfficiencyBench"
            build_release_app(
                bench_derived,
                staged_bench,
                LONGRUN_BUNDLE_ID,
                extra_swift_flags="-DRASC_EFFICIENCY_BENCHMARK",
            )
        result["bench_app"] = str(staged_bench)

    cdir = container_dir(LONGRUN_BUNDLE_ID)
    for sub in [cdir / "Library/Application Support/Rasc", cdir / "Library/Caches"]:
        if sub.exists():
            shutil.rmtree(sub, ignore_errors=True)

    model_src = find_voice_model_source()
    stage_voice_model(LONGRUN_BUNDLE_ID, model_src)
    stage_bench_fixtures(LONGRUN_BUNDLE_ID)
    write_container_prefs(
        LONGRUN_BUNDLE_ID,
        {
            "onboardingCompleted": True,
            "onboardingStep": 5,
            "voiceCaptureEnabled": True,
        },
    )
    return result


def read_csv_rows(csv_path: Path) -> list[dict[str, Any]]:
    if not csv_path.exists():
        return []
    rows: list[dict[str, Any]] = []
    with csv_path.open() as f:
        for r in csv.DictReader(f):
            typed: dict[str, Any] = {}
            for k, v in r.items():
                if k in ("wall_iso", "phase"):
                    typed[k] = v
                else:
                    try:
                        typed[k] = float(v) if "." in v else int(v)
                    except ValueError:
                        typed[k] = v
            rows.append(typed)
    return rows


def compute_run_summary(run_dir: Path) -> dict[str, Any]:
    manifest = json.loads((run_dir / "manifest.json").read_text())
    personal_before = manifest.get("personal_db_baseline", {})
    personal_after = snapshot_personal_dbs()
    personal_ok = personal_before == personal_after

    stages_out: dict[str, Any] = {}
    for stage_dir in sorted((run_dir / "stages").iterdir() if (run_dir / "stages").exists() else []):
        if not stage_dir.is_dir():
            continue
        csv_path = stage_dir / "timeseries.csv"
        rows = read_csv_rows(csv_path)
        sample_summary = summarize_samples(rows, stage_dir.name) if rows else {"sample_count": 0}
        in_app_path = stage_dir / "in_app_summary.json"
        partial_in_app_path = stage_dir / "in_app_partial_summary.json"
        in_app = {}
        if in_app_path.exists():
            in_app = json.loads(in_app_path.read_text())
        elif partial_in_app_path.exists():
            in_app = json.loads(partial_in_app_path.read_text())

        diag_files = sorted(stage_dir.glob("diagnostics/*_leaks.txt"))
        latest_leaks: dict[str, Any] = {}
        if diag_files:
            txt = diag_files[-1].read_text()
            import re

            ml = re.search(r"Process \d+:\s+(\d+)\s+leaks?\s+for\s+(\d+)\s+total leaked bytes", txt)
            if ml:
                latest_leaks = {
                    "file": diag_files[-1].name,
                    "leaks_count": int(ml.group(1)),
                    "leaks_bytes": int(ml.group(2)),
                }

        stages_out[stage_dir.name] = {
            "sample_summary": sample_summary,
            "in_app_summary": in_app,
            "latest_leaks": latest_leaks,
        }

    status = json.loads((run_dir / "status.json").read_text()) if (run_dir / "status.json").exists() else {}
    summary = {
        "run_dir": str(run_dir),
        "profile": manifest["profile"],
        "generated_at": time.strftime("%Y-%m-%dT%H:%M:%S%z"),
        "manifest": manifest,
        "status": status,
        "personal_db_unchanged": personal_ok,
        "stages": stages_out,
    }
    atomic_write_json(run_dir / "summary.json", summary)

    md_lines = [
        f"# Long-Running Validation Summary ({manifest['profile']})",
        "",
        f"- **Run directory:** `{run_dir}`",
        f"- **Status:** `{status.get('state', 'unknown')}` (screen locked at start: `{manifest.get('screen_locked_at_start')}`)",
        f"- **Bundle ID (isolated):** `{LONGRUN_BUNDLE_ID}` (`personal_db_unchanged={personal_ok}`)",
        "",
    ]
    for st_name, st_val in stages_out.items():
        s = st_val["sample_summary"]
        fp = s.get("phys_footprint_mib", {})
        rss = s.get("rss_mib", {})
        nf = s.get("neural_footprint_mib", {})
        cpu = s.get("cpu_pct", {})
        md_lines.extend(
            [
                f"## Stage `{st_name}`",
                f"- Samples: {s.get('sample_count', 0)} | Active elapsed: {s.get('active_elapsed_s', 0)}s | Wall elapsed: {s.get('wall_elapsed_s', 0)}s | Sleep gaps: {s.get('detected_sleep_events', 0)} ({s.get('total_sleep_gap_s', 0)}s)",
                f"- Phys footprint (MiB): start={fp.get('start')} end={fp.get('end')} p50={fp.get('p50')} p95={fp.get('p95')} max={fp.get('max')} slope={fp.get('slope_mib_per_hour')} MiB/h recovery_from_peak={s.get('recovery_delta_mib', {}).get('from_peak_mib')} MiB",
                f"- RSS p50={rss.get('p50')} MiB (max={rss.get('max')} MiB) | Neural p50={nf.get('p50')} MiB (max={nf.get('max')} MiB)",
                f"- CPU mean={cpu.get('mean')}% | Idle wakeups/s={s.get('pkg_idle_wkups_per_s_mean')} | XNU CPU energy={s.get('xnu_cpu_energy_j')} J",
                f"- Disk read={s.get('disk_read_mib')} MiB | Disk written={s.get('disk_written_mib')} MiB | Logical writes={s.get('logical_writes_mib')} MiB",
                "",
            ]
        )
    (run_dir / "SUMMARY.md").write_text("\n".join(md_lines))
    return summary


def run_worker(run_dir: Path) -> int:
    manifest = json.loads((run_dir / "manifest.json").read_text())
    personal_before = manifest["personal_db_baseline"]
    stop_event = threading.Event()
    child_proc: subprocess.Popen[Any] | None = None
    caff_proc: subprocess.Popen[Any] | None = None

    pid_file = run_dir / "supervisor.pid"
    pid_file.write_text(str(os.getpid()))

    def on_sig(_signum: int, _frame: Any) -> None:
        stop_event.set()
        if child_proc is not None and child_proc.poll() is None:
            try:
                child_proc.send_signal(signal.SIGTERM)
            except OSError:
                pass

    signal.signal(signal.SIGTERM, on_sig)
    signal.signal(signal.SIGINT, on_sig)

    if manifest.get("prevent_idle_sleep"):
        caff_proc = subprocess.Popen(
            ["caffeinate", "-i", "-s", "-w", str(os.getpid())],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )

    stages_plan: list[tuple[str, str, list[str], float, float]] = []
    soak_dur = float(manifest["soak_duration_seconds"])
    idle_dur = float(manifest["idle_duration_seconds"])
    cycle_int = float(manifest["cycle_interval_seconds"])
    cooldown_dur = float(manifest["cooldown_seconds"])
    sample_soak = float(manifest["sample_interval_soak_s"])
    sample_idle = float(manifest["sample_interval_idle_s"])
    diag_interval = float(manifest["diag_interval_seconds"])

    if manifest["profile"] in ("soak-8h", "full-32h"):
        bench_bin = Path(manifest["apps"]["bench_app"]) / "Contents/MacOS/Rasc"
        stages_plan.append(
            (
                "soak",
                str(bench_bin),
                [
                    "--run-soak-bench",
                    "--soak-duration-seconds",
                    str(soak_dur),
                    "--soak-cycle-interval-seconds",
                    str(cycle_int),
                    "--soak-cooldown-seconds",
                    str(cooldown_dur),
                ],
                soak_dur + 300.0,
                sample_soak,
            )
        )
    if manifest["profile"] in ("idle-24h-voice-on", "full-32h"):
        ship_bin = Path(manifest["apps"]["shipping_app"]) / "Contents/MacOS/Rasc"
        stages_plan.append(
            (
                "idle_voice_on",
                str(ship_bin),
                ["-onboardingCompleted", "YES", "-voiceCaptureEnabled", "YES"],
                idle_dur,
                sample_idle,
            )
        )

    status_path = run_dir / "status.json"
    cdir = container_dir(LONGRUN_BUNDLE_ID)
    bench_out = cdir / "Library/Application Support/Rasc/EfficiencyBench/output"

    try:
        for idx, (stage_name, binary, args, max_duration_s, interval_s) in enumerate(stages_plan):
            if stop_event.is_set():
                break
            stage_dir = run_dir / "stages" / stage_name
            stage_dir.mkdir(parents=True, exist_ok=True)
            if stage_name == "soak":
                if bench_out.exists():
                    shutil.rmtree(bench_out)
                bench_out.mkdir(parents=True, exist_ok=True)
                phase_file = bench_out / "phases.jsonl"
            else:
                phase_file = None

            atomic_write_json(
                status_path,
                {
                    "state": "starting_stage",
                    "stage": stage_name,
                    "stage_index": idx + 1,
                    "stage_total": len(stages_plan),
                    "supervisor_pid": os.getpid(),
                    "screen_locked": detect_screen_locked(),
                    "updated_at": time.strftime("%Y-%m-%dT%H:%M:%S%z"),
                },
            )

            stderr_f = (stage_dir / "stderr.log").open("w")
            child_proc = subprocess.Popen(
                [binary, *args],
                stdout=subprocess.DEVNULL,
                stderr=stderr_f,
            )
            try:
                wait_for_rusage(child_proc.pid, timeout_s=15.0)
                if stage_name == "idle_voice_on":
                    # Allow Core ML Speech model warm preparation to settle for 15s (interruptible).
                    stop_event.wait(timeout=min(15.0, max(1.0, max_duration_s * 0.1)))

                sample_process(
                    pid=child_proc.pid,
                    duration_s=max_duration_s,
                    interval_s=interval_s,
                    csv_path=stage_dir / "timeseries.csv",
                    phase_file=phase_file,
                    stop_when_exits=(stage_name == "soak"),
                    diag_dir=stage_dir / "diagnostics",
                    diag_prefix=stage_name,
                    status_path=status_path,
                    partial_summary_path=stage_dir / "partial_summary.json",
                    periodic_diag_interval_s=diag_interval,
                    stop_event=stop_event,
                    status_extra_fn=lambda sn=stage_name, si=idx: {
                        "stage": sn,
                        "stage_index": si + 1,
                        "stage_total": len(stages_plan),
                        "supervisor_pid": os.getpid(),
                        "target_duration_s": soak_dur if sn == "soak" else idle_dur,
                    },
                )
                if child_proc.poll() is None:
                    child_proc.send_signal(signal.SIGTERM)
                try:
                    child_proc.wait(timeout=20.0)
                except subprocess.TimeoutExpired:
                    terminate_process(child_proc)
            finally:
                terminate_process(child_proc)
                stderr_f.close()
                if stage_name == "soak":
                    for src_name, dst_name in [
                        ("phases.jsonl", "phases.jsonl"),
                        ("ops.jsonl", "ops.jsonl"),
                        ("summary.json", "in_app_summary.json"),
                        ("partial_summary.json", "in_app_partial_summary.json"),
                    ]:
                        src = bench_out / src_name
                        if src.exists():
                            shutil.copy2(src, stage_dir / dst_name)
                child_proc = None

        final_state = "stopped" if stop_event.is_set() else "completed"
        atomic_write_json(
            status_path,
            {
                "state": final_state,
                "supervisor_pid": os.getpid(),
                "screen_locked_at_end": detect_screen_locked(),
                "updated_at": time.strftime("%Y-%m-%dT%H:%M:%S%z"),
            },
        )
        compute_run_summary(run_dir)
        verify_personal_dbs_unchanged(personal_before)
        return 0
    finally:
        if caff_proc is not None and caff_proc.poll() is None:
            caff_proc.terminate()
            try:
                caff_proc.wait(timeout=3.0)
            except subprocess.TimeoutExpired:
                caff_proc.kill()
        if personal_before:
            verify_personal_dbs_unchanged(personal_before)


def cmd_start(args: argparse.Namespace) -> int:
    personal_before = snapshot_personal_dbs()
    run_id = time.strftime("%Y%m%d-%H%M%S") + f"-{args.profile}"
    run_dir = (args.run_dir or (DEFAULT_BASE_DIR / run_id)).resolve()
    run_dir.mkdir(parents=True, exist_ok=True)

    apps = prepare_apps_and_container(
        run_dir=run_dir,
        profile=args.profile,
        shipping_app=args.shipping_app,
        bench_app=args.bench_app,
        sparkle_distribution=args.sparkle_distribution,
    )

    default_soak = 28800.0
    default_idle = 86400.0
    if args.duration_seconds is not None:
        if args.profile == "soak-8h":
            default_soak = float(args.duration_seconds)
        elif args.profile == "idle-24h-voice-on":
            default_idle = float(args.duration_seconds)
        else:
            default_soak = float(args.duration_seconds) / 2.0
            default_idle = float(args.duration_seconds) / 2.0

    manifest = {
        "profile": args.profile,
        "started_at": time.strftime("%Y-%m-%dT%H:%M:%S%z"),
        "bundle_id": LONGRUN_BUNDLE_ID,
        "sparkle_distribution": bool(args.sparkle_distribution),
        "prevent_idle_sleep": bool(args.prevent_idle_sleep),
        "screen_locked_at_start": detect_screen_locked(),
        "soak_duration_seconds": default_soak,
        "idle_duration_seconds": default_idle,
        "cycle_interval_seconds": float(args.cycle_interval_seconds),
        "cooldown_seconds": float(args.cooldown_seconds),
        "sample_interval_soak_s": float(args.sample_interval_seconds or 5.0),
        "sample_interval_idle_s": float(args.sample_interval_seconds or 15.0),
        "diag_interval_seconds": float(args.diag_interval_seconds),
        "apps": apps,
        "model_revision": MODEL_REV,
        "personal_db_baseline": personal_before,
    }
    atomic_write_json(run_dir / "manifest.json", manifest)

    if args.detach:
        log_path = run_dir / "supervisor.log"
        log_file = log_path.open("w")
        proc = subprocess.Popen(
            [sys.executable, str(Path(__file__).resolve()), "_worker", "--run-dir", str(run_dir)],
            stdin=subprocess.DEVNULL,
            stdout=log_file,
            stderr=subprocess.STDOUT,
            start_new_session=True,
        )
        log_file.close()
        deadline = time.monotonic() + 8.0
        while time.monotonic() < deadline:
            if (run_dir / "supervisor.pid").exists() and (run_dir / "status.json").exists():
                break
            if proc.poll() is not None:
                raise RuntimeError(f"Detached supervisor exited early ({proc.returncode}). Log:\n{log_path.read_text()}")
            time.sleep(0.25)
        verify_personal_dbs_unchanged(personal_before)
        print(
            json.dumps(
                {
                    "status": "detached",
                    "supervisor_pid": proc.pid,
                    "run_dir": str(run_dir),
                    "log_path": str(log_path),
                    "monitor_cmd": f"python3 Experiments/Efficiency/scripts/run_long_running.py status --run-dir {run_dir}",
                    "stop_cmd": f"python3 Experiments/Efficiency/scripts/run_long_running.py stop --run-dir {run_dir}",
                    "summarize_cmd": f"python3 Experiments/Efficiency/scripts/run_long_running.py summarize --run-dir {run_dir}",
                },
                indent=2,
            )
        )
        return 0
    return run_worker(run_dir)


def cmd_status(args: argparse.Namespace) -> int:
    run_dir = resolve_run_dir(args.run_dir)
    manifest = json.loads((run_dir / "manifest.json").read_text())
    status = json.loads((run_dir / "status.json").read_text()) if (run_dir / "status.json").exists() else {}
    sup_pid = int((run_dir / "supervisor.pid").read_text().strip()) if (run_dir / "supervisor.pid").exists() else None
    child_pid = status.get("pid")
    personal_ok = snapshot_personal_dbs() == manifest.get("personal_db_baseline", {})
    payload = {
        "run_dir": str(run_dir),
        "profile": manifest["profile"],
        "supervisor_pid": sup_pid,
        "supervisor_alive": pid_exists(sup_pid) if sup_pid else False,
        "child_pid": child_pid,
        "child_alive": pid_exists(int(child_pid)) if child_pid else False,
        "screen_locked_now": detect_screen_locked(),
        "personal_db_unchanged": personal_ok,
        "status": status,
    }
    print(json.dumps(payload, indent=2))
    return 0


def cmd_stop(args: argparse.Namespace) -> int:
    run_dir = resolve_run_dir(args.run_dir)
    pid_path = run_dir / "supervisor.pid"
    if not pid_path.exists():
        raise FileNotFoundError(f"Missing supervisor.pid in {run_dir}")
    sup_pid = int(pid_path.read_text().strip())
    if pid_exists(sup_pid):
        os.kill(sup_pid, signal.SIGTERM)
        deadline = time.monotonic() + args.timeout
        while time.monotonic() < deadline and pid_exists(sup_pid):
            time.sleep(0.3)
        if pid_exists(sup_pid):
            os.kill(sup_pid, signal.SIGKILL)
            time.sleep(0.5)
    summary = compute_run_summary(run_dir)
    print(json.dumps({"stopped_pid": sup_pid, "status": summary["status"], "personal_db_unchanged": summary["personal_db_unchanged"]}, indent=2))
    return 0


def cmd_summarize(args: argparse.Namespace) -> int:
    run_dir = resolve_run_dir(args.run_dir)
    summary = compute_run_summary(run_dir)
    print(json.dumps(summary, indent=2))
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest="command", required=True)

    p_start = sub.add_parser("start")
    p_start.add_argument("--profile", required=True, choices=["soak-8h", "idle-24h-voice-on", "full-32h"])
    p_start.add_argument("--run-dir", type=Path, default=None)
    p_start.add_argument("--duration-seconds", type=float, default=None)
    p_start.add_argument("--cycle-interval-seconds", type=float, default=900.0)
    p_start.add_argument("--cooldown-seconds", type=float, default=300.0)
    p_start.add_argument("--sample-interval-seconds", type=float, default=None)
    p_start.add_argument("--diag-interval-seconds", type=float, default=1800.0)
    p_start.add_argument("--detach", action="store_true")
    p_start.add_argument("--prevent-idle-sleep", action="store_true")
    p_start.add_argument("--sparkle-distribution", action="store_true")
    p_start.add_argument("--shipping-app", type=Path, default=None)
    p_start.add_argument("--bench-app", type=Path, default=None)

    p_status = sub.add_parser("status")
    p_status.add_argument("--run-dir", type=Path, default=None)

    p_stop = sub.add_parser("stop")
    p_stop.add_argument("--run-dir", type=Path, default=None)
    p_stop.add_argument("--timeout", type=float, default=25.0)

    p_sum = sub.add_parser("summarize")
    p_sum.add_argument("--run-dir", type=Path, default=None)

    p_worker = sub.add_parser("_worker")
    p_worker.add_argument("--run-dir", type=Path, required=True)

    args = parser.parse_args()
    if args.command == "start":
        return cmd_start(args)
    if args.command == "status":
        return cmd_status(args)
    if args.command == "stop":
        return cmd_stop(args)
    if args.command == "summarize":
        return cmd_summarize(args)
    if args.command == "_worker":
        return run_worker(args.run_dir)
    return 1


if __name__ == "__main__":
    raise SystemExit(main())
