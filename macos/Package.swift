// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "WorldCaptureMac",
    platforms: [.macOS(.v15)],
    products: [
        .executable(name: "WorldCaptureMac", targets: ["WorldCaptureMac"]),
        .library(name: "CaptureKit", targets: ["CaptureKit"]),
    ],
    targets: [
        .target(name: "CaptureKit"),
        .executableTarget(name: "WorldCaptureMac", dependencies: ["CaptureKit"]),
        .testTarget(name: "CaptureKitTests", dependencies: ["CaptureKit"]),
    ]
)
