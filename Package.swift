// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Silver",
    platforms: [.macOS("26.0")],
    products: [.library(name: "SilverCore", targets: ["SilverCore"])],
    targets: [
        .target(name: "SilverCore", path: "Silver/Core"),
        .testTarget(name: "SilverCoreTests", dependencies: ["SilverCore"], path: "Tests/SilverCoreTests", resources: [.copy("Fixtures")])
    ]
)
