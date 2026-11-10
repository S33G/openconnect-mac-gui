// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "BettererConnect",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "BetterConnectCore", targets: ["BetterConnectCore"]),
        .executable(name: "BettererConnect", targets: ["BettererConnect"])
    ],
    targets: [
        .target(name: "BetterConnectCore"),
        .executableTarget(name: "BettererConnect", dependencies: ["BetterConnectCore"]),
        .testTarget(name: "BetterConnectCoreTests", dependencies: ["BetterConnectCore"])
    ]
)
