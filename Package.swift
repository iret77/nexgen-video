// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "NexGenVideo",
    platforms: [.macOS(.v26)],
    products: [
        .executable(name: "NexGenVideo", targets: ["NexGenVideo"]),
        // Shared across the app AND every loadable format pack: one dynamic
        // library so host and plugin link ONE copy of the `Pack`/`PackEntry`
        // protocol metadata (bundle.sh embeds it in Contents/Frameworks).
        .library(name: "NexGenEngine", type: .dynamic, targets: ["NexGenEngine"]),
        // The first loadable pack — built as a dynamic library, then assembled +
        // signed into `musicvideo.ngvpack` by the release workflow. NOT a
        // dependency of the app: it ships OUTSIDE the DMG and loads at runtime.
        .library(name: "MusicvideoPlugin", type: .dynamic, targets: ["MusicvideoPlugin"]),
    ],
    dependencies: [
        .package(url: "https://github.com/dmrschmidt/DSWaveformImage", from: "14.2.2"),
        .package(url: "https://github.com/modelcontextprotocol/swift-sdk.git", from: "0.11.0"),
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.7.0"),
        .package(url: "https://github.com/getsentry/sentry-cocoa", from: "8.40.0"),
        .package(url: "https://github.com/huggingface/swift-transformers", from: "1.3.3"),
        .package(url: "https://github.com/airbnb/lottie-ios", from: "4.6.1"),
        .package(url: "https://github.com/jpsim/Yams", from: "5.0.0"),
    ],
    targets: [
        .executableTarget(
            name: "NexGenVideo",
            dependencies: [
                .product(name: "DSWaveformImage", package: "DSWaveformImage"),
                .product(name: "MCP", package: "swift-sdk"),
                .product(name: "Sparkle", package: "Sparkle"),
                .product(name: "Sentry", package: "sentry-cocoa"),
                .product(name: "Tokenizers", package: "swift-transformers"),
                .product(name: "Lottie", package: "lottie-ios"),
                "NexGenEngine",
            ],
            path: "Sources/NexGenVideo",
            exclude: [
                "Resources/Info.plist",
                "Resources/AppIcon.icns",
                "Resources/AppIcon.png",
            ],
            resources: [
                .copy("Resources/Fonts"),
                .copy("Resources/MCPB/nexgen.mcpb"),
                .copy("Resources/Images"),
                .copy("Resources/Changelog"),
            ],
            plugins: ["MetalCIKernelPlugin"]
        ),
        .plugin(name: "MetalCIKernelPlugin", capability: .buildTool()),
        .target(
            name: "NexGenEngine",
            dependencies: [
                .product(name: "Yams", package: "Yams"),
            ],
            path: "Sources/NexGenEngine"
        ),
        // The musicvideo format pack. Links NexGenEngine (the shared dynamic
        // library) so its `Pack`/`PackEntry` metadata is identical to the host's.
        // Its knowledge (pattern library, phase docs, badge) ships as target
        // resources, assembled into the `.ngvpack` alongside the signed dylib.
        .target(
            name: "MusicvideoPlugin",
            dependencies: ["NexGenEngine"],
            path: "Sources/MusicvideoPlugin",
            resources: [
                .copy("Resources/MusicvideoPack"),
            ]
        ),
        .testTarget(
            name: "NexGenVideoTests",
            dependencies: ["NexGenVideo", "NexGenEngine", "MusicvideoPlugin"],
            path: "Tests/NexGenVideoTests"
        ),
        // Depends on MusicvideoPlugin too: the pack is no longer compiled into the
        // engine, so the pack-specific tests link it and register it explicitly.
        .testTarget(
            name: "NexGenEngineTests",
            dependencies: ["NexGenEngine", "MusicvideoPlugin"],
            path: "Tests/NexGenEngineTests",
            resources: [
                .copy("Fixtures"),
                .copy("Goldens"),
            ]
        ),
    ]
)
