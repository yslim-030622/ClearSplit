// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "ClearSplit",
    platforms: [
        .iOS(.v16),
        .macOS(.v12)
    ],
    products: [
        .library(
            name: "ClearSplitCore",
            targets: ["ClearSplitCore"]
        )
    ],
    targets: [
        .target(
            name: "ClearSplitCore",
            path: "Sources/ClearSplit"
        ),
        .testTarget(
            name: "ClearSplitTests",
            dependencies: ["ClearSplitCore"],
            path: "Tests/ClearSplitTests"
        )
    ]
)
