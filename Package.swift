// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "Invoke",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(
            name: "Invoke",
            targets: ["Invoke"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", .upToNextMajor(from: "2.0.0"))
    ],
    targets: [
        .executableTarget(
            name: "Invoke",
            dependencies: [
                .product(name: "Sparkle", package: "Sparkle")
            ],
            resources: [
                .process("AppIcon.icns")
            ]
        ),
    ]
)
