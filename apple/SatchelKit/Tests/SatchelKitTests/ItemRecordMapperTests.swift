import CloudKit
import Foundation
import Testing

@testable import SatchelKit

/// A mapper writing assets into its own temporary directory, removed by `cleanUp()`.
struct TestMapper {
    let mapper: ItemRecordMapper
    var directory: URL { mapper.assetDirectory }

    init() {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "SatchelKitTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        mapper = ItemRecordMapper(zoneName: "Library", assetDirectory: directory)
    }

    func files() -> [URL] {
        (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
    }

    func cleanUp() {
        try? FileManager.default.removeItem(at: directory)
    }
}

func fixtureItem(_ name: String) throws -> Item {
    try JSONDecoder().decode(Item.self, from: Data(contentsOf: ContractFixtures.directory.appending(path: name)))
}

@Suite struct ItemRecordMapperTests {
    // MARK: Record shape

    @Test func recordNameZoneAndType() throws {
        let test = TestMapper()
        defer { test.cleanUp() }
        let item = try fixtureItem("page-full.json")
        let record = try test.mapper.record(for: item, body: "# Hi")
        #expect(record.recordType == "Item")
        #expect(record.recordID.recordName == "u_6934756466cbddd7758641e28103be7e")
        #expect(record.recordID.zoneID.zoneName == "Library")
        #expect(record.recordID.zoneID.ownerName == CKCurrentUserDefaultName)
    }

    @Test func zoneComesFromTheEnvironment() {
        let environment = AppEnvironment(
            appGroup: "group.x", iCloudContainer: "iCloud.x", cloudKitZone: "Library", version: "1", build: "1")
        #expect(ItemRecordMapper(environment: environment).zoneID.zoneName == "Library")
    }

    /// The mapper's field list is exactly the `Item` record type in `apple/CloudKit/Satchel.ckdb`.
    @Test func fieldNamesMatchTheSchemaFile() throws {
        let schemaURL = ContractFixtures.directory
            .deletingLastPathComponent().deletingLastPathComponent()
            .appending(path: "apple/CloudKit/Satchel.ckdb")
        let schema = try String(contentsOf: schemaURL, encoding: .utf8)
        guard let start = schema.range(of: "RECORD TYPE Item ("),
            let end = schema.range(of: ");", range: start.upperBound..<schema.endIndex)
        else {
            Issue.record("no Item record type in Satchel.ckdb")
            return
        }
        let fields = schema[start.upperBound..<end.lowerBound]
            .split(separator: "\n")
            .compactMap { $0.split(separator: " ", omittingEmptySubsequences: true).first.map(String.init) }
            .filter { !$0.hasPrefix("\"___") && $0 != "GRANT" }
        #expect(Set(fields) == ItemRecordMapper.fieldNames)
    }

    @Test(arguments: try ContractFixtures.all().map(\.name))
    func writesOnlySchemaFields(name: String) throws {
        let test = TestMapper()
        defer { test.cleanUp() }
        let record = try test.mapper.record(for: try fixtureItem(name), body: "body")
        #expect(Set(record.allKeys()).isSubset(of: ItemRecordMapper.fieldNames))
        #expect(Set(record.changedKeys()).isSubset(of: ItemRecordMapper.fieldNames))
    }

    @Test func writesEveryFieldOfAFullItem() throws {
        let test = TestMapper()
        defer { test.cleanUp() }
        let item = try fixtureItem("page-full.json")
        let record = try test.mapper.record(for: item, body: "# Safari web extensions")
        #expect(record["schemaVersion"] as? Int64 == 1)
        #expect(record["kind"] as? String == "page")
        #expect(record["url"] as? String == item.url)
        #expect(record["canonicalUrl"] as? String == item.canonicalURL)
        #expect(record["normalizedUrl"] as? String == item.normalizedURL)
        #expect(record["title"] as? String == "Safari web extensions")
        #expect(record["description"] as? String == item.description)
        #expect(record["siteName"] as? String == "Apple Developer Documentation")
        #expect(record["author"] as? String == "Apple Inc.")
        #expect(record["imageUrl"] as? String == item.imageURL)
        #expect(record["faviconUrl"] as? String == item.faviconURL)
        #expect(record["lang"] as? String == "en-US")
        #expect(record["tags"] as? [String] == ["safari", "extensions", "ios"])
        #expect(record["note"] as? String == item.note)
        #expect(record["metadataStatus"] as? String == "complete")
        #expect(record["body"] as? String == "# Safari web extensions")
        #expect(record["bodyAsset"] == nil)
        let createdAt = try #require(record["createdAt"] as? Date)
        #expect(CloudKitTimestamp.string(from: createdAt) == "2026-10-20T09:15:00.000Z")
        let updatedAt = try #require(record["updatedAt"] as? Date)
        #expect(updatedAt.timeIntervalSince1970 == 1_792_687_227.512)
        #expect(record["capturedAt"] as? Date == updatedAt)
        #expect(record["publishedAt"] is Date)
        // source and page are JSON strings that decode to the same values.
        let source = try #require(record["source"] as? String)
        #expect(try JSONDecoder().decode(ItemSource.self, from: Data(source.utf8)) == item.source)
        let page = try #require(record["page"] as? String)
        #expect(try JSONDecoder().decode(PageInfo.self, from: Data(page.utf8)) == item.page)
    }

    @Test func leavesAbsentFieldsUnsetOnANewRecord() throws {
        let test = TestMapper()
        defer { test.cleanUp() }
        let record = try test.mapper.record(for: try fixtureItem("link-minimal.json"), body: nil)
        // Not even as nil, so a .changedKeys save can't blank what another device wrote.
        for key in [
            "description", "siteName", "author", "publishedAt", "imageUrl", "faviconUrl", "lang", "tags", "note",
        ] {
            #expect(!record.changedKeys().contains(key), "\(key)")
        }
        #expect(!record.changedKeys().contains("page"))
        #expect(!record.changedKeys().contains("capturedAt"))
    }

    @Test func clearsAbsentFieldsOnABaseRecord() throws {
        let test = TestMapper()
        defer { test.cleanUp() }
        let full = try fixtureItem("page-full.json")
        let server = try test.mapper.record(for: full, body: "old")
        var trimmed = full
        trimmed.description = nil
        trimmed.note = nil
        trimmed.tags = []
        trimmed.page = nil
        let record = try test.mapper.record(for: trimmed, body: nil, updating: server)
        #expect(record === server)
        #expect(record["description"] == nil)
        #expect(record["note"] == nil)
        #expect(record["tags"] == nil)
        #expect(record["page"] == nil)
        #expect(record["title"] as? String == full.title)
        #expect(record["body"] as? String == "old")
    }

    @Test func rejectsAMismatchedBaseRecord() throws {
        let test = TestMapper()
        defer { test.cleanUp() }
        let item = try fixtureItem("link-minimal.json")
        let other = CKRecord(recordType: "Item", recordID: test.mapper.recordID(forItemID: "u_other"))
        #expect(throws: ItemRecordMappingError.recordIDMismatch("u_other")) {
            try test.mapper.record(for: item, body: nil, updating: other)
        }
        let wrongType = CKRecord(recordType: "ImageAsset", recordID: test.mapper.recordID(forItemID: item.id))
        #expect(throws: ItemRecordMappingError.wrongRecordType("ImageAsset")) {
            try test.mapper.record(for: item, body: nil, updating: wrongType)
        }
    }

    // MARK: Round trips

    @Test(arguments: try ContractFixtures.all().map(\.name))
    func roundTripsWithTheLocalCopy(name: String) throws {
        let test = TestMapper()
        defer { test.cleanUp() }
        let item = try fixtureItem(name)
        let record = try test.mapper.record(for: item, body: "# \(name)")
        #expect(try test.mapper.item(from: record, existing: item) == item)
        #expect(try test.mapper.body(from: record) == "# \(name)")
    }

    /// With no local copy, everything comes back except what CloudKit has no column for.
    @Test(arguments: try ContractFixtures.all().map(\.name))
    func roundTripsWithoutTheLocalCopy(name: String) throws {
        let test = TestMapper()
        defer { test.cleanUp() }
        let item = try fixtureItem(name)
        var expected = item
        expected.extra = [:]
        let decoded = try test.mapper.item(from: try test.mapper.record(for: item, body: nil))
        #expect(decoded == expected)
        // The fixtures' timestamps are toISOString() strings, so they come back unchanged.
        #expect(decoded.createdAt == item.createdAt)
        #expect(decoded.updatedAt == item.updatedAt)
        #expect(decoded.capturedAt == item.capturedAt)
        #expect(decoded.publishedAt == item.publishedAt)
    }

    @Test func nestedUnknownFieldsSurviveInTheJSONFields() throws {
        let test = TestMapper()
        defer { test.cleanUp() }
        let item = try fixtureItem("unknown-fields.json")
        let decoded = try test.mapper.item(from: try test.mapper.record(for: item, body: nil))
        #expect(decoded.source.extra["build"] == .number(4211))
        #expect(decoded.page?.extra["outline"] == item.page?.extra["outline"])
        #expect(decoded.page?.images.first?.extra["dominantColor"] == .string("#336699"))
        #expect(decoded.page?.images.first?.extra["width"] == .number(640))
        // Top-level unknown fields have no column, so they come only from the local copy.
        #expect(decoded.extra.isEmpty)
        #expect(
            try test.mapper.item(from: try test.mapper.record(for: item, body: nil), existing: item).extra.count == 4)
    }

    @Test func ignoresALocalCopyWithAnotherID() throws {
        let test = TestMapper()
        defer { test.cleanUp() }
        let item = try fixtureItem("link-minimal.json")
        var other = try fixtureItem("unknown-fields.json")
        other.selection = true
        let decoded = try test.mapper.item(from: try test.mapper.record(for: item, body: nil), existing: other)
        #expect(decoded.extra.isEmpty)
        #expect(decoded.selection == nil)
    }

    @Test(arguments: [true, false])
    func selectionRoundTrips(flag: Bool) throws {
        let test = TestMapper()
        defer { test.cleanUp() }
        var item = try fixtureItem("page-full.json")
        item.selection = flag
        let record = try test.mapper.record(for: item, body: nil)
        #expect(record["selection"] as? Int64 == (flag ? 1 : 0))
        #expect(try test.mapper.item(from: record).selection == flag)
    }

    @Test func emptyTagsComeBackEmpty() throws {
        let test = TestMapper()
        defer { test.cleanUp() }
        let item = try fixtureItem("link-minimal.json")
        let record = try test.mapper.record(for: item, body: nil)
        #expect(record["tags"] == nil)
        #expect(try test.mapper.item(from: record).tags == [])
    }

    // MARK: Body

    @Test func bodyOfExactly512KBIsInline() throws {
        let test = TestMapper()
        defer { test.cleanUp() }
        let body = String(repeating: "a", count: 512 * 1024)
        let record = try test.mapper.record(for: try fixtureItem("page-full.json"), body: body)
        #expect(record["body"] as? String == body)
        #expect(record["bodyAsset"] == nil)
        #expect(record.changedKeys().contains("bodyAsset"))  // cleared, not just unset
        #expect(test.files().isEmpty)
    }

    @Test func oneByteMoreGoesToAnAsset() throws {
        let test = TestMapper()
        defer { test.cleanUp() }
        let body = String(repeating: "a", count: 512 * 1024 + 1)
        let record = try test.mapper.record(for: try fixtureItem("page-full.json"), body: body)
        #expect(record["body"] == nil)
        #expect(record.changedKeys().contains("body"))  // cleared, not just unset
        let asset = try #require(record["bodyAsset"] as? CKAsset)
        let url = try #require(asset.fileURL)
        #expect(url.deletingLastPathComponent().lastPathComponent == test.directory.lastPathComponent)
        #expect(try Data(contentsOf: url).count == 512 * 1024 + 1)
        #expect(try test.mapper.body(from: record) == body)
    }

    @Test func sizeIsCountedInUTF8Bytes() throws {
        let test = TestMapper()
        defer { test.cleanUp() }
        let item = try fixtureItem("page-full.json")
        // "é" is 2 bytes: 262,144 of them are exactly 512 KB.
        let twoByte = String(repeating: "é", count: 256 * 1024)
        #expect(try test.mapper.record(for: item, body: twoByte)["body"] as? String == twoByte)
        let overByOne = twoByte + "a"
        #expect(try test.mapper.record(for: item, body: overByOne)["bodyAsset"] is CKAsset)
        // "€" is 3 bytes: far fewer than 512 K characters, but more than 512 KB.
        let threeByte = String(repeating: "€", count: 174_763)
        #expect(threeByte.count < 512 * 1024 && threeByte.utf8.count == 512 * 1024 + 1)
        let record = try test.mapper.record(for: item, body: threeByte)
        #expect(record["body"] == nil)
        #expect(try test.mapper.body(from: record) == threeByte)
    }

    @Test func nilBodyLeavesBothBodyFieldsAlone() throws {
        let test = TestMapper()
        defer { test.cleanUp() }
        let item = try fixtureItem("page-full.json")
        let record = try test.mapper.record(for: item, body: nil)
        #expect(!record.changedKeys().contains("body"))
        #expect(!record.changedKeys().contains("bodyAsset"))
        #expect(try test.mapper.body(from: record) == nil)
        // And on a base record that has a body, it's kept.
        let server = try test.mapper.record(for: item, body: "kept")
        #expect(try test.mapper.body(from: try test.mapper.record(for: item, body: nil, updating: server)) == "kept")
    }

    @Test func switchingFromAssetToInlineClearsTheAsset() throws {
        let test = TestMapper()
        defer { test.cleanUp() }
        let item = try fixtureItem("page-full.json")
        let server = try test.mapper.record(for: item, body: String(repeating: "a", count: 600_000))
        let record = try test.mapper.record(for: item, body: "short", updating: server)
        #expect(record["bodyAsset"] == nil)
        #expect(try test.mapper.body(from: record) == "short")
    }

    @Test func readerPrefersBodyOverAsset() throws {
        let test = TestMapper()
        defer { test.cleanUp() }
        let record = try test.mapper.record(
            for: try fixtureItem("page-full.json"), body: String(repeating: "a", count: 600_000))
        record["body"] = "inline wins"
        #expect(try test.mapper.body(from: record) == "inline wins")
    }

    @Test func unreadableAssetThrows() throws {
        let test = TestMapper()
        defer { test.cleanUp() }
        let record = try test.mapper.record(
            for: try fixtureItem("page-full.json"), body: String(repeating: "a", count: 600_000))
        test.mapper.removeAssetFile(of: record)
        #expect(throws: ItemRecordMappingError.unreadableBodyAsset) { try test.mapper.body(from: record) }
    }

    // MARK: Asset files

    @Test func removesItsOwnAssetFile() throws {
        let test = TestMapper()
        defer { test.cleanUp() }
        let record = try test.mapper.record(
            for: try fixtureItem("page-full.json"), body: String(repeating: "a", count: 600_000))
        #expect(test.files().count == 1)
        test.mapper.removeAssetFile(of: record)
        #expect(test.files().isEmpty)
    }

    @Test func neverRemovesFilesOutsideItsDirectory() throws {
        let test = TestMapper()
        let elsewhere = TestMapper()
        defer {
            test.cleanUp()
            elsewhere.cleanUp()
        }
        let record = try elsewhere.mapper.record(
            for: try fixtureItem("page-full.json"), body: String(repeating: "a", count: 600_000))
        test.mapper.removeAssetFile(of: record)
        #expect(elsewhere.files().count == 1)
    }

    @Test func sweepsStaleAssetFiles() throws {
        let test = TestMapper()
        defer { test.cleanUp() }
        let item = try fixtureItem("page-full.json")
        _ = try test.mapper.record(for: item, body: String(repeating: "a", count: 600_000))
        _ = try test.mapper.record(for: item, body: String(repeating: "b", count: 600_000))
        #expect(test.files().count == 2)  // unique names: two saves of one item don't collide
        test.mapper.removeAssetFiles(olderThan: 3600)
        #expect(test.files().count == 2)
        test.mapper.removeAssetFiles(olderThan: 3600, now: Date().addingTimeInterval(7200))
        #expect(test.files().isEmpty)
    }

    // MARK: Timestamps

    @Test func timestampFormats() throws {
        func roundTrip(_ string: String) throws -> String {
            CloudKitTimestamp.string(from: try #require(CloudKitTimestamp.date(from: string)))
        }
        #expect(try roundTrip("2026-10-22T16:40:27.512Z") == "2026-10-22T16:40:27.512Z")
        #expect(try roundTrip("2026-10-22T14:03:11.000Z") == "2026-10-22T14:03:11.000Z")
        #expect(try roundTrip("1969-12-31T23:59:59.999Z") == "1969-12-31T23:59:59.999Z")
        #expect(try roundTrip("2026-10-22T16:40:27Z") == "2026-10-22T16:40:27.000Z")
        #expect(try roundTrip("2026-10-22T18:40:27.512+02:00") == "2026-10-22T16:40:27.512Z")
        #expect(try roundTrip("2026-10-22T16:40:27.5Z") == "2026-10-22T16:40:27.500Z")
        #expect(try roundTrip("2026-10-22T16:40:27.1239Z") == "2026-10-22T16:40:27.124Z")
        #expect(CloudKitTimestamp.date(from: "2026-10-22") == nil)
        #expect(CloudKitTimestamp.date(from: "yesterday") == nil)
    }

    @Test func everyMillisecondOfASecondRoundTrips() {
        let base = 1_792_687_227
        for millisecond in 0..<1000 {
            let date = Date(timeIntervalSince1970: TimeInterval(base) + TimeInterval(millisecond) / 1000)
            let string = CloudKitTimestamp.string(from: date)
            #expect(string.hasSuffix(String(format: ".%03dZ", millisecond)))
            #expect(CloudKitTimestamp.date(from: string).map { CloudKitTimestamp.sameMillisecond($0, date) } == true)
        }
    }

    @Test func keepsALocalStringForTheSameInstant() throws {
        let test = TestMapper()
        defer { test.cleanUp() }
        var item = try fixtureItem("link-minimal.json")
        item.createdAt = "2026-10-22T16:03:11+02:00"
        item.updatedAt = "2026-10-22T14:03:11Z"
        let record = try test.mapper.record(for: item, body: nil)
        // Without the local copy: the same instants in toISOString() form.
        let fresh = try test.mapper.item(from: record)
        #expect(fresh.createdAt == "2026-10-22T14:03:11.000Z")
        #expect(fresh.updatedAt == "2026-10-22T14:03:11.000Z")
        // With it: the local strings, since they name the same millisecond.
        #expect(try test.mapper.item(from: record, existing: item) == item)
        // A newer server date replaces the local string.
        record["updatedAt"] = CloudKitTimestamp.date(from: "2026-10-23T00:00:00.000Z")
        #expect(try test.mapper.item(from: record, existing: item).updatedAt == "2026-10-23T00:00:00.000Z")
    }

    @Test func rejectsAnInvalidTimestamp() throws {
        let test = TestMapper()
        defer { test.cleanUp() }
        var item = try fixtureItem("link-minimal.json")
        item.publishedAt = "June 2026"
        #expect(throws: ItemRecordMappingError.invalidTimestamp(field: "publishedAt", value: "June 2026")) {
            try test.mapper.record(for: item, body: nil)
        }
    }

    // MARK: Reading bad records

    @Test func rejectsBadRecords() throws {
        let test = TestMapper()
        defer { test.cleanUp() }
        let item = try fixtureItem("link-minimal.json")
        let wrongType = CKRecord(recordType: "Users")
        #expect(throws: ItemRecordMappingError.wrongRecordType("Users")) { try test.mapper.item(from: wrongType) }

        let missingTitle = try test.mapper.record(for: item, body: nil)
        missingTitle["title"] = nil
        #expect(throws: ItemRecordMappingError.missingField("title")) { try test.mapper.item(from: missingTitle) }

        let unknownKind = try test.mapper.record(for: item, body: nil)
        unknownKind["kind"] = "video"
        #expect(throws: ItemRecordMappingError.invalidField("kind")) { try test.mapper.item(from: unknownKind) }

        let badSource = try test.mapper.record(for: item, body: nil)
        badSource["source"] = "{not json"
        #expect(throws: ItemRecordMappingError.invalidField("source")) { try test.mapper.item(from: badSource) }

        let wrongFieldType = try test.mapper.record(for: item, body: nil)
        wrongFieldType["url"] = 42
        #expect(throws: ItemRecordMappingError.invalidField("url")) { try test.mapper.item(from: wrongFieldType) }
    }
}
