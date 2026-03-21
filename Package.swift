// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Networking",
    platforms: [
        .iOS(.v26)
    ],
    products: [
        .library(name: "Networking", targets: ["Networking"]),
        .library(name: "NetworkingTestSupport", targets: ["NetworkingTestSupport"])
    ],
    targets: [
        .target(
            name: "Networking",
            exclude: ["NetworkLogger.md"]
        ),
        .target(
            name: "NetworkingTestSupport",
            dependencies: ["Networking"]
        ),
        .testTarget(
            name: "NetworkingTests",
            dependencies: ["Networking", "NetworkingTestSupport"]
        )
    ]
)
