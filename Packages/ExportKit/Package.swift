// swift-tools-version: 6.0
import PackageDescription
let package = Package(
    name: "ExportKit",
    platforms: [.macOS(.v15)],
    products: [.library(name: "ExportKit", targets: ["ExportKit"])],
    dependencies: [.package(path: "../SharedKit"), .package(path: "../EffectsKit"), .package(path: "../EditorKit")],
    targets: [
        .target(name: "ExportKit", dependencies: ["SharedKit", "EffectsKit", "EditorKit"]),
        .testTarget(name: "ExportKitTests", dependencies: ["ExportKit", "SharedKit"]),
    ]
)
