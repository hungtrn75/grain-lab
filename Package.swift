// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "GrainLab",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "GrainLab", targets: ["GrainLab"])
    ],
    dependencies: [],
    targets: [
        .executableTarget(
            name: "GrainLab",
            dependencies: [],
            resources: [
                .process("Resources")
            ]
        ),
        .testTarget(
            name: "GrainLabTests",
            dependencies: ["GrainLab"]
        )
    ]
)
