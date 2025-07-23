// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "MacRecode",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "MacRecode", targets: ["MacRecode"])
    ],
    targets: [
        .executableTarget(
            name: "MacRecode",
            dependencies: []
        ),
        .testTarget(
            name: "MacRecodeTests",
            dependencies: ["MacRecode"]
        )
    ]
)