// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "ClaudeResetTracker",
    platforms: [
        .macOS(.v13)
    ],
    targets: [
        .executableTarget(
            name: "ClaudeResetTracker",
            path: "Sources/ClaudeResetTracker"
        )
    ]
)
