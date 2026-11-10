// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "OpenConnectMacGUI",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "OpenConnectCore", targets: ["OpenConnectCore"]),
        .executable(name: "OpenConnectMacGUI", targets: ["OpenConnectMacGUI"])
    ],
    targets: [
        .target(name: "OpenConnectCore"),
        .executableTarget(name: "OpenConnectMacGUI", dependencies: ["OpenConnectCore"]),
        .testTarget(name: "OpenConnectCoreTests", dependencies: ["OpenConnectCore"])
    ]
)
