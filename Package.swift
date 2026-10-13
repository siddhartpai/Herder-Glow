// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "HerderGlow",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "HerderGlowCore"),
        .executableTarget(name: "HerderGlow", dependencies: ["HerderGlowCore"]),
        .testTarget(name: "HerderGlowCoreTests", dependencies: ["HerderGlowCore"]),
    ],
    swiftLanguageModes: [.v5]
)
