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
            name: "ClearSplit",
            targets: ["ClearSplit"]
        )
    ],
    targets: [
        .target(
            name: "ClearSplit"
        ),
        .testTarget(
            name: "ClearSplitTests",
            dependencies: ["ClearSplit"]
        )
    ]
)
