// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "MacSponge",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(url: "https://github.com/rive-app/rive-ios.git", from: "6.28.0")
    ],
    targets: [
        .executableTarget(
            name: "MacSponge",
            dependencies: [.product(name: "RiveRuntime", package: "rive-ios")],
            path: "Sources/MacSponge"
        )
    ]
)
