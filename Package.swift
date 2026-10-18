// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "NotchIsland",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "NotchIsland", targets: ["NotchIsland"]),
        // Loaded into /usr/bin/perl at runtime, never linked; see Sources/NowPlayingHelper
        .library(name: "NowPlayingHelper", type: .dynamic, targets: ["NowPlayingHelper"]),
    ],
    targets: [
        .executableTarget(name: "NotchIsland"),
        .target(name: "NowPlayingHelper", linkerSettings: [.linkedFramework("Foundation")]),
    ]
)
