// swift-tools-version:5.9
// Test-only package: exposes pure-logic app files to `swift test`.
// The app itself builds via YTApp.xcodeproj — this package is never shipped.
import PackageDescription

let package = Package(
    name: "YTAppCore",
    platforms: [.macOS(.v13)],
    targets: [
        .target(
            name: "YTAppCore",
            path: "YTApp/YTApp",
            sources: [
                "FuzzyMatcher.swift",
                "RateRamp.swift",
                "VideoURL.swift",
                "TranscriptParser.swift",
                "StatsAggregator.swift",
            ]
        ),
        .testTarget(
            name: "YTAppCoreTests",
            dependencies: ["YTAppCore"],
            path: "Tests"
        ),
    ]
)
