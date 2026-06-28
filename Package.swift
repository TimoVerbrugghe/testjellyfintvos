// swift-tools-version: 6.3
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "JellyfinTVOS",
    platforms: [
        .macOS(.v13),
        .tvOS(.v16)
    ],
    products: [
        .library(
            name: "JellyfinTVOS",
            targets: ["JellyfinTVOS"]
        ),
        .executable(
            name: "JellyfinTVOSDemoApp",
            targets: ["JellyfinTVOSDemoApp"]
        ),
    ],
    targets: [
        .target(
            name: "JellyfinTVOS"
        ),
        .executableTarget(
            name: "JellyfinTVOSDemoApp",
            dependencies: ["JellyfinTVOS"]
        ),
        .testTarget(
            name: "JellyfinTVOSTests",
            dependencies: ["JellyfinTVOS"]
        ),
    ],
    swiftLanguageModes: [.v5]
)
