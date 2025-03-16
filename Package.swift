// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "MuVision",
    platforms: [.iOS(.v17)],
    products: [.library(name: "MuVision", targets: ["MuVision"])],
    dependencies: [
        .package(url: "https://github.com/musesum/MuFlo.git", branch: "genius"),
        .package(url: "https://github.com/musesum/MuPeer.git", branch: "genius"),
    ],
    targets: [
        .target(name: "MuVision",
                dependencies: [
                    .product(name: "MuFlo", package: "MuFlo"),
                    .product(name: "MuPeer", package: "MuPeer"),
                ]),
        .testTarget(
            name: "MuVisionTests",
            dependencies: ["MuVision"]),
    ]
)
