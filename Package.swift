// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "MpvPlayerUI",
    platforms: [
        .macOS(.v13)
    ],
    targets: [
        .executableTarget(
            name: "MpvPlayerUI",
            path: "Sources/MpvPlayerUI"
        )
    ]
)
