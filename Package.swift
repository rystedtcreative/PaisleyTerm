// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "PaisleyTerm",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(url: "https://github.com/migueldeicaza/SwiftTerm", from: "1.2.0"),
        .package(url: "https://github.com/orlandos-nl/Citadel", from: "0.8.0"),
    ],
    targets: [
        .executableTarget(
            name: "PaisleyTerm",
            dependencies: [
                .product(name: "SwiftTerm", package: "SwiftTerm"),
                .product(name: "Citadel", package: "Citadel"),
            ],
            path: "Sources/PaisleyTerm"
        )
    ]
)
