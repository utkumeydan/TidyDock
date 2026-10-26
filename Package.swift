// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "TidyDock",
    defaultLocalization: "en",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "TidyDock", targets: ["TidyDock"]),
    ],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.6.0"),
    ],
    targets: [
        // Pure decision logic with no AppKit dependency, so it can be unit tested.
        .target(
            name: "TidyDockCore",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .executableTarget(
            name: "TidyDock",
            dependencies: [
                "TidyDockCore",
                .product(name: "Sparkle", package: "Sparkle"),
            ],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "TidyDockCoreTests",
            dependencies: ["TidyDockCore"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
