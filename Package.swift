// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Ferry",
    defaultLocalization: "en",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "FerryCore"),
        .executableTarget(name: "FerryApp", dependencies: ["FerryCore"],
                          resources: [.process("Resources")]),
        .testTarget(name: "FerryCoreTests", dependencies: ["FerryCore"]),
    ]
)
