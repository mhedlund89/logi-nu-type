// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "LogiLite",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "LogiLite",
            path: "Sources/LogiLite",
            swiftSettings: [.unsafeFlags(["-swift-version", "5"])]
        )
    ]
)
