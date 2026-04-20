// swift-tools-version: 6.0
import PackageDescription
let package = Package(
    name: "EditorKit",
    platforms: [.macOS(.v15)],
    products: [.library(name: "EditorKit", targets: ["EditorKit"])],
    dependencies: [.package(path: "../EffectsKit")],
    targets: [
        .target(name: "EditorKit", dependencies: ["EffectsKit"]),
        .testTarget(name: "EditorKitTests", dependencies: ["EditorKit"]),
    ]
)
