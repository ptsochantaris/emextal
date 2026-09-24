// swift-tools-version: 6.4
import PackageDescription

let package = Package(
    name: "EmextalAudio",
    platforms: [.macOS(.v15), .iOS(.v18)],
    products: [
        .library(name: "EmextalAudio", targets: ["EmextalAudio"]),
    ],
    dependencies: [
        .package(url: "https://github.com/ml-explore/mlx-swift.git", .upToNextMajor(from: "0.31.6")),
        .package(url: "https://github.com/ml-explore/mlx-swift-lm.git", branch: "main"),
        .package(url: "https://github.com/aleroot/swift-tokenizers", from: "1.0.0")
    ],
    targets: [
        .target(
            name: "EmextalAudio",
            dependencies: [
                .product(name: "MLX", package: "mlx-swift"),
                .product(name: "MLXNN", package: "mlx-swift"),
                .product(name: "MLXLMCommon", package: "mlx-swift-lm"),
                .product(name: "Tokenizers", package: "swift-tokenizers"),
            ],
            path: "Sources/EmextalAudio"
        ),
    ]
)
