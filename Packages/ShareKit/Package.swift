// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ShareKit",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "ShareKit", targets: ["ShareKit"]),
    ],
    dependencies: [
        .package(path: "../SharedKit"),
    ],
    targets: [
        .target(
            name: "ShareKit",
            dependencies: [
                "SharedKit",
            ]
        ),
        .testTarget(
            name: "ShareKitTests",
            dependencies: ["ShareKit"]
        ),
    ]
)
