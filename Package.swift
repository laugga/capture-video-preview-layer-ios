// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "CaptureVideoPreviewLayer",
    platforms: [
        .iOS(.v17)
    ],
    products: [
        .library(
            name: "CaptureVideoPreviewLayer",
            targets: ["CaptureVideoPreviewLayer"]
        )
    ],
    targets: [
        // Types shared between the library and the Metal shading language sources,
        // so that the uniform and vertex layouts are guaranteed to match on both sides
        .target(
            name: "CaptureVideoPreviewLayerShaderTypes"
        ),
        .target(
            name: "CaptureVideoPreviewLayer",
            dependencies: ["CaptureVideoPreviewLayerShaderTypes"]
        ),
        .testTarget(
            name: "CaptureVideoPreviewLayerTests",
            dependencies: ["CaptureVideoPreviewLayer"],
            resources: [
                .process("Samples.xcassets")
            ]
        )
    ]
)
