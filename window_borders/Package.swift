// swift-tools-version:5.9
import PackageDescription

// Window Borders: a menu bar app that draws a differently colored border around every window.
// BorderCore holds the pure logic (colors, persistence matching, geometry) so it can be unit tested without AppKit;
// WindowBorders is the AppKit app. scripts/build-app.sh wraps the executable into WindowBorders.app.
let package = Package(
    name: "WindowBorders",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "WindowBorders", targets: ["WindowBorders"]),
    ],
    targets: [
        .target(name: "BorderCore"),
        .executableTarget(
            name: "WindowBorders",
            dependencies: ["BorderCore"],
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("ApplicationServices"),
                .linkedFramework("Carbon"),
                .linkedFramework("ServiceManagement"),
            ]
        ),
        .testTarget(name: "BorderCoreTests", dependencies: ["BorderCore"]),
    ]
)
