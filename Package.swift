// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "MacRecode",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(name: "MacRecode", targets: ["MacRecode"]),
        .executable(name: "MacRecodeApp", targets: ["MacRecodeApp"])
    ],
    targets: [
        .target(
            name: "MacRecode",
            dependencies: []
        ),
        .executableTarget(
            name: "MacRecodeApp",
            dependencies: ["MacRecode"]
        ),
        .testTarget(
            name: "MacRecodeTests",
            dependencies: ["MacRecode"]
        )
    ]
)