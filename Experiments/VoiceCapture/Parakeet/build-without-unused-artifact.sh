#!/usr/bin/env bash
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
work="${1:?Pass a fresh experiment directory}"
mkdir -p "$work"
work="$(cd "$work" && pwd)"
git clone --depth 1 --branch v0.18.4 https://github.com/FluidInference/FluidAudio.git "$work/FluidAudio"
mkdir "$work/Probe" "$work/Probe/Sources"
cp "$here/Sources/main.swift" "$work/Probe/Sources/main.swift"
python3 - "$here" "$work" <<'PY'
import json
import sys
from pathlib import Path

here, work = map(Path, sys.argv[1:])
manifest = work / "FluidAudio/Package@swift-6.2.swift"
text = manifest.read_text()
start = text.index('                .target(\n                    name: "NemoTextProcessing"')
end = text.index('                .target(name: "LuxTts', start)
text = text[:start] + text[end:]
start = text.index("        .binaryTarget(")
end = text.index("        .target(", start)
manifest.write_text(text[:start] + text[end:])
probe = (here / "Package.swift").read_text().replace(
    'url: "https://github.com/FluidInference/FluidAudio.git", exact: "0.18.4"',
    "path: " + json.dumps(str(work / "FluidAudio")),
)
(work / "Probe/Package.swift").write_text(probe)
PY
swift build --package-path "$work/Probe" --scratch-path "$work/build" -c release
