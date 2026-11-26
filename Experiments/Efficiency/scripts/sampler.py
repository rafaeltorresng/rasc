#!/usr/bin/env python3
"""External resource sampler for Rasc using native XNU proc_pid_rusage (RUSAGE_INFO_V6) and Apple diagnostics."""
from __future__ import annotations

import argparse
import csv
import ctypes
import json
import os
import re
import signal
import subprocess
import threading
import time
from pathlib import Path
from typing import Any, Callable


class MachTimebaseInfo(ctypes.Structure):
    _fields_ = [
        ("numer", ctypes.c_uint32),
        ("denom", ctypes.c_uint32),
    ]


class RUsageInfoV6(ctypes.Structure):
    _fields_ = [
        ("ri_uuid", ctypes.c_uint8 * 16),
        ("ri_user_time", ctypes.c_uint64),
        ("ri_system_time", ctypes.c_uint64),
        ("ri_pkg_idle_wkups", ctypes.c_uint64),
        ("ri_interrupt_wkups", ctypes.c_uint64),
        ("ri_pageins", ctypes.c_uint64),
        ("ri_wired_size", ctypes.c_uint64),
        ("ri_resident_size", ctypes.c_uint64),
        ("ri_phys_footprint", ctypes.c_uint64),
        ("ri_proc_start_abstime", ctypes.c_uint64),
        ("ri_proc_exit_abstime", ctypes.c_uint64),
        ("ri_child_user_time", ctypes.c_uint64),
        ("ri_child_system_time", ctypes.c_uint64),
        ("ri_child_pkg_idle_wkups", ctypes.c_uint64),
        ("ri_child_interrupt_wkups", ctypes.c_uint64),
        ("ri_child_pageins", ctypes.c_uint64),
        ("ri_child_elapsed_abstime", ctypes.c_uint64),
        ("ri_diskio_bytesread", ctypes.c_uint64),
        ("ri_diskio_byteswritten", ctypes.c_uint64),
        ("ri_cpu_time_qos_default", ctypes.c_uint64),
        ("ri_cpu_time_qos_maintenance", ctypes.c_uint64),
        ("ri_cpu_time_qos_background", ctypes.c_uint64),
        ("ri_cpu_time_qos_utility", ctypes.c_uint64),
        ("ri_cpu_time_qos_legacy", ctypes.c_uint64),
        ("ri_cpu_time_qos_user_initiated", ctypes.c_uint64),
        ("ri_cpu_time_qos_user_interactive", ctypes.c_uint64),
        ("ri_billed_system_time", ctypes.c_uint64),
        ("ri_serviced_system_time", ctypes.c_uint64),
        ("ri_logical_writes", ctypes.c_uint64),
        ("ri_lifetime_max_phys_footprint", ctypes.c_uint64),
        ("ri_instructions", ctypes.c_uint64),
        ("ri_cycles", ctypes.c_uint64),
        ("ri_billed_energy", ctypes.c_uint64),
        ("ri_serviced_energy", ctypes.c_uint64),
        ("ri_interval_max_phys_footprint", ctypes.c_uint64),
        ("ri_runnable_time", ctypes.c_uint64),
        ("ri_flags", ctypes.c_uint64),
        ("ri_user_ptime", ctypes.c_uint64),
        ("ri_system_ptime", ctypes.c_uint64),
        ("ri_pinstructions", ctypes.c_uint64),
        ("ri_pcycles", ctypes.c_uint64),
        ("ri_energy_nj", ctypes.c_uint64),
        ("ri_penergy_nj", ctypes.c_uint64),
        ("ri_secure_time_in_system", ctypes.c_uint64),
        ("ri_secure_ptime_in_system", ctypes.c_uint64),
        ("ri_neural_footprint", ctypes.c_uint64),
        ("ri_lifetime_max_neural_footprint", ctypes.c_uint64),
        ("ri_interval_max_neural_footprint", ctypes.c_uint64),
        ("ri_reserved", ctypes.c_uint64 * 9),
    ]


_LIBSYSTEM = ctypes.CDLL("/usr/lib/libSystem.B.dylib")
_LIBSYSTEM.proc_pid_rusage.argtypes = [ctypes.c_int, ctypes.c_int, ctypes.POINTER(RUsageInfoV6)]
_LIBSYSTEM.proc_pid_rusage.restype = ctypes.c_int
_LIBSYSTEM.mach_timebase_info.argtypes = [ctypes.POINTER(MachTimebaseInfo)]
_LIBSYSTEM.mach_timebase_info.restype = ctypes.c_int

_TIMEBASE = MachTimebaseInfo()
_LIBSYSTEM.mach_timebase_info(ctypes.byref(_TIMEBASE))
_MACH_NUMER = _TIMEBASE.numer
_MACH_DENOM = max(1, _TIMEBASE.denom)

RUSAGE_INFO_V6 = 6


def ticks_to_ns(ticks: int) -> int:
    return (ticks * _MACH_NUMER) // _MACH_DENOM


def read_rusage(pid: int) -> dict[str, Any] | None:
    ru = RUsageInfoV6()
    rc = _LIBSYSTEM.proc_pid_rusage(pid, RUSAGE_INFO_V6, ctypes.byref(ru))
    if rc != 0:
        return None
    user_ns = ticks_to_ns(ru.ri_user_time)
    sys_ns = ticks_to_ns(ru.ri_system_time)
    return {
        "phys_footprint_bytes": int(ru.ri_phys_footprint),
        "lifetime_max_phys_footprint_bytes": int(ru.ri_lifetime_max_phys_footprint),
        "interval_max_phys_footprint_bytes": int(ru.ri_interval_max_phys_footprint),
        "resident_size_bytes": int(ru.ri_resident_size),
        "wired_size_bytes": int(ru.ri_wired_size),
        "neural_footprint_bytes": int(ru.ri_neural_footprint),
        "lifetime_max_neural_footprint_bytes": int(ru.ri_lifetime_max_neural_footprint),
        "user_time_ns": int(user_ns),
        "system_time_ns": int(sys_ns),
        "cpu_time_ns": int(user_ns + sys_ns),
        "pkg_idle_wkups": int(ru.ri_pkg_idle_wkups),
        "interrupt_wkups": int(ru.ri_interrupt_wkups),
        "pageins": int(ru.ri_pageins),
        "diskio_bytesread": int(ru.ri_diskio_bytesread),
        "diskio_byteswritten": int(ru.ri_diskio_byteswritten),
        "logical_writes": int(ru.ri_logical_writes),
        "instructions": int(ru.ri_instructions),
        "cycles": int(ru.ri_cycles),
        "energy_nj": int(ru.ri_energy_nj),
        "penergy_nj": int(ru.ri_penergy_nj),
        "billed_energy": int(ru.ri_billed_energy),
        "runnable_time_ns": int(ticks_to_ns(ru.ri_runnable_time)),
    }


def pid_exists(pid: int) -> bool:
    try:
        os.kill(pid, 0)
        return True
    except OSError:
        return False


def detect_screen_locked() -> bool | None:
    """Best-effort query for macOS CGSSessionScreenIsLocked without touching private APIs."""
    try:
        proc = subprocess.run(
            [
                "swift",
                "-e",
                (
                    "import CoreGraphics; "
                    "if let d = CGSessionCopyCurrentDictionary() as? [String: Any], "
                    "let v = d[\"CGSSessionScreenIsLocked\"] as? Int { print(v) } else { print(0) }"
                ),
            ],
            capture_output=True,
            text=True,
            timeout=5.0,
        )
        if proc.returncode == 0:
            out = proc.stdout.strip()
            if out in ("0", "1"):
                return out == "1"
    except Exception:
        pass
    return None


def atomic_write_json(path: Path, payload: Any) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_suffix(path.suffix + ".tmp")
    tmp.write_text(json.dumps(payload, indent=2))
    tmp.replace(path)


def capture_diagnostics(pid: int, out_dir: Path, prefix: str) -> dict[str, Any]:
    out_dir.mkdir(parents=True, exist_ok=True)
    summary: dict[str, Any] = {"captured_at": time.strftime("%Y-%m-%dT%H:%M:%S%z"), "prefix": prefix}

    def run_text(cmd: list[str], timeout: float = 20.0) -> str:
        try:
            proc = subprocess.run(cmd, capture_output=True, text=True, timeout=timeout)
            return proc.stdout + ("\n--- stderr ---\n" + proc.stderr if proc.stderr.strip() else "")
        except Exception as exc:
            return f"<failed: {exc}>"

    footprint_txt = run_text(["footprint", str(pid)])
    (out_dir / f"{prefix}_footprint.txt").write_text(footprint_txt)
    m = re.search(r"Footprint:\s*([0-9.]+)\s*(KB|MB|GB|B)", footprint_txt)
    if m:
        summary["footprint_cli"] = f"{m.group(1)} {m.group(2)}"

    vmmap_txt = run_text(["vmmap", "--summary", str(pid)])
    (out_dir / f"{prefix}_vmmap.txt").write_text(vmmap_txt)

    leaks_txt = run_text(["leaks", str(pid)], timeout=45.0)
    (out_dir / f"{prefix}_leaks.txt").write_text(leaks_txt)
    ml = re.search(r"Process \d+:\s+(\d+)\s+leaks?\s+for\s+(\d+)\s+total leaked bytes", leaks_txt)
    if ml:
        summary["leaks_count"] = int(ml.group(1))
        summary["leaks_bytes"] = int(ml.group(2))

    lsof_txt = run_text(["lsof", "-n", "-p", str(pid)])
    (out_dir / f"{prefix}_lsof.txt").write_text(lsof_txt)
    lsof_lines = [ln for ln in lsof_txt.splitlines() if ln.strip()]
    summary["open_fds"] = max(0, len(lsof_lines) - 1)

    ps_txt = run_text(["ps", "-Ao", "pid,ppid,rss,pcpu,time,comm"])
    related = [
        ln.strip()
        for ln in ps_txt.splitlines()
        if "VoiceModelDownloader" in ln or "com.rafaeltorres.rasc" in ln or "Rasc.app" in ln
    ]
    summary["related_processes"] = related
    return summary


def quantile(sorted_vals: list[float], q: float) -> float:
    if not sorted_vals:
        return 0.0
    if len(sorted_vals) == 1:
        return sorted_vals[0]
    idx = (len(sorted_vals) - 1) * q
    lo = int(idx)
    hi = min(len(sorted_vals) - 1, lo + 1)
    frac = idx - lo
    return sorted_vals[lo] * (1.0 - frac) + sorted_vals[hi] * frac


def ols_slope_mib_per_min(points: list[tuple[float, float]]) -> float:
    if len(points) < 2:
        return 0.0
    n = float(len(points))
    sum_x = sum(x for x, _ in points)
    sum_y = sum(y for _, y in points)
    mean_x = sum_x / n
    mean_y = sum_y / n
    denom = sum((x - mean_x) ** 2 for x, _ in points)
    if denom <= 1e-12:
        return 0.0
    numer = sum((x - mean_x) * (y - mean_y) for x, y in points)
    bytes_per_sec = numer / denom
    return (bytes_per_sec * 60.0) / (1024.0 * 1024.0)


def summarize_samples(samples: list[dict[str, Any]], label: str) -> dict[str, Any]:
    if not samples:
        return {"label": label, "sample_count": 0}
    fps = sorted(s["phys_footprint_bytes"] / (1024 * 1024) for s in samples)
    rss = sorted(s["resident_size_bytes"] / (1024 * 1024) for s in samples)
    neural = sorted(s["neural_footprint_bytes"] / (1024 * 1024) for s in samples)
    cpus = sorted(s["cpu_pct"] for s in samples[1:] or samples)
    wkups = sorted(s["idle_wkups_per_s"] for s in samples[1:] or samples)
    int_wkups = sorted(s["interrupt_wkups_per_s"] for s in samples[1:] or samples)
    pwr = sorted(s["energy_mw"] for s in samples[1:] or samples)

    first, last = samples[0], samples[-1]
    active_elapsed_s = max(1e-6, float(last["elapsed_s"]) - float(first["elapsed_s"]))
    detected_sleep_events = sum(1 for s in samples if int(s.get("sleep_gap_detected", 0) or 0) > 0)
    total_sleep_gap_s = round(
        sum(float(s.get("wall_gap_s", 0.0) or 0.0) for s in samples if int(s.get("sleep_gap_detected", 0) or 0) > 0),
        3,
    )
    if "wall_epoch" in first and "wall_epoch" in last:
        wall_elapsed_s = max(active_elapsed_s, float(last["wall_epoch"]) - float(first["wall_epoch"]))
    else:
        wall_elapsed_s = active_elapsed_s + total_sleep_gap_s

    cpu_delta_ms = (last["cpu_time_ns"] - first["cpu_time_ns"]) / 1e6
    energy_delta_j = (last["energy_nj"] - first["energy_nj"]) / 1e9
    disk_read_bytes = int(last["diskio_bytesread"] - first["diskio_bytesread"])
    disk_written_bytes = int(last["diskio_byteswritten"] - first["diskio_byteswritten"])
    logical_writes_bytes = int(last["logical_writes"] - first["logical_writes"])

    start_fp_mib = round(first["phys_footprint_bytes"] / (1024 * 1024), 2)
    end_fp_mib = round(last["phys_footprint_bytes"] / (1024 * 1024), 2)
    peak_fp_mib = round(fps[-1], 2)
    slope_min = ols_slope_mib_per_min([(float(s["elapsed_s"]), float(s["phys_footprint_bytes"])) for s in samples])
    slope_hr = slope_min * 60.0

    return {
        "label": label,
        "sample_count": len(samples),
        "elapsed_s": round(active_elapsed_s, 3),
        "active_elapsed_s": round(active_elapsed_s, 3),
        "wall_elapsed_s": round(wall_elapsed_s, 3),
        "detected_sleep_events": detected_sleep_events,
        "total_sleep_gap_s": total_sleep_gap_s,
        "phys_footprint_mib": {
            "start": start_fp_mib,
            "end": end_fp_mib,
            "min": round(fps[0], 2),
            "p50": round(quantile(fps, 0.5), 2),
            "p95": round(quantile(fps, 0.95), 2),
            "max": peak_fp_mib,
            "mean": round(sum(fps) / len(fps), 2),
            "slope_mib_per_min": round(slope_min, 4),
            "slope_mib_per_hour": round(slope_hr, 4),
        },
        "recovery_delta_mib": {
            "from_peak_mib": round(end_fp_mib - peak_fp_mib, 2),
            "from_start_mib": round(end_fp_mib - start_fp_mib, 2),
        },
        "lifetime_max_phys_footprint_mib": round(
            last["lifetime_max_phys_footprint_bytes"] / (1024 * 1024), 2
        ),
        "rss_mib": {
            "min": round(rss[0], 2),
            "p50": round(quantile(rss, 0.5), 2),
            "p95": round(quantile(rss, 0.95), 2),
            "max": round(rss[-1], 2),
        },
        "neural_footprint_mib": {
            "p50": round(quantile(neural, 0.5), 2),
            "max": round(neural[-1], 2),
            "lifetime_max": round(last["lifetime_max_neural_footprint_bytes"] / (1024 * 1024), 2),
        },
        "cpu_pct": {
            "mean": round((cpu_delta_ms / 1000.0) / active_elapsed_s * 100.0, 4),
            "p50": round(quantile(cpus, 0.5), 4),
            "p95": round(quantile(cpus, 0.95), 4),
            "max": round(cpus[-1], 4),
        },
        "cumulative_cpu_ms": round(cpu_delta_ms, 2),
        "pkg_idle_wkups_total": int(last["pkg_idle_wkups"] - first["pkg_idle_wkups"]),
        "pkg_idle_wkups_per_s_mean": round(
            (last["pkg_idle_wkups"] - first["pkg_idle_wkups"]) / active_elapsed_s, 4
        ),
        "pkg_idle_wkups_per_s_p50": round(quantile(wkups, 0.5), 4),
        "interrupt_wkups_total": int(last["interrupt_wkups"] - first["interrupt_wkups"]),
        "interrupt_wkups_per_s_mean": round(
            (last["interrupt_wkups"] - first["interrupt_wkups"]) / active_elapsed_s, 4
        ),
        "interrupt_wkups_per_s_p50": round(quantile(int_wkups, 0.5), 4),
        "disk_read_bytes": disk_read_bytes,
        "disk_written_bytes": disk_written_bytes,
        "logical_writes_bytes": logical_writes_bytes,
        "disk_read_mib": round(disk_read_bytes / (1024 * 1024), 3),
        "disk_written_mib": round(disk_written_bytes / (1024 * 1024), 3),
        "logical_writes_mib": round(logical_writes_bytes / (1024 * 1024), 3),
        "pageins_delta": int(last["pageins"] - first["pageins"]),
        "xnu_cpu_energy_j": round(energy_delta_j, 4),
        "xnu_cpu_power_mw_mean": round((energy_delta_j * 1000.0) / active_elapsed_s, 2),
        "xnu_cpu_power_mw_p50": round(quantile(pwr, 0.5), 2),
    }


def sample_process(
    pid: int,
    duration_s: float,
    interval_s: float,
    csv_path: Path,
    phase_file: Path | None = None,
    stop_when_exits: bool = True,
    diag_dir: Path | None = None,
    diag_prefix: str = "end",
    status_path: Path | None = None,
    partial_summary_path: Path | None = None,
    periodic_diag_interval_s: float = 0.0,
    stop_event: threading.Event | None = None,
    status_extra_fn: Callable[[], dict[str, Any]] | None = None,
) -> dict[str, Any]:
    csv_path.parent.mkdir(parents=True, exist_ok=True)
    start_t = time.monotonic()
    samples: list[dict[str, Any]] = []
    prev: dict[str, Any] | None = None
    prev_t: float | None = None
    prev_wall_t: float | None = None
    final_diag: dict[str, Any] = {}
    periodic_diags: list[dict[str, Any]] = []
    diag_captured = False
    last_diag_t = start_t
    last_status_t = start_t - 10.0

    csv_file = None
    writer: csv.DictWriter | None = None

    def active_phase() -> str:
        if not phase_file or not phase_file.exists():
            return "running"
        lines = [ln.strip() for ln in phase_file.read_text().splitlines() if ln.strip()]
        if not lines:
            return "starting"
        try:
            obj = json.loads(lines[-1])
            return obj.get("phase", "running")
        except Exception:
            return "running"

    def write_live_status(state: str, force: bool = False) -> None:
        nonlocal last_status_t
        now_status = time.monotonic()
        if not force and (now_status - last_status_t) < max(interval_s, 10.0):
            return
        last_status_t = now_status
        summary = summarize_samples(samples, csv_path.stem) if samples else {"label": csv_path.stem, "sample_count": 0}
        if partial_summary_path and samples:
            atomic_write_json(partial_summary_path, {"state": state, "summary": summary, "periodic_diagnostics": periodic_diags})
        if status_path:
            payload: dict[str, Any] = {
                "state": state,
                "pid": pid,
                "updated_at": time.strftime("%Y-%m-%dT%H:%M:%S%z"),
                "latest": samples[-1] if samples else None,
                "summary": summary,
            }
            if status_extra_fn:
                try:
                    payload.update(status_extra_fn())
                except Exception:
                    pass
            atomic_write_json(status_path, payload)

    try:
        while True:
            if stop_event is not None and stop_event.is_set():
                break
            now_t = time.monotonic()
            wall_now = time.time()
            elapsed = now_t - start_t
            if duration_s > 0 and elapsed >= duration_s:
                break
            ru = read_rusage(pid)
            if ru is None:
                break

            phase = active_phase()
            if stop_when_exits and (phase == "exiting" or (samples and ru["phys_footprint_bytes"] == 0)):
                break

            if prev is not None and prev_t is not None and prev_wall_t is not None:
                dt = max(1e-6, now_t - prev_t)
                wall_dt = max(0.0, wall_now - prev_wall_t)
                wall_gap_s = max(0.0, wall_dt - dt)
                sleep_gap_detected = 1 if wall_gap_s > max(5.0, interval_s * 3.0) else 0
                d_cpu_ns = max(0, ru["cpu_time_ns"] - prev["cpu_time_ns"])
                d_wkups = max(0, ru["pkg_idle_wkups"] - prev["pkg_idle_wkups"])
                d_iwkups = max(0, ru["interrupt_wkups"] - prev["interrupt_wkups"])
                d_energy_nj = max(0, ru["energy_nj"] - prev["energy_nj"])
                d_disk_r = max(0, ru["diskio_bytesread"] - prev["diskio_bytesread"])
                d_disk_w = max(0, ru["diskio_byteswritten"] - prev["diskio_byteswritten"])
                cpu_pct = (d_cpu_ns / 1e9) / dt * 100.0
                idle_wkups_per_s = d_wkups / dt
                int_wkups_per_s = d_iwkups / dt
                energy_mw = (d_energy_nj / 1e6) / dt
            else:
                cpu_pct = 0.0
                idle_wkups_per_s = 0.0
                int_wkups_per_s = 0.0
                energy_mw = 0.0
                d_disk_r = 0
                d_disk_w = 0
                wall_gap_s = 0.0
                sleep_gap_detected = 0

            row = {
                "wall_iso": time.strftime("%Y-%m-%dT%H:%M:%S%z"),
                "wall_epoch": round(wall_now, 3),
                "elapsed_s": round(elapsed, 3),
                "wall_gap_s": round(wall_gap_s, 3),
                "sleep_gap_detected": sleep_gap_detected,
                "phase": phase,
                "cpu_pct": round(cpu_pct, 4),
                "idle_wkups_per_s": round(idle_wkups_per_s, 4),
                "interrupt_wkups_per_s": round(int_wkups_per_s, 4),
                "energy_mw": round(energy_mw, 3),
                "delta_disk_read_bytes": d_disk_r,
                "delta_disk_write_bytes": d_disk_w,
                **ru,
            }
            if writer is None:
                csv_file = csv_path.open("w", newline="")
                writer = csv.DictWriter(csv_file, fieldnames=list(row.keys()))
                writer.writeheader()
            writer.writerow(row)
            csv_file.flush()

            samples.append(row)
            prev = ru
            prev_t = now_t
            prev_wall_t = wall_now

            write_live_status("running")

            if diag_dir and not diag_captured and phase == "cooldown_done":
                final_diag = capture_diagnostics(pid, diag_dir, diag_prefix)
                diag_captured = True
            elif diag_dir and periodic_diag_interval_s > 0 and (now_t - last_diag_t) >= periodic_diag_interval_s:
                last_diag_t = now_t
                snap = capture_diagnostics(pid, diag_dir, f"{diag_prefix}_t{int(elapsed):06d}s")
                snap["elapsed_s"] = round(elapsed, 1)
                periodic_diags.append(snap)

            next_target = now_t + interval_s
            sleep_s = max(0.0, next_target - time.monotonic())
            if sleep_s > 0:
                if stop_event is not None:
                    if stop_event.wait(timeout=sleep_s):
                        break
                else:
                    time.sleep(sleep_s)
            if not pid_exists(pid):
                break

        if diag_dir and not diag_captured and pid_exists(pid):
            final_diag = capture_diagnostics(pid, diag_dir, diag_prefix)
    finally:
        if csv_file is not None:
            csv_file.flush()
            csv_file.close()
        final_state = "stopped" if (stop_event is not None and stop_event.is_set()) else "completed"
        write_live_status(final_state, force=True)

    return {
        "summary": summarize_samples(samples, csv_path.stem),
        "diagnostics": final_diag,
        "periodic_diagnostics": periodic_diags,
    }


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--pid", type=int, required=True)
    parser.add_argument("--duration", type=float, default=0.0)
    parser.add_argument("--interval", type=float, default=1.0)
    parser.add_argument("--csv", type=Path, required=True)
    parser.add_argument("--phase-file", type=Path, default=None)
    parser.add_argument("--diag-dir", type=Path, default=None)
    parser.add_argument("--diag-prefix", type=str, default="snapshot")
    parser.add_argument("--periodic-diag-interval", type=float, default=0.0)
    parser.add_argument("--status-path", type=Path, default=None)
    parser.add_argument("--partial-summary-path", type=Path, default=None)
    parser.add_argument("--json-out", type=Path, default=None)
    args = parser.parse_args()

    stop_event = threading.Event()

    def _on_sig(_signum: int, _frame: Any) -> None:
        stop_event.set()

    signal.signal(signal.SIGTERM, _on_sig)
    signal.signal(signal.SIGINT, _on_sig)

    result = sample_process(
        pid=args.pid,
        duration_s=args.duration,
        interval_s=args.interval,
        csv_path=args.csv,
        phase_file=args.phase_file,
        diag_dir=args.diag_dir,
        diag_prefix=args.diag_prefix,
        status_path=args.status_path,
        partial_summary_path=args.partial_summary_path,
        periodic_diag_interval_s=args.periodic_diag_interval,
        stop_event=stop_event,
    )
    if args.json_out:
        atomic_write_json(args.json_out, result)
    print(json.dumps(result, indent=2))


if __name__ == "__main__":
    main()
