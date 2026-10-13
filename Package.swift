// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "HerdrGlow",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "HerdrGlowCore"),
        .executableTarget(name: "HerdrGlow", dependencies: ["HerdrGlowCore"]),
        .testTarget(name: "HerdrGlowCoreTests", dependencies: ["HerdrGlowCore"]),
    ],
    swiftLanguageModes: [.v5]
)
