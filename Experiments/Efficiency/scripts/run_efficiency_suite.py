#!/usr/bin/env python3
"""Reproducible Release efficiency benchmark orchestrator for Rasc."""
from __future__ import annotations

import argparse
import hashlib
import json
import os
import plistlib
import shutil
import subprocess
import sys
import time
from pathlib import Path
from typing import Any

from sampler import capture_diagnostics, pid_exists, read_rusage, sample_process, summarize_samples

ROOT = Path(__file__).resolve().parents[3]
SCRIPTS_DIR = Path(__file__).resolve().parent
SAMPLER = SCRIPTS_DIR / "sampler.py"

BUNDLE_ID = "com.rafaeltorres.rasc.efficiency"
MODEL_REV = "3b9d38a93d606f84011e5a0a669b7ea146375a22"

PERSONAL_DBS = [
    Path.home() / "Library/Application Support/Rasc/Rasc.sqlite",
    Path.home() / "Library/Containers/com.rafaeltorres.rasc/Data/Library/Application Support/Rasc/Rasc.sqlite",
]

MODEL_CANDIDATES = [
    Path.home() / f"Library/Containers/com.rafaeltorres.rasc/Data/Library/Application Support/Rasc/VoiceModels/{MODEL_REV}",
    Path.home() / f"Library/Application Support/Rasc/VoiceModels/{MODEL_REV}",
]

WORK_ROOT = Path("/tmp/rasc-efficiency-build")


def snapshot_personal_dbs() -> dict[str, tuple[int, int] | None]:
    out: dict[str, tuple[int, int] | None] = {}
    for p in PERSONAL_DBS:
        if p.exists():
            st = p.stat()
            out[str(p)] = (st.st_mtime_ns, st.st_size)
        else:
            out[str(p)] = None
    return out


def verify_personal_dbs_unchanged(before: dict[str, tuple[int, int] | None]) -> None:
    after = snapshot_personal_dbs()
    if before != after:
        raise RuntimeError(f"Personal database modified! before={before} after={after}")


def find_voice_model_source() -> Path:
    for candidate in MODEL_CANDIDATES:
        resolved = candidate.resolve()
        if resolved.is_dir() and (resolved / "Preprocessor.mlmodelc").exists():
            return resolved
    raise FileNotFoundError(
        f"Verified speech model ({MODEL_REV}) not found in expected local locations."
    )


def build_release_app(
    derived_path: Path,
    staged_app_path: Path,
    bundle_id: str,
    extra_swift_flags: str | None = None,
) -> Path:
    source_packages = ROOT / ".derivedData/Rasc/SourcePackages"
    cmd = [
        "xcodebuild",
        "-project", str(ROOT / "Rasc.xcodeproj"),
        "-scheme", "Rasc",
        "-configuration", "Release",
        "-destination", "platform=macOS,arch=arm64",
        "-derivedDataPath", str(derived_path),
        "-clonedSourcePackagesDirPath", str(source_packages),
        "CODE_SIGN_STYLE=Manual",
        "CODE_SIGN_IDENTITY=-",
        "DEVELOPMENT_TEAM=",
    ]
    if (source_packages / "checkouts").exists():
        cmd.append("-disableAutomaticPackageResolution")
    if extra_swift_flags:
        cmd.append(f"OTHER_SWIFT_FLAGS=$(inherited) {extra_swift_flags}")
    cmd.append("build")
    print(f"[build] {' '.join(cmd)}", flush=True)
    proc = subprocess.run(cmd, cwd=ROOT, capture_output=True, text=True)
    if proc.returncode != 0:
        print(proc.stdout[-4000:])
        print(proc.stderr[-4000:], file=sys.stderr)
        raise RuntimeError(f"xcodebuild failed with status {proc.returncode}")

    built_app = derived_path / "Build/Products/Release/Rasc.app"
    if staged_app_path.exists():
        shutil.rmtree(staged_app_path)
    staged_app_path.parent.mkdir(parents=True, exist_ok=True)
    subprocess.run(["ditto", str(built_app), str(staged_app_path)], check=True)
    subprocess.run(
        [
            "/usr/libexec/PlistBuddy",
            "-c", f"Set :CFBundleIdentifier {bundle_id}",
            str(staged_app_path / "Contents/Info.plist"),
        ],
        check=True,
    )
    subprocess.run(
        [
            "codesign", "--force", "--sign", "-", "--options", "runtime",
            "--entitlements", str(ROOT / "Rasc/Rasc.entitlements"),
            "--generate-entitlement-der", str(staged_app_path),
        ],
        check=True,
        capture_output=True,
    )
    subprocess.run(
        ["codesign", "--verify", "--deep", "--strict", str(staged_app_path)],
        check=True,
        capture_output=True,
    )
    return staged_app_path


def app_size_breakdown(app_path: Path) -> dict[str, Any]:
    def dir_bytes(p: Path) -> int:
        if not p.exists():
            return 0
        if p.is_file() or p.is_symlink():
            return p.lstat().st_size
        return sum(f.lstat().st_size for f in p.rglob("*") if f.is_file())

    du_kb = int(subprocess.check_output(["du", "-sk", str(app_path)], text=True).split()[0])
    contents = app_path / "Contents"
    return {
        "app_du_kib": du_kb,
        "app_du_mib": round(du_kb / 1024.0, 2),
        "total_file_bytes": dir_bytes(app_path),
        "macos_binary_bytes": dir_bytes(contents / "MacOS/Rasc"),
        "frameworks_bytes": dir_bytes(contents / "Frameworks"),
        "xpc_services_bytes": dir_bytes(contents / "XPCServices"),
        "resources_bytes": dir_bytes(contents / "Resources"),
    }


def container_dir(bundle_id: str) -> Path:
    return Path.home() / f"Library/Containers/{bundle_id}/Data"


def write_container_prefs(bundle_id: str, prefs: dict[str, Any]) -> None:
    cdir = container_dir(bundle_id)
    plist_path = cdir / f"Library/Preferences/{bundle_id}.plist"
    plist_path.parent.mkdir(parents=True, exist_ok=True)
    # Write XML/binary plist cleanly and also sync via `defaults import` on file path
    data = plistlib.dumps(prefs, fmt=plistlib.FMT_BINARY)
    plist_path.write_bytes(data)


def stage_voice_model(bundle_id: str, model_src: Path) -> int:
    dst_parent = container_dir(bundle_id) / "Library/Application Support/Rasc/VoiceModels"
    dst = dst_parent / MODEL_REV
    dst_parent.mkdir(parents=True, exist_ok=True)
    if dst.exists() or dst.is_symlink():
        if dst.is_symlink():
            dst.unlink()
        else:
            shutil.rmtree(dst)
    # Use APFS clone (regular files/dirs, zero symlinks so VoiceModelAssets regularFile check passes)
    subprocess.run(["cp", "-cR", str(model_src), str(dst)], check=True)
    total_bytes = sum(f.stat().st_size for f in dst.rglob("*") if f.is_file())
    return total_bytes


def stage_bench_fixtures(bundle_id: str) -> Path:
    fixtures_dst = container_dir(bundle_id) / "Library/Application Support/Rasc/EfficiencyBench/fixtures"
    if fixtures_dst.exists():
        shutil.rmtree(fixtures_dst)
    fixtures_dst.mkdir(parents=True, exist_ok=True)
    examples_dir = ROOT / "Experiments/VoiceCapture/Round4/examples"
    examples = json.loads((examples_dir / "examples.json").read_text())["examples"]
    manifest = []
    for row in examples:
        wav_name = Path(row["audio"]).name
        src_wav = examples_dir / wav_name
        shutil.copy2(src_wav, fixtures_dst / wav_name)
        manifest.append({
            "id": row["id"],
            "audio": wav_name,
            "language": row.get("language"),
            "durationSeconds": row.get("audioSeconds"),
        })
    (fixtures_dst / "manifest.json").write_text(json.dumps(manifest, indent=2))
    return fixtures_dst


def wait_for_rusage(pid: int, timeout_s: float = 5.0) -> dict[str, Any]:
    deadline = time.monotonic() + timeout_s
    while time.monotonic() < deadline:
        ru = read_rusage(pid)
        if ru is not None:
            return ru
        time.sleep(0.02)
    raise RuntimeError(f"Could not attach proc_pid_rusage to pid {pid}")


def terminate_process(proc: subprocess.Popen[Any]) -> None:
    if proc.poll() is None:
        proc.terminate()
        try:
            proc.wait(timeout=8.0)
        except subprocess.TimeoutExpired:
            proc.kill()
            proc.wait(timeout=5.0)


def launch_binary(binary: Path, args: list[str] | None = None, stderr_file: Path | None = None) -> subprocess.Popen[Any]:
    cmd = [str(binary)] + (args or [])
    stderr_handle = open(stderr_file, "w") if stderr_file else subprocess.DEVNULL
    return subprocess.Popen(cmd, stdout=subprocess.DEVNULL, stderr=stderr_handle)


def measure_launch_runs(binary: Path, bundle_id: str, seed_db_dir: Path | None, runs: int, out_dir: Path) -> dict[str, Any]:
    print(f"[launch] Measuring {runs} cold-process launches of unmodified Release binary...", flush=True)
    all_runs = []
    for idx in range(runs):
        cdir = container_dir(bundle_id)
        db_dir = cdir / "Library/Application Support/Rasc"
        db_dir.mkdir(parents=True, exist_ok=True)
        for name in ["Rasc.sqlite", "Rasc.sqlite-wal", "Rasc.sqlite-shm"]:
            p = db_dir / name
            if p.exists():
                p.unlink()
        if seed_db_dir and seed_db_dir.exists():
            for name in ["Rasc.sqlite", "Rasc.sqlite-wal", "Rasc.sqlite-shm"]:
                src = seed_db_dir / name
                if src.exists():
                    shutil.copy2(src, db_dir / name)
        time.sleep(0.3)
        proc = launch_binary(
            binary,
            args=["-onboardingCompleted", "YES", "-voiceCaptureEnabled", "NO"],
        )
        try:
            wait_for_rusage(proc.pid)
            res = sample_process(
                pid=proc.pid,
                duration_s=8.0,
                interval_s=0.1,
                csv_path=out_dir / f"launch_run_{idx}.csv",
                stop_when_exits=False,
            )
            import csv as csvmod
            rows = list(csvmod.DictReader((out_dir / f"launch_run_{idx}.csv").open()))
            peak_cpu = max(float(r["cpu_pct"]) for r in rows)
            settle_s = float(rows[-1]["elapsed_s"])
            for i in range(len(rows) - 1):
                t = float(rows[i]["elapsed_s"])
                if t >= 0.2 and float(rows[i]["cpu_pct"]) < 1.5 and float(rows[i + 1]["cpu_pct"]) < 1.5:
                    settle_s = t
                    break
            settled_fp_mib = round(int(rows[-1]["phys_footprint_bytes"]) / (1024 * 1024), 2)
            settled_rss_mib = round(int(rows[-1]["resident_size_bytes"]) / (1024 * 1024), 2)
            all_runs.append({
                "run": idx,
                "peak_cpu_pct": round(peak_cpu, 2),
                "time_to_idle_s": round(float(settle_s), 2),
                "settled_footprint_mib": settled_fp_mib,
                "settled_rss_mib": settled_rss_mib,
                "cum_cpu_ms_8s": res["summary"]["cumulative_cpu_ms"],
                "pkg_idle_wkups_8s": res["summary"]["pkg_idle_wkups_total"],
            })
        finally:
            terminate_process(proc)
        time.sleep(0.5)

    def stats(key: str) -> dict[str, float]:
        vals = sorted(r[key] for r in all_runs)
        mid = vals[len(vals) // 2]
        return {"min": vals[0], "p50": mid, "max": vals[-1]}

    return {
        "runs": all_runs,
        "peak_cpu_pct": stats("peak_cpu_pct"),
        "time_to_idle_s": stats("time_to_idle_s"),
        "settled_footprint_mib": stats("settled_footprint_mib"),
        "settled_rss_mib": stats("settled_rss_mib"),
        "cum_cpu_ms_8s": stats("cum_cpu_ms_8s"),
        "pkg_idle_wkups_8s": stats("pkg_idle_wkups_8s"),
    }


def measure_idle_window(
    name: str,
    binary: Path,
    launch_args: list[str],
    duration_s: float,
    settle_s: float,
    out_dir: Path,
) -> dict[str, Any]:
    print(f"[idle:{name}] Launching unmodified Release binary (settle={settle_s}s, sample={duration_s}s)...", flush=True)
    proc = launch_binary(binary, args=launch_args)
    try:
        wait_for_rusage(proc.pid)
        if settle_s > 0:
            _ = sample_process(
                pid=proc.pid,
                duration_s=settle_s,
                interval_s=1.0,
                csv_path=out_dir / f"{name}_settle.csv",
                stop_when_exits=False,
            )
        diag_start = capture_diagnostics(proc.pid, out_dir / "diagnostics", f"{name}_start")
        result = sample_process(
            pid=proc.pid,
            duration_s=duration_s,
            interval_s=1.0,
            csv_path=out_dir / f"{name}.csv",
            stop_when_exits=False,
            diag_dir=out_dir / "diagnostics",
            diag_prefix=f"{name}_end",
        )
        return {
            "summary": result["summary"],
            "diagnostics_start": diag_start,
            "diagnostics_end": result["diagnostics"],
        }
    finally:
        terminate_process(proc)


def run_workday_benchmark(
    binary: Path,
    bundle_id: str,
    out_dir: Path,
) -> dict[str, Any]:
    print("[workday] Launching Release --run-efficiency-bench & sampling full 8-phase workload...", flush=True)
    bench_out = container_dir(bundle_id) / "Library/Application Support/Rasc/EfficiencyBench/output"
    if bench_out.exists():
        shutil.rmtree(bench_out)
    bench_out.mkdir(parents=True, exist_ok=True)
    phase_file = bench_out / "phases.jsonl"

    proc = subprocess.Popen(
        [str(binary), "--run-efficiency-bench"],
        stdout=subprocess.DEVNULL,
        stderr=open(out_dir / "workday_stderr.log", "w"),
    )
    try:
        wait_for_rusage(proc.pid, timeout_s=10.0)
        sample_res = sample_process(
            pid=proc.pid,
            duration_s=600.0,
            interval_s=1.0,
            csv_path=out_dir / "workday_timeseries.csv",
            phase_file=phase_file,
            stop_when_exits=True,
            diag_dir=out_dir / "diagnostics",
            diag_prefix="workday_cooldown",
        )
        proc.wait(timeout=30.0)
    finally:
        terminate_process(proc)

    # Copy container outputs into repo results directory
    for fname in ["phases.jsonl", "ops.jsonl", "summary.json"]:
        src = bench_out / fname
        if src.exists():
            shutil.copy2(src, out_dir / f"workday_{fname}")

    # Measure SQLite footprint after endurance workload
    db_root = container_dir(bundle_id) / "Library/Application Support/Rasc"
    sqlite_files = {}
    for fname in ["Rasc.sqlite", "Rasc.sqlite-wal", "Rasc.sqlite-shm"]:
        p = db_root / fname
        sqlite_files[fname] = p.stat().st_size if p.exists() else 0

    # Per-phase breakdown from workday_timeseries.csv
    import csv as csvmod
    rows = list(csvmod.DictReader((out_dir / "workday_timeseries.csv").open()))
    typed_rows = []
    for r in rows:
        tr: dict[str, Any] = {"phase": r["phase"], "elapsed_s": float(r["elapsed_s"])}
        for k, v in r.items():
            if k in ("wall_iso", "phase"):
                continue
            tr[k] = float(v) if "." in v else int(v)
        typed_rows.append(tr)

    by_phase: dict[str, list[dict[str, Any]]] = {}
    for r in typed_rows:
        by_phase.setdefault(r["phase"], []).append(r)

    phase_summaries = {
        phase: summarize_samples(plist, phase)
        for phase, plist in by_phase.items()
    }

    in_app_summary = json.loads((out_dir / "workday_summary.json").read_text()) if (out_dir / "workday_summary.json").exists() else {}

    return {
        "overall_sample_summary": sample_res["summary"],
        "diagnostics_cooldown": sample_res["diagnostics"],
        "phase_summaries": phase_summaries,
        "in_app_summary": in_app_summary,
        "sqlite_sizes_bytes": sqlite_files,
        "returncode": proc.returncode,
    }


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--label", required=True, choices=["baseline", "optimized"])
    parser.add_argument("--output", type=Path, default=None)
    parser.add_argument("--idle-duration", type=float, default=90.0)
    parser.add_argument("--launch-runs", type=int, default=5)
    parser.add_argument("--keep-container", action="store_true")
    args = parser.parse_args()

    out_dir = (args.output or (ROOT / f"Experiments/Efficiency/results/{args.label}")).resolve()
    if out_dir.exists():
        shutil.rmtree(out_dir)
    out_dir.mkdir(parents=True, exist_ok=True)

    personal_before = snapshot_personal_dbs()
    model_src = find_voice_model_source()

    commit = subprocess.check_output(["git", "rev-parse", "--short", "HEAD"], cwd=ROOT, text=True).strip()
    os_ver = subprocess.check_output(["sw_vers", "-productVersion"], text=True).strip()
    os_build = subprocess.check_output(["sw_vers", "-buildVersion"], text=True).strip()
    cpu_brand = subprocess.check_output(["sysctl", "-n", "machdep.cpu.brand_string"], text=True).strip()
    mem_bytes = int(subprocess.check_output(["sysctl", "-n", "hw.memsize"], text=True).strip())
    xcode_ver = " / ".join(subprocess.check_output(["xcodebuild", "-version"], text=True).strip().splitlines())

    shipping_derived = ROOT / ".derivedData/Rasc"
    bench_derived = ROOT / ".derivedData/RascEfficiencyBench"
    if WORK_ROOT.exists():
        shutil.rmtree(WORK_ROOT)
    WORK_ROOT.mkdir(parents=True, exist_ok=True)

    # Clean previous Rasc data inside isolated container (keep SIP-protected container root)
    cdir = container_dir(BUNDLE_ID)
    for sub in [
        cdir / "Library/Application Support/Rasc",
        cdir / "Library/Caches",
    ]:
        if sub.exists():
            shutil.rmtree(sub, ignore_errors=True)

    try:
        shipping_app = build_release_app(
            shipping_derived,
            WORK_ROOT / "Shipping/Rasc.app",
            BUNDLE_ID,
        )
        shipping_binary = shipping_app / "Contents/MacOS/Rasc"
        bundle_breakdown = app_size_breakdown(shipping_app)

        bench_app = build_release_app(
            bench_derived,
            WORK_ROOT / "Bench/Rasc.app",
            BUNDLE_ID,
            extra_swift_flags="-DRASC_EFFICIENCY_BENCHMARK",
        )
        bench_binary = bench_app / "Contents/MacOS/Rasc"

        # Stage speech model and CC-BY-4.0 FLEURS WAVs inside isolated container
        model_bytes = stage_voice_model(BUNDLE_ID, model_src)
        stage_bench_fixtures(BUNDLE_ID)

        # 1. Run workday endurance benchmark first (seeds DB cleanly, tests all 8 phases + cooldown + leaks)
        write_container_prefs(BUNDLE_ID, {
            "onboardingCompleted": True,
            "onboardingStep": 5,
            "voiceCaptureEnabled": False,
        })
        workday = run_workday_benchmark(bench_binary, BUNDLE_ID, out_dir)

        # Preserve a copy of the realistic DB (seeded notes) for unmodified shipping tests so Onboarding stays skipped
        db_snapshot_dir = WORK_ROOT / "seed_db_snapshot"
        if db_snapshot_dir.exists():
            shutil.rmtree(db_snapshot_dir)
        db_snapshot_dir.mkdir(parents=True)
        for name in ["Rasc.sqlite", "Rasc.sqlite-wal", "Rasc.sqlite-shm"]:
            src = container_dir(BUNDLE_ID) / "Library/Application Support/Rasc" / name
            if src.exists():
                shutil.copy2(src, db_snapshot_dir / name)

        # 2. Launch latency & startup settle (n=5 unmodified Shipping Release runs)
        launch_stats = measure_launch_runs(shipping_binary, BUNDLE_ID, db_snapshot_dir, args.launch_runs, out_dir)

        # Restore snapshot DB
        db_dst = container_dir(BUNDLE_ID) / "Library/Application Support/Rasc"
        for name in ["Rasc.sqlite", "Rasc.sqlite-wal", "Rasc.sqlite-shm"]:
            if (db_snapshot_dir / name).exists():
                shutil.copy2(db_snapshot_dir / name, db_dst / name)

        # 3. Unmodified Shipping Release — Idle Voice OFF
        idle_voice_off = measure_idle_window(
            "idle_voice_off",
            shipping_binary,
            ["-onboardingCompleted", "YES", "-voiceCaptureEnabled", "NO"],
            args.idle_duration,
            8.0,
            out_dir,
        )

        # Verify speech model is staged intact inside container before Voice On idle tests
        staged_model = container_dir(BUNDLE_ID) / f"Library/Application Support/Rasc/VoiceModels/{MODEL_REV}/Preprocessor.mlmodelc"
        if not staged_model.exists():
            stage_voice_model(BUNDLE_ID, model_src)
        assert staged_model.exists(), f"Missing staged speech model at {staged_model}"

        # 4. Unmodified Shipping Release — Idle Voice ON (Core ML prepared; settle 30s so preparation finishes)
        idle_voice_on = measure_idle_window(
            "idle_voice_on",
            shipping_binary,
            ["-onboardingCompleted", "YES", "-voiceCaptureEnabled", "YES"],
            args.idle_duration,
            30.0,
            out_dir,
        )

        # 5. Unmodified Shipping Release — Idle with Single-Modifier Shortcut (`Option`) active
        idle_modifier_on = measure_idle_window(
            "idle_modifier_on",
            shipping_binary,
            [
                "-onboardingCompleted", "YES",
                "-voiceCaptureEnabled", "YES",
                "-globalShortcutsMigratedV1", "YES",
                "-globalShortcutModifier.voiceScratchpad", "option",
            ],
            45.0,
            12.0,
            out_dir,
        )

        report = {
            "label": args.label,
            "generated_at": time.strftime("%Y-%m-%dT%H:%M:%S%z"),
            "environment": {
                "commit": commit,
                "machine_cpu": cpu_brand,
                "memory_bytes": mem_bytes,
                "macos_version": os_ver,
                "macos_build": os_build,
                "xcode": xcode_ver,
                "bundle_id": BUNDLE_ID,
                "is_sandboxed": True,
                "personal_db_unchanged": True,
            },
            "disk_footprint": {
                "app_bundle": bundle_breakdown,
                "speech_model_bytes": model_bytes,
                "speech_model_mib": round(model_bytes / (1024 * 1024), 2),
                "sqlite_after_workday_bytes": workday["sqlite_sizes_bytes"],
            },
            "launch": launch_stats,
            "idle_voice_off": idle_voice_off,
            "idle_voice_on": idle_voice_on,
            "idle_modifier_on": idle_modifier_on,
            "workday": workday,
        }
        (out_dir / "report.json").write_text(json.dumps(report, indent=2))
        print(f"[done] Report written to {out_dir / 'report.json'}", flush=True)
    finally:
        verify_personal_dbs_unchanged(personal_before)
        if not args.keep_container:
            shutil.rmtree(cdir / "Library/Application Support/Rasc", ignore_errors=True)
        if WORK_ROOT.exists():
            shutil.rmtree(WORK_ROOT, ignore_errors=True)


if __name__ == "__main__":
    main()
