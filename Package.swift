// swift-tools-version:5.8
import PackageDescription

let package = Package(
    name: "AudioDoctor",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "AudioDoctor",
            path: "Sources/AudioDoctor"
        )
    ]
)
