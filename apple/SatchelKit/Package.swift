// swift-tools-version: 6.2
import PackageDescription

// Shared model, local store, CloudKit store, outbox, and merge rules (spec §9.2.1).
// Phase 3 adds GRDB (ADR-0017).
let package = Package(
    name: "SatchelKit",
    platforms: [.iOS(.v26), .macOS(.v26)],
    products: [
        .library(name: "SatchelKit", targets: ["SatchelKit"])
    ],
    targets: [
        .target(name: "SatchelKit"),
        .testTarget(name: "SatchelKitTests", dependencies: ["SatchelKit"]),
    ]
)
