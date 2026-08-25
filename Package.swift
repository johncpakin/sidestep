// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Sidestep",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "Sidestep",
            path: "Sources/Sidestep",
            exclude: ["Resources"],
            swiftSettings: [.unsafeFlags(["-parse-as-library"])]
        )
    ]
)
