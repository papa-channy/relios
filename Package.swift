// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "relios",
    platforms: [
        .macOS(.v13),
    ],
    products: [
        .executable(name: "relios", targets: ["relios"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.3.0"),
        .package(url: "https://github.com/dduan/TOMLDecoder.git", from: "0.2.0"),
    ],
    targets: [
        .executableTarget(
            name: "relios",
            dependencies: ["ReliosCLI"]
        ),
        .target(
            name: "ReliosCLI",
            dependencies: [
                "ReliosCore",
                "ReliosSupport",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ]
        ),
        .target(
            name: "ReliosCore",
            dependencies: [
                "ReliosSupport",
                .product(name: "TOMLDecoder", package: "TOMLDecoder"),
            ]
        ),
        .target(
            name: "ReliosSupport"
        ),
        .testTarget(
            name: "ReliosCoreTests",
            dependencies: [
                "ReliosCore",
                "ReliosSupport",
            ]
        ),
    ]
)
