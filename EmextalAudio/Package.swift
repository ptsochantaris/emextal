// swift-tools-version:6.3
import PackageDescription

let package = Package(
    name: "EmextalAudio",
    platforms: [.macOS(.v14), .iOS(.v17)],
    products: [
        .library(name: "EmextalAudio", targets: ["EmextalAudio"])
    ],
    dependencies: [
        .package(url: "https://github.com/ml-explore/mlx-swift.git", .upToNextMajor(from: "0.31.4")),
        .package(url: "https://github.com/ml-explore/mlx-swift-lm.git", branch: "main"),
        .package(url: "https://github.com/DePasqualeOrg/swift-tokenizers.git", .upToNextMinor(from: "0.7.1"))
    ],
    targets: [
        .target(
            name: "EmextalAudio",
            dependencies: [
                .product(name: "MLX", package: "mlx-swift"),
                .product(name: "MLXNN", package: "mlx-swift"),
                .product(name: "MLXLMCommon", package: "mlx-swift-lm"),
                .product(name: "Tokenizers", package: "swift-tokenizers")
            ],
            path: "Sources/EmextalAudio"
        )
    ]
)
