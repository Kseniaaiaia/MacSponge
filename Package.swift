// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "MacSponge",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(name: "MacSponge", path: "Sources/MacSponge")
    ]
)
