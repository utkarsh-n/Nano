// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "NanoCore",
    platforms: [.macOS(.v14)],
    products: [.library(name: "NanoCore", targets: ["NanoCore"])],
    targets: [
        .target(name: "NanoCore", path: "Core"),
        .testTarget(name: "NanoCoreTests", dependencies: ["NanoCore"], path: "Tests")
    ]
)
