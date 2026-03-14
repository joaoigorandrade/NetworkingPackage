// swift-tools-version: 6.2
import CompilerPluginSupport
import PackageDescription

let package = Package(
    name: "Networking",
    platforms: [
        .iOS(.v13),
        .macOS(.v10_15)
    ],
    products: [
        .library(name: "Networking", targets: ["Networking"]),
        .library(name: "NetworkingTestSupport", targets: ["NetworkingTestSupport"])
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-syntax.git", from: "600.0.0")
    ],
    targets: [
        .macro(
            name: "NetworkingMacros",
            dependencies: [
                .product(name: "SwiftCompilerPlugin", package: "swift-syntax"),
                .product(name: "SwiftSyntax", package: "swift-syntax"),
                .product(name: "SwiftSyntaxBuilder", package: "swift-syntax"),
                .product(name: "SwiftSyntaxMacros", package: "swift-syntax")
            ]
        ),
        .target(
            name: "Networking",
            dependencies: ["NetworkingMacros"]
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
