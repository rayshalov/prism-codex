// swift-tools-version: 5.8
import PackageDescription

let package = Package(
    name: "Prism",
    platforms: [.macOS(.v13)],
    products: [.executable(name: "Prism", targets: ["Prism"])],
    targets: [
        .target(name: "PrismCore"),
        .executableTarget(name: "Prism", dependencies: ["PrismCore"]),
        .executableTarget(name: "PrismChecks", dependencies: ["PrismCore"], path: "Tests")
    ]
)
