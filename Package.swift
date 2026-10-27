// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "VenusBar",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "VenusBar", targets: ["VenusBar"])
    ],
    targets: [
        .executableTarget(name: "VenusBar", path: "Sources/VenusBar")
    ],
    swiftLanguageVersions: [.v5]
)
