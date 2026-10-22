// swift-tools-version: 6.2
import PackageDescription

// Shared model, local store, CloudKit store, outbox, and merge rules (spec §9.2.1).
let package = Package(
    name: "SatchelKit",
    platforms: [.iOS(.v26), .macOS(.v26)],
    products: [
        .library(name: "SatchelKit", targets: ["SatchelKit"])
    ],
    dependencies: [
        // The local store: SQLite in WAL mode, migrations, FTS5 (ADR-0017). Pinned exactly; bump deliberately.
        .package(url: "https://github.com/groue/GRDB.swift", exact: "7.11.1")
    ],
    targets: [
        .target(
            name: "SatchelKit",
            dependencies: [.product(name: "GRDB", package: "GRDB.swift")]
        ),
        .testTarget(
            name: "SatchelKitTests",
            // GRDB directly too, for the schema tests that open the file without a Store.
            dependencies: ["SatchelKit", .product(name: "GRDB", package: "GRDB.swift")]
        ),
    ]
)
