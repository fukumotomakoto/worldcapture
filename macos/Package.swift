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
    dependencies: [
        // 自动更新（与 project.yml 的 Sparkle 依赖保持一致）。
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.5.0"),
    ],
    targets: [
        .target(name: "CaptureKit"),
        .executableTarget(
            name: "WorldCaptureMac",
            dependencies: [
                "CaptureKit",
                .product(name: "Sparkle", package: "Sparkle"),
            ],
            resources: [.process("Resources")]
        ),
        .testTarget(name: "CaptureKitTests", dependencies: ["CaptureKit"]),
    ]
)
