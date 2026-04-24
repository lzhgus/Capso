// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "TranslationKit",
    platforms: [.macOS(.v15)],
    products: [.library(name: "TranslationKit", targets: ["TranslationKit"])],
    dependencies: [
        .package(path: "../SharedKit"),
        .package(path: "../OCRKit"),
    ],
    targets: [
        .target(name: "TranslationKit", dependencies: ["SharedKit", "OCRKit"]),
        .testTarget(name: "TranslationKitTests", dependencies: ["TranslationKit"]),
    ]
)
