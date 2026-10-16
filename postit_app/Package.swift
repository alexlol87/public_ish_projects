// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "PostIt",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "PostItCore"),
        .executableTarget(name: "PostIt", dependencies: ["PostItCore"]),
        .testTarget(name: "PostItTests", dependencies: ["PostItCore"]),
    ]
)
