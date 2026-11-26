#!/usr/bin/env bash
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
base="$(cd "${1:?Path to fresh Rasc source checkout}" && pwd)"
grdb="$(cd "${2:?Path to Xcode-pinned GRDB.swift checkout}" && pwd)"
work="$(mktemp -d /tmp/rasc-voice-persistence.XXXXXX)"
mkdir "$work/Sources"
cat "$base/Rasc/Data/NoteRepository.swift" "$here/RepositoryExtension.swift" > "$work/Sources/NoteRepository.swift"
sed -n '/^struct RefinementMetadata/,/^}/p' "$base/Rasc/Domain/Refinement.swift" > "$work/Sources/RefinementMetadata.swift"
for source in Rasc/Data/{AppDatabase,ActiveNoteStore}.swift Rasc/Domain/{Note,NoteExport,RefinementRevision}.swift; do
  ln -s "$base/$source" "$work/Sources/$(basename "$source")"
done
ln -s "$here/Validate.swift" "$work/Sources/Validate.swift"
cat > "$work/Package.swift" <<SWIFT
// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "VoicePersistenceProbe",
    platforms: [.macOS(.v14)],
    dependencies: [.package(name: "GRDB.swift", path: "$grdb")],
    targets: [.executableTarget(name: "Probe", dependencies: [
        .product(name: "GRDB", package: "GRDB.swift")
    ], path: "Sources")]
)
SWIFT
swift run --package-path "$work" -c release -j 4 Probe
