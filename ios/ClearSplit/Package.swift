// swift-tools-version: 6.2
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "ClearSplit",
    platforms: [.iOS(.v17)],
    products: [
        .library(
            name: "ClearSplit",
            targets: ["ClearSplit"]
        ),
    ],
    targets: [
        .target(
            name: "ClearSplit"
        ),
        .testTarget(
            name: "ClearSplitTests",
            dependencies: ["ClearSplit"]
        ),
    ]
)
