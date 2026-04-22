// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "TokenStat",
    platforms: [
        .macOS(.v13)
    ],
    targets: [
        .executableTarget(
            name: "TokenStat",
            path: "Sources/TokenStat"
        )
    ]
)
