// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "RascParakeetProbe",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(url: "https://github.com/FluidInference/FluidAudio.git", exact: "0.18.4", traits: [])
    ],
    targets: [
        .executableTarget(name: "ParakeetProbe", dependencies: [
            .product(name: "FluidAudio", package: "FluidAudio")
        ], path: "Sources")
    ]
)
