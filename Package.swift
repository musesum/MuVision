// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "MuVision",
    platforms: [.iOS(.v15)],
    products: [
        // Products define the executables and libraries a package produces, making them visible to other packages.
        .library(
            name: "MuVision",
            targets: ["MuVision"]),
    ],
    dependencies: [
        .package(url: "https://github.com/musesum/MuExtensions.git", .branch("main")),
        .package(url: "https://github.com/musesum/MuFlo.git", from: "0.23.0")
    ],
    targets: [
        // Targets are the basic building blocks of a package, defining a module or a test suite.
        // Targets can depend on other targets in this package and products from dependencies.
        .target(name: "MuVision",
                dependencies: [
                    .product(name: "MuExtensions", package: "MuExtensions"),
                    .product(name: "MuFlo", package: "MuFlo")]),
        .testTarget(
            name: "MuVisionTests",
            dependencies: ["MuVision"]),
    ]
)
