// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "VenusBar",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "VenusBar", targets: ["VenusBar"])
    ],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.10.1")
    ],
    targets: [
        .executableTarget(name: "VenusBar", dependencies: [.product(name: "Sparkle", package: "Sparkle")], path: "Sources/VenusBar")
    ],
    swiftLanguageVersions: [.v5]
)
