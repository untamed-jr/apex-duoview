// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "DuoCore",
    platforms: [.iOS("27.1"), .macOS(.v14)],
    products: [
        .library(name: "F1TV", targets: ["F1TV"]),
        .library(name: "Library", targets: ["Library"]),
        .library(name: "LiveTiming", targets: ["LiveTiming"]),
        .library(name: "Multiview", targets: ["Multiview"]),
    ],
    targets: [
        .target(name: "F1TV"),
        .target(name: "Library"),
        .target(name: "LiveTiming", dependencies: ["F1TV", "Library"]),
        .target(name: "Multiview", dependencies: ["F1TV", "Library"]),
        .testTarget(name: "F1TVTests", dependencies: ["F1TV"], resources: [.copy("Fixtures")]),
        .testTarget(name: "LibraryTests", dependencies: ["Library"]),
        .testTarget(name: "LiveTimingTests", dependencies: ["LiveTiming", "F1TV", "Library"], resources: [.copy("Fixtures")]),
        .testTarget(name: "MultiviewTests", dependencies: ["Multiview"], resources: [.copy("Fixtures")]),
    ],
    swiftLanguageModes: [.v6]
)
