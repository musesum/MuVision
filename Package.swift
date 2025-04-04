// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "MuVision",
    platforms: [.iOS(.v17)],
    products: [.library(name: "MuVision", targets: ["MuVision"])],
    dependencies: [
        .package(url: "https://github.com/musesum/MuFlo.git", branch: "sync"),
        .package(url: "https://github.com/musesum/MuPeer.git", branch: "sync"),
    ],
    targets: [
        .target(name: "MuVision",
                dependencies: [
                    .product(name: "MuFlo", package: "MuFlo"),
                    .product(name: "MuPeer", package: "MuPeer"),
                ])
    ]
)
