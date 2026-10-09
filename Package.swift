// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "SidebarHover",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "SidebarCore"),
        .testTarget(name: "SidebarCoreTests", dependencies: ["SidebarCore"]),
    ],
    swiftLanguageModes: [.v5]
)
