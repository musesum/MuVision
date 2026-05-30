// swift-tools-version: 6.1

import PackageDescription

let package = Package(
    name: "MuVision",
    platforms: [.iOS(.v17), .visionOS(.v2), .watchOS(.v10)],
    products: [.library(name: "MuVision", targets: ["MuVision"])],
    dependencies: [
        // DEV: local paths during watchOS port. Restore github URLs before publish.
        .package(name: "MuFlo", path: "../MuFlo"),
        .package(name: "MuPeers", path: "../MuPeers"),
        .package(name: "MuHands", path: "../MuHands"),
    ],
    targets: [
        .target(name: "MuVision",
                dependencies: [
                    .product(name: "MuFlo", package: "MuFlo"),
                    .product(name: "MuPeers", package: "MuPeers"),
                    .product(name: "MuHands", package: "MuHands"),
                ],
                resources: [.process("Resources")]),
        .testTarget(
            name: "MuVisionTests",
            dependencies: ["MuVision"]),
    ]
)
