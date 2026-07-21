// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "FFMpegasus",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "FFMpegasus", targets: ["FFMpegasus"])
    ],
    targets: [
        .target(
            name: "FFMpegasusCore",
            path: "Sources/FFMpegasusCore"
        ),
        .executableTarget(
            name: "FFMpegasus",
            dependencies: ["FFMpegasusCore"],
            path: "Sources/FFMpegasus"
        ),
        .testTarget(
            name: "FFMpegasusCoreTests",
            dependencies: ["FFMpegasusCore"],
            path: "Tests/FFMpegasusCoreTests"
        ),
        .testTarget(
            name: "FFMpegasusGUITests",
            path: "Tests/FFMpegasusGUITests",
            exclude: ["README.md"]
        )
    ]
)
