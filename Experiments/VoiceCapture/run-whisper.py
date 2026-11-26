#!/usr/bin/env python3
"""Stage an ad-hoc signed benchmark bundle and evaluate the same fixtures offline."""
import argparse
import json
import plistlib
import shutil
import subprocess
import tempfile
from pathlib import Path

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("binary", type=Path)
parser.add_argument("model", type=Path)
parser.add_argument("fixtures", type=Path)
parser.add_argument("output", type=Path)
args = parser.parse_args()
args.output.mkdir(parents=True, exist_ok=True)
here = Path(__file__).resolve().parent
rows = json.loads((args.fixtures / "manifest.json").read_text())

with tempfile.TemporaryDirectory(prefix="rasc-whisper-") as name:
    app = Path(name) / "RascWhisperProbe.app"
    binary = app / "Contents/MacOS/WhisperProbe"
    assets = app / "Contents/Resources"
    assets.mkdir(parents=True)
    binary.parent.mkdir()
    shutil.copy2(args.binary, binary)
    model = assets / args.model.name
    subprocess.run(["cp", "-c", args.model, model], check=True)
    for item in rows:
        filename = item["id"] + ".wav"
        shutil.copy2(args.fixtures / filename, assets / filename)
    (app / "Contents/Info.plist").write_bytes(plistlib.dumps({
        "CFBundleIdentifier": "com.rasc.research.whisperprobe",
        "CFBundleExecutable": "WhisperProbe", "CFBundleName": "Rasc Whisper Probe",
        "CFBundlePackageType": "APPL", "CFBundleVersion": "1",
    }))
    entitlements = here / "design/design.entitlements"
    subprocess.run(["codesign", "--force", "--sign", "-", "--options", "runtime",
                    "--entitlements", entitlements, app], check=True)
    subprocess.run(["codesign", "--verify", "--deep", "--strict", app], check=True)
    with (args.output / "whisper-signing.txt").open("w") as record:
        subprocess.run(["codesign", "-d", "--entitlements", "-", "-r-", app],
                       stdout=record, stderr=record, check=True)
    with (args.output / "whisper-batch.jsonl").open("w") as results, (args.output / "whisper-batch-resources.txt").open("w") as metrics:
        for language in ("en", "pt", "auto"):
            metrics.write(language + "\n")
            metrics.flush()
            files = [assets / (row["id"] + ".wav") for row in rows
                     if (language == "auto" and row["id"] in {"pt-clip", "en-clip", "mix-switch", "mix-worker", "accidental"})
                     or row["locale"].split("-")[0] == language]
            subprocess.run(["/usr/bin/time", "-l", binary, model, language, *files],
                           stdout=results, stderr=metrics, check=True, timeout=180)
