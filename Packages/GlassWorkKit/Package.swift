// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "GlassWorkKit",
    defaultLocalization: "en",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "GlassWorkCore", targets: ["GlassWorkCore"]),
        .library(name: "GlassWorkUI", targets: ["GlassWorkUI"]),
    ],
    dependencies: [
        .package(url: "https://github.com/pointfreeco/swift-snapshot-testing", from: "1.19.7"),
    ],
    targets: [
        .target(name: "GlassWorkCore"),
        .target(name: "GlassWorkUI", dependencies: ["GlassWorkCore"], resources: [.process("Resources")]),
        .testTarget(name: "GlassWorkCoreTests", dependencies: ["GlassWorkCore"]),
        .testTarget(
            name: "GlassWorkUITests",
            dependencies: [
                "GlassWorkUI",
                .product(name: "SnapshotTesting", package: "swift-snapshot-testing"),
            ],
            exclude: ["__Snapshots__"]
        ),
    ],
    swiftLanguageModes: [.v6]
)
