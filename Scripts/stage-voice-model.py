#!/usr/bin/env python3
"""Stage the pinned Voice Capture pack. This developer tool handles model assets only."""

import argparse
import concurrent.futures
import hashlib
import json
from pathlib import Path
import shutil
import subprocess
from urllib.parse import quote

ROOT = Path(__file__).resolve().parents[1]
MODEL = "FluidVoice-Labs/fluid-speech-pro-coreml"
REVISION = "3b9d38a93d606f84011e5a0a669b7ea146375a22"
MANIFEST = ROOT / "Rasc/Resources/VoiceModelManifest.json"


def matches(path, expected):
    if not path.is_file() or path.stat().st_size != expected["bytes"]:
        return False
    with path.open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest() == expected["sha256"]


def stage_model(destination, source=None):
    files = json.loads(MANIFEST.read_text())

    def stage(entry):
        relative, expected = entry
        path = destination / relative
        if matches(path, expected):
            return
        path.parent.mkdir(parents=True, exist_ok=True)
        partial = path.with_suffix(path.suffix + ".partial")
        try:
            if source is None:
                url = f"https://huggingface.co/{MODEL}/resolve/{REVISION}/{quote(relative)}?download=true"
                subprocess.run(
                    ["curl", "--fail", "--silent", "--show-error", "--location", "--retry", "2",
                     "--max-time", "1800", url, "--output", str(partial)],
                    check=True,
                )
            else:
                shutil.copyfile(source / relative, partial)
            if not matches(partial, expected):
                raise ValueError(f"Integrity check failed for {relative}")
            partial.replace(path)
        finally:
            partial.unlink(missing_ok=True)

    with concurrent.futures.ThreadPoolExecutor(max_workers=4) as executor:
        list(executor.map(stage, files.items()))
    print(f"Verified {len(files)} files, {sum(entry['bytes'] for entry in files.values())} bytes ({REVISION})")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("directory", type=Path)
    parser.add_argument("--from", dest="source", type=Path, help="Copy from a previously downloaded model folder.")
    args = parser.parse_args()
    stage_model(args.directory, source=args.source)
