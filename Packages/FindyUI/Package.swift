// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "FindyUI",
    defaultLocalization: "en",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "FindyUI", targets: ["FindyUI"])
    ],
    dependencies: [
        .package(path: "../FindyCore")
    ],
    targets: [
        .target(
            name: "FindyUI",
            dependencies: ["FindyCore"],
            resources: [.process("Resources")]
        ),
        .testTarget(name: "FindyUITests", dependencies: ["FindyUI", "FindyCore"]),
    ]
)
