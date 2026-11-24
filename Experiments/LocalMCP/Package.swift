// swift-tools-version:6.2
import PackageDescription
let package = Package(
    name: "RascMCPProbe",
    platforms: [.macOS(.v14)],
    dependencies: [.package(url: "https://github.com/modelcontextprotocol/swift-sdk.git", exact: "0.12.1")],
    targets: [.executableTarget(name: "RascMCPProbe", dependencies: [.product(name: "MCP", package: "swift-sdk")])]
)
