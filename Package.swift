// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Ferry",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "FerryCore"),
        .executableTarget(name: "FerryApp", dependencies: ["FerryCore"]),
        .testTarget(name: "FerryCoreTests", dependencies: ["FerryCore"]),
    ]
)
