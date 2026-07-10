// swift-tools-version: 5.9
import PackageDescription

// PaisleyCore is the platform-agnostic engine (models, agent-output parsing,
// profile storage) and builds anywhere Swift runs, including Linux. The
// PaisleyTerm executable is the macOS SwiftUI app; its Apple-only
// dependencies (SwiftTerm/AppKit, Citadel PTY) are gated to macOS so
// `swift build` / `swift test` work on Linux against the core alone.

// Zero-warning builds are the project's quality bar, enforced by the compiler
// (not by scraping the build log). Applied to PaisleyCore only for now: the
// macOS app target still has latent Swift-6 concurrency warnings (e.g. cross-
// actor access of @MainActor session state in SSHService) that a newer
// toolchain surfaces. Re-enable on PaisleyTerm once that concurrency cleanup is
// done and verified on macOS — see CONTRIBUTING.md.
let strictWarnings: [SwiftSetting] = [.unsafeFlags(["-warnings-as-errors"])]

var products: [Product] = [
    .library(name: "PaisleyCore", targets: ["PaisleyCore"]),
]

var dependencies: [Package.Dependency] = []

var targets: [Target] = [
    .target(
        name: "PaisleyCore",
        path: "Sources/PaisleyCore",
        swiftSettings: strictWarnings
    ),
    .testTarget(
        name: "PaisleyCoreTests",
        dependencies: ["PaisleyCore"],
        path: "Tests/PaisleyCoreTests",
        swiftSettings: strictWarnings
    ),
]

#if os(macOS)
dependencies += [
    .package(url: "https://github.com/migueldeicaza/SwiftTerm", from: "1.2.0"),
    .package(url: "https://github.com/orlandos-nl/Citadel", from: "0.8.0"),
]
products.append(.executable(name: "PaisleyTerm", targets: ["PaisleyTerm"]))
targets.append(
    .executableTarget(
        name: "PaisleyTerm",
        dependencies: [
            "PaisleyCore",
            .product(name: "SwiftTerm", package: "SwiftTerm"),
            .product(name: "Citadel", package: "Citadel"),
        ],
        path: "Sources/PaisleyTerm"
        // NOTE: -warnings-as-errors intentionally NOT applied here yet — the app
        // target has pre-existing Swift-6 concurrency warnings to clean up first.
    )
)
#endif

let package = Package(
    name: "PaisleyTerm",
    platforms: [.macOS(.v14)],
    products: products,
    dependencies: dependencies,
    targets: targets
)
