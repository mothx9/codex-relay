// swift-tools-version: 6.0
import PackageDescription
let package = Package(name: "CodexRelay", platforms: [.macOS(.v13), .iOS(.v17)], products: [.library(name: "RelayCore", targets: ["RelayCore"])], targets: [.target(name: "RelayCore", path: "RelayCore"), .testTarget(name: "RelayCoreTests", dependencies: ["RelayCore"], path: "RelayCoreTests")])
