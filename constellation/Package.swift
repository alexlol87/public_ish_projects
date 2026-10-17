// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Constellation",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "ConstellationCore"),
        .executableTarget(name: "Constellation", dependencies: ["ConstellationCore"]),
        .testTarget(name: "ConstellationCoreTests", dependencies: ["ConstellationCore"]),
    ]
)
