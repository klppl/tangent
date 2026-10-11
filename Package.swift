// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Tangent",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "Tangent",
            path: "Sources/Tangent"
        )
    ]
)
