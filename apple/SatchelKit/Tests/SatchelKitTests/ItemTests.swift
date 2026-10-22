import Foundation
import Testing

@testable import SatchelKit

/// The contract fixtures both languages round-trip (spec §7.1), read from the repo so TypeScript and Swift test the
/// same files.
enum ContractFixtures {
    static let directory = URL(filePath: #filePath)
        .deletingLastPathComponent()  // SatchelKitTests
        .deletingLastPathComponent()  // Tests
        .deletingLastPathComponent()  // SatchelKit
        .deletingLastPathComponent()  // apple
        .deletingLastPathComponent()  // repo root
        .appending(path: "fixtures/model")

    static func all() throws -> [(name: String, data: Data)] {
        try FileManager.default.contentsOfDirectory(atPath: directory.path(percentEncoded: false))
            .filter { $0.hasSuffix(".json") }
            .sorted()
            .map { ($0, try Data(contentsOf: directory.appending(path: $0))) }
    }
}

@Suite struct ItemTests {
    @Test func fixturesExist() throws {
        #expect(
            try ContractFixtures.all().map(\.name) == ["link-minimal.json", "page-full.json", "unknown-fields.json"])
    }

    @Test(arguments: try ContractFixtures.all().map(\.name))
    func roundTripsLosslessly(name: String) throws {
        let data = try Data(contentsOf: ContractFixtures.directory.appending(path: name))
        let item = try JSONDecoder().decode(Item.self, from: data)
        let reencoded = try JSONEncoder().encode(item)
        // Same JSON value at every level: same keys, same values, nothing dropped or added.
        #expect(
            try JSONDecoder().decode(JSONValue.self, from: reencoded)
                == JSONDecoder().decode(JSONValue.self, from: data))
        // And decoding the re-encoded JSON gives the same item.
        #expect(try JSONDecoder().decode(Item.self, from: reencoded) == item)
    }

    @Test func decodesTypedFields() throws {
        let data = try Data(contentsOf: ContractFixtures.directory.appending(path: "page-full.json"))
        let item = try JSONDecoder().decode(Item.self, from: data)
        #expect(item.kind == .page)
        #expect(item.source.client == .safariIOS)
        #expect(item.tags == ["safari", "extensions", "ios"])
        #expect(item.page?.images.count == 2)
        #expect(item.page?.images.first?.alt != nil)
        #expect(item.extra.isEmpty)
    }

    @Test func keepsUnknownFieldsAtEveryLevel() throws {
        let data = try Data(contentsOf: ContractFixtures.directory.appending(path: "unknown-fields.json"))
        let item = try JSONDecoder().decode(Item.self, from: data)
        #expect(item.extra["archived"] == .bool(true))
        #expect(item.extra["x-experiment"] == .null)
        #expect(
            item.extra["readingProgress"]
                == .object(["fraction": .number(0.42), "updatedAt": .string("2026-10-22T11:00:00.000Z")]))
        #expect(item.source.extra["build"] == .number(4211))
        #expect(item.page?.extra["outline"] != nil)
        #expect(item.page?.images.first?.extra["dominantColor"] == .string("#336699"))
    }

    @Test func decodesAnUnknownClient() throws {
        let json = #"{"client":"safari-visionos","version":"2027.1.0"}"#
        let source = try JSONDecoder().decode(ItemSource.self, from: Data(json.utf8))
        #expect(source.client.rawValue == "safari-visionos")
        #expect(!ClientID.known.contains(source.client))
    }

    @Test func enumsMatchTheTypeScriptModel() {
        #expect(ItemKind.allCases.map(\.rawValue) == ["link", "page"])
        #expect(MetadataStatus.allCases.map(\.rawValue) == ["complete", "pending", "failed"])
        #expect(ImageStatus.allCases.map(\.rawValue) == ["remote", "stored", "failed"])
        #expect(
            ClientID.known.map(\.rawValue) == [
                "chrome", "edge", "safari-ios", "safari-macos", "ios-share", "ios-app", "macos-app",
            ])
    }

    @Test func knownKeysMatchTheJSONSchema() throws {
        let schemaURL = ContractFixtures.directory
            .deletingLastPathComponent().deletingLastPathComponent()
            .appending(path: "packages/model/schema/item.schema.json")
        let schema = try JSONDecoder().decode(JSONValue.self, from: Data(contentsOf: schemaURL))
        func properties(_ value: JSONValue?) -> Set<String> {
            guard case .object(let object) = value, case .object(let props)? = object["properties"] else { return [] }
            return Set(props.keys)
        }
        guard case .object(let root) = schema, case .object(let props)? = root["properties"],
            case .object(let defs)? = root["$defs"]
        else { Issue.record("unexpected schema shape"); return }
        #expect(properties(schema) == Item.keys)
        #expect(properties(props["source"]) == ItemSource.keys)
        #expect(properties(props["page"]) == PageInfo.keys)
        #expect(properties(defs["imageRef"]) == ImageRef.keys)
    }
}
