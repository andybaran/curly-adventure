// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "HeartRateRecorder",
    platforms: [
        .macOS(.v13)
    ],
    targets: [
        .executableTarget(
            name: "HeartRateRecorder",
            path: "Sources"
        )
    ]
)
