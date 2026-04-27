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
        .package(url: "https://github.com/soto-project/soto.git", exact: "7.14.0"),
    ],
    targets: [
        .target(
            name: "ShareKit",
            dependencies: [
                "SharedKit",
                .product(name: "SotoS3", package: "soto"),
            ]
        ),
        .testTarget(
            name: "ShareKitTests",
            dependencies: ["ShareKit"]
        ),
    ]
)
