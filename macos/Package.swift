// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "WorldCaptureMac",
    defaultLocalization: "zh-Hans",
    platforms: [.macOS(.v15)],
    products: [
        .executable(name: "WorldCaptureMac", targets: ["WorldCaptureMac"]),
        .library(name: "CaptureKit", targets: ["CaptureKit"]),
    ],
    targets: [
        .target(name: "CaptureKit"),
        .executableTarget(
            name: "WorldCaptureMac",
            dependencies: ["CaptureKit"],
            resources: [.process("Resources")]
        ),
        .testTarget(name: "CaptureKitTests", dependencies: ["CaptureKit"]),
    ]
)
