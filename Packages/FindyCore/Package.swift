// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "FindyCore",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "FindyCore", targets: ["FindyCore"])
    ],
    targets: [
        .target(name: "FindyCore"),
        .testTarget(name: "FindyCoreTests", dependencies: ["FindyCore"]),
    ]
)
