#!/usr/bin/env python3
"""Run real domain tests without LaunchServices. Native window suites stay in Xcode."""
import argparse
import json
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
WINDOW_SUITES = {
    "PanelControllerTests.swift", "HomeWindowControllerTests.swift",
    "SettingsWindowPresentationTests.swift", "WindowFrameStoreTests.swift",
    "AppReliabilityLifecycleTests.swift",
}
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--checkouts", type=Path, default=ROOT / ".derivedData/Rasc/SourcePackages/checkouts")
parser.add_argument("--package-dir", type=Path, default=ROOT / ".derivedData/DomainVerification")
args = parser.parse_args()
work = args.package_dir.resolve()
checkouts = args.checkouts.resolve()
for name in ["GRDB.swift", "KeyboardShortcuts"]:
    if not (checkouts / name / "Package.swift").exists():
        parser.error(f"Resolve Xcode packages first; missing {checkouts / name}")

def link(source, destination):
    destination.parent.mkdir(parents=True, exist_ok=True)
    if destination.is_symlink() and destination.resolve() == source.resolve():
        return
    if destination.exists() or destination.is_symlink():
        parser.error(f"Refusing to overwrite unrelated harness file: {destination}")
    destination.symlink_to(source)

for source in (ROOT / "Rasc").rglob("*.swift"):
    if source.name != "RascApp.swift":
        link(source, work / "Sources/Rasc" / source.relative_to(ROOT / "Rasc"))
for source in (ROOT / "RascTests").glob("*.swift"):
    if source.name not in WINDOW_SUITES:
        link(source, work / "Tests/RascTests" / source.name)
link(ROOT / "RascTests/Fixtures", work / "Tests/RascTests/Fixtures")
# Historical corpus tests resolve paths relative to #filePath.
link(ROOT / "Evals", work / "Tests/Evals")
link(ROOT / "Evals", work / "Evals")
paths = [checkouts / "GRDB.swift", checkouts / "KeyboardShortcuts", ROOT / "Vendor/ThinkingOrbsKit"]
dependencies = ",\n".join(f".package(path: {json.dumps(str(path))})" for path in paths)
(work / "Package.swift").write_text(f'''// swift-tools-version:6.2
import PackageDescription
let package = Package(name: "RascDomainVerification", platforms: [.macOS(.v14)], dependencies: [
{dependencies}
], targets: [
.target(name: "Rasc", dependencies: [.product(name: "GRDB", package: "GRDB.swift"), .product(name: "KeyboardShortcuts", package: "KeyboardShortcuts"), .product(name: "ThinkingOrbsKit", package: "ThinkingOrbsKit")]),
.testTarget(name: "RascTests", dependencies: ["Rasc"], resources: [.copy("Fixtures")])
])
''')
print("Running actual sources and domain tests. Five native window suites require Xcode.", flush=True)
raise SystemExit(subprocess.call(["xcrun", "swift", "test", "--package-path", str(work)], cwd=ROOT))
