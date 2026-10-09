// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "SidebarHover",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "SidebarCore"),
        .executableTarget(name: "SidebarHover", dependencies: ["SidebarCore"]),
        .testTarget(name: "SidebarCoreTests", dependencies: ["SidebarCore"]),
    ],
    swiftLanguageModes: [.v5]
)
