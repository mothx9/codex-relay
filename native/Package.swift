// swift-tools-version: 6.0
import PackageDescription
let package = Package(name: "CodexRelay", platforms: [.macOS(.v13), .iOS(.v17)], products: [.library(name: "RelayCore", targets: ["RelayCore"])], dependencies: [.package(url: "https://github.com/swiftlang/swift-markdown.git", exact: "0.9.0")], targets: [.target(name: "RelayCore", dependencies: [.product(name: "Markdown", package: "swift-markdown")], path: "RelayCore"), .testTarget(name: "RelayCoreTests", dependencies: ["RelayCore"], path: "RelayCoreTests")])
