// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "LogiNuType",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "LogiNuType",
            path: "Sources/LogiNuType",
            swiftSettings: [.unsafeFlags(["-swift-version", "5"])]
        )
    ]
)
