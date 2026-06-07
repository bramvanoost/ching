// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "CHINGEngine",
    platforms: [
        .iOS(.v17),
        .macOS(.v14),
    ],
    products: [
        .library(name: "CHINGEngine", targets: ["CHINGEngine"]),
        .executable(name: "ching-parity", targets: ["CHINGParityCLI"]),
    ],
    targets: [
        .target(name: "CHINGEngine"),
        .executableTarget(
            name: "CHINGParityCLI",
            dependencies: ["CHINGEngine"]
        ),
        .testTarget(
            name: "CHINGEngineTests",
            dependencies: ["CHINGEngine"]
        ),
    ]
)
