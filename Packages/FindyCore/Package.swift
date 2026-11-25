// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "FindyCore",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "FindyCore", targets: ["FindyCore"])
    ],
    dependencies: [
        // SQLite access for the per-folder settings store. MIT license.
        .package(url: "https://github.com/groue/GRDB.swift.git", from: "7.0.0")
    ],
    targets: [
        .target(
            name: "FindyCore",
            dependencies: [.product(name: "GRDB", package: "GRDB.swift")]
        ),
        .testTarget(name: "FindyCoreTests", dependencies: ["FindyCore"]),
    ]
)
