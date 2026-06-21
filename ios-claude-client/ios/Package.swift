// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "ClaudeRemote",
    platforms: [
        .iOS(.v17)
    ],
    products: [
        .library(
            name: "ClaudeRemote",
            targets: ["ClaudeRemote"]
        ),
    ],
    dependencies: [
        .package(
            url: "https://github.com/migueldeicaza/SwiftTerm.git",
            from: "1.0.0"
        ),
    ],
    targets: [
        .target(
            name: "ClaudeRemote",
            dependencies: [
                .product(name: "SwiftTerm", package: "SwiftTerm"),
            ],
            path: "ClaudeRemote",
            exclude: [],
            resources: []
        ),
        .testTarget(
            name: "ClaudeRemoteTests",
            dependencies: ["ClaudeRemote"],
            path: "Tests"
        ),
    ]
)
