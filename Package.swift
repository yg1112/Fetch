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
    ],
    targets: [
        .executableTarget(
            name: "Invoke",
            dependencies: [
            ],
            resources: [
                .process("AppIcon.icns")
            ]
        ),
    ]
)
