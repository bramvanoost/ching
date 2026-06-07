// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "ShellYesEngine",
    platforms: [
        .iOS(.v17),
        .macOS(.v14),
    ],
    products: [
        .library(name: "ShellYesEngine", targets: ["ShellYesEngine"]),
        .executable(name: "shellyes-parity", targets: ["ShellYesParityCLI"]),
    ],
    targets: [
        .target(name: "ShellYesEngine"),
        .executableTarget(
            name: "ShellYesParityCLI",
            dependencies: ["ShellYesEngine"]
        ),
        .testTarget(
            name: "ShellYesEngineTests",
            dependencies: ["ShellYesEngine"]
        ),
    ]
)
