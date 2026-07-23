// swift-tools-version: 6.3
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "PapyrusKit",
    products: [
        .library(
            name: "PapyrusKit",
            targets: ["PapyrusKit"]
        ),
    ],
    targets: [
        .target(
            name: "PapyrusKit"
        ),
        .testTarget(
            name: "PapyrusKitTests",
            dependencies: ["PapyrusKit"]
        ),
    ]
)
