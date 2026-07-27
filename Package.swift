// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "MpvYoutubePlayer",
    platforms: [
        .macOS(.v13)
    ],
    targets: [
        .executableTarget(
            name: "MpvYoutubePlayer",
            path: "Sources/MpvYoutubePlayer"
        )
    ]
)
