// swift-tools-version: 6.3
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "JellyfinTVOS",
    products: [
        .library(
            name: "JellyfinTVOS",
            targets: ["JellyfinTVOS"]
        ),
    ],
    targets: [
        .target(
            name: "JellyfinTVOS"
        ),
        .testTarget(
            name: "JellyfinTVOSTests",
            dependencies: ["JellyfinTVOS"]
        ),
    ],
    swiftLanguageModes: [.v6]
)
