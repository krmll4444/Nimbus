// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "NimbusCore",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(
            name: "NimbusCore",
            targets: ["NimbusCore"]
        )
    ],
    targets: [
        .target(
            name: "NimbusCore",
            path: "Sources/NimbusCore"
        ),
        .testTarget(
            name: "NimbusCoreTests",
            dependencies: ["NimbusCore"],
            path: "Tests/NimbusCoreTests"
        )
    ]
)
