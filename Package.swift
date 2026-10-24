// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "ToqdasCore",
    platforms: [.macOS(.v13), .iOS(.v16)],
    products: [.library(name: "ToqdasCore", targets: ["ToqdasCore"])],
    targets: [
        .target(name: "ToqdasCore", path: "Core"),
        .testTarget(name: "ToqdasCoreTests", dependencies: ["ToqdasCore"], path: "Tests")
    ]
)
