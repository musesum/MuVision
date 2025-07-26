// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "MuVision",
    platforms: [.iOS(.v17), .visionOS(.v2)],
    products: [.library(name: "MuVision", targets: ["MuVision"])],
    dependencies: [
        .package(url: "https://github.com/musesum/MuFlo.git", branch: "main"),
        .package(url: "https://github.com/musesum/MuPeers.git", branch: "main"),
        .package(url: "https://github.com/musesum/MuHands.git", branch: "main"),
    ],
    targets: [
        .target(name: "MuVision",
                dependencies: [
                    .product(name: "MuFlo", package: "MuFlo"),
                    .product(name: "MuPeers", package: "MuPeers"),
                    .product(name: "MuHands", package: "MuHands"),
                ]),
        .testTarget(
            name: "MuVisionTests",
            dependencies: ["MuVision"]),
    ]
)
