#!/usr/bin/env python3
"""Build a Release-optimized RascBench.app against the real Rasc Swift sources in /tmp/rasc-bench-pkg."""
from __future__ import annotations

import json
import os
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[4]
CHECKOUTS = ROOT / ".derivedData/Rasc/SourcePackages/checkouts"
PKG = Path(os.environ.get("RASC_BENCH_DIR", "/tmp/rasc-bench-pkg"))
DRIVER = Path(__file__).resolve().parent / "BenchRunner.swift"


def link(src: Path, dst: Path) -> None:
    dst.parent.mkdir(parents=True, exist_ok=True)
    if dst.is_symlink() and dst.resolve() == src.resolve():
        return
    if dst.exists() or dst.is_symlink():
        dst.unlink()
    dst.symlink_to(src)


def main() -> None:
    for dep in ("GRDB.swift", "KeyboardShortcuts", "FluidAudio"):
        if not (CHECKOUTS / dep / "Package.swift").exists():
            raise SystemExit(f"Missing package checkout: {CHECKOUTS / dep}")

    for src in (ROOT / "Rasc").rglob("*.swift"):
        if src.name == "RascApp.swift":
            continue
        link(src, PKG / "Sources/RascBench/Rasc" / src.relative_to(ROOT / "Rasc"))

    link(DRIVER, PKG / "Sources/RascBench/BenchRunner.swift")
    link(DRIVER.with_name("VoiceReliability.swift"), PKG / "Sources/RascBench/VoiceReliability.swift")

    deps = [
        str(CHECKOUTS / "GRDB.swift"),
        str(CHECKOUTS / "KeyboardShortcuts"),
        os.environ.get("RASC_BENCH_FLUID_CHECKOUT", str(CHECKOUTS / "FluidAudio")),
        str(ROOT / "Vendor/ThinkingOrbsKit"),
    ]
    dep_lines = ",\n".join(f'        .package(path: {json.dumps(p)})' for p in deps)
    (PKG / "Package.swift").write_text(f"""// swift-tools-version:6.2
import PackageDescription

let package = Package(
    name: "RascBench",
    platforms: [.macOS(.v14)],
    dependencies: [
{dep_lines}
    ],
    targets: [
        .executableTarget(
            name: "RascBench",
            dependencies: [
                .product(name: "GRDB", package: "GRDB.swift"),
                .product(name: "KeyboardShortcuts", package: "KeyboardShortcuts"),
                .product(name: "ThinkingOrbsKit", package: "ThinkingOrbsKit"),
                .product(name: "FluidAudio", package: "FluidAudio"),
            ]
        )
    ]
)
""")

    subprocess.run(["xcrun", "swift", "build", "-c", "release", "--package-path", str(PKG)], check=True)
    bin_path = PKG / ".build/release/RascBench"
    app = PKG / "RascBench.app"
    contents = app / "Contents"
    macos = contents / "MacOS"
    res = contents / "Resources"
    macos.mkdir(parents=True, exist_ok=True)
    res.mkdir(parents=True, exist_ok=True)
    subprocess.run(["cp", "-f", str(bin_path), str(macos / "RascBench")], check=True)
    subprocess.run(["cp", "-f", str(ROOT / "Rasc/Resources/VoiceModelManifest.json"), str(res / "VoiceModelManifest.json")], check=True)
    (contents / "Info.plist").write_text("""<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key><string>RascBench</string>
  <key>CFBundleIdentifier</key><string>com.rafaeltorres.rasc.bench</string>
  <key>CFBundleName</key><string>RascBench</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>0.1.16</string>
  <key>CFBundleVersion</key><string>22</string>
</dict>
</plist>
""")
    print(f"Built Release bundle -> {macos / 'RascBench'}")


if __name__ == "__main__":
    main()
