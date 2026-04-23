// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "TokenStat",
    targets: [
        .systemLibrary(
            name: "CGtk",
            pkgConfig: "gtk+-3.0",
            providers: [.apt(["libgtk-3-dev"])]
        ),
        .systemLibrary(
            name: "CAppIndicator",
            pkgConfig: "ayatana-appindicator3-0.1",
            providers: [.apt(["libayatana-appindicator3-dev"])]
        ),
        .executableTarget(
            name: "TokenStat",
            dependencies: ["CGtk", "CAppIndicator"],
            path: "Sources/TokenStat"
        )
    ]
)
