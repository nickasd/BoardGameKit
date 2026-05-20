// swift-tools-version: 6.3

import PackageDescription

let package = Package(
    name: "BoardGameKit",
    platforms: [
        .macOS(.v12), .iOS(.v15)
    ],
    products: [
        .library(
            name: "BoardGameKit",
            targets: ["BoardGameKit"]
        ),
    ],
    dependencies: [
        .package(path: "~/Documents/games/BoardGameKitHost")
    ],
    targets: [
        .target(
            name: "BoardGameKit",
            dependencies: ["BoardGameKitHost"]
        ),
    ],
    swiftLanguageModes: [.v5]
)
