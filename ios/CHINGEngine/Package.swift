// swift-tools-version: 5.10
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
            dependencies: ["CHINGEngine"],
            swiftSettings: [
                .unsafeFlags([
                    "-F", "/Library/Developer/CommandLineTools/Library/Developer/Frameworks",
                ]),
            ],
            linkerSettings: [
                .unsafeFlags([
                    "-F", "/Library/Developer/CommandLineTools/Library/Developer/Frameworks",
                    "-framework", "Testing",
                    "-Xlinker", "-rpath",
                    "-Xlinker", "/Library/Developer/CommandLineTools/Library/Developer/Frameworks",
                    "-Xlinker", "-rpath",
                    "-Xlinker", "/Library/Developer/CommandLineTools/Library/Developer/usr/lib",
                ]),
            ]
        ),
    ]
)
