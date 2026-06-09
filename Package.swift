// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "dsmn",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .library(name: "DSMNCore", targets: ["DSMNCore"]),
        .executable(name: "dsmn-app", targets: ["dsmnapp"]),
        .executable(name: "dsmnctl", targets: ["dsmnctl"]),
        .executable(name: "dsmnd", targets: ["dsmnd"])
    ],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.9.2")
    ],
    targets: [
        .target(name: "DSMNCore"),
        .executableTarget(
            name: "dsmnapp",
            dependencies: [
                "DSMNCore",
                .product(name: "Sparkle", package: "Sparkle")
            ],
            exclude: ["Resources"]
        ),
        .executableTarget(name: "dsmnctl", dependencies: ["DSMNCore"]),
        .executableTarget(name: "dsmnd", dependencies: ["DSMNCore"]),
        .testTarget(name: "DSMNCoreTests", dependencies: ["DSMNCore"]),
        .testTarget(name: "dsmndTests", dependencies: ["dsmnd", "DSMNCore"])
    ]
)
