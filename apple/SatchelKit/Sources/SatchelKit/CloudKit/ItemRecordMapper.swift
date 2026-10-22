import CloudKit
import Foundation

/// Maps an `Item` and its Markdown body to and from a CloudKit `Item` record (spec §8.2,
/// `apple/CloudKit/Satchel.ckdb`).
///
/// - **Record:** type `Item`, record name = `Item.id`, in the zone named by `AppEnvironment.cloudKitZone` (`Library`).
/// - **Fields** use `packages/model`'s JSON spelling (`canonicalUrl`, `imageUrl`, …). Timestamps are TIMESTAMP fields,
///   converted by `CloudKitTimestamp`. `source` and `page` are JSON strings written with the Codable types, so their
///   unknown fields survive. `tags` is a string list.
/// - **Body:** at most `maxInlineBodyBytes` of UTF-8 goes in `body`; anything larger goes in `bodyAsset`, a file the
///   mapper writes into `assetDirectory`. A writer sets one and clears the other.
/// - **Not in the record:** CloudKit has no column for `Item.selection` or for `Item.extra` (fields from a newer
///   client). They stay in the local store, and `item(from:existing:)` carries them over from the local copy.
public struct ItemRecordMapper: Sendable {
    public static let recordType: CKRecord.RecordType = "Item"
    /// 512 KB. A body this size or smaller is stored inline; CloudKit records are limited to 1 MB in all.
    public static let maxInlineBodyBytes = 512 * 1024

    /// The `Item` fields in `Satchel.ckdb`, excluding CloudKit's `___` system fields.
    public static let fieldNames: Set<String> = [
        "author", "body", "bodyAsset", "canonicalUrl", "capturedAt", "createdAt", "description", "faviconUrl",
        "imageUrl", "kind", "lang", "metadataStatus", "normalizedUrl", "note", "page", "publishedAt", "schemaVersion",
        "siteName", "source", "tags", "title", "updatedAt", "url",
    ]

    public let zoneID: CKRecordZone.ID
    /// Where `bodyAsset` files are written. They must outlive the save that uploads them; see `removeAssetFile(of:)`
    /// and `removeAssetFiles(olderThan:)`.
    public let assetDirectory: URL

    public init(zoneName: String, assetDirectory: URL = ItemRecordMapper.defaultAssetDirectory) {
        zoneID = CKRecordZone.ID(zoneName: zoneName, ownerName: CKCurrentUserDefaultName)
        self.assetDirectory = assetDirectory
    }

    public init(environment: AppEnvironment, assetDirectory: URL = ItemRecordMapper.defaultAssetDirectory) {
        self.init(zoneName: environment.cloudKitZone, assetDirectory: assetDirectory)
    }

    /// `<process temporary directory>/SatchelBodyAssets/`.
    public static var defaultAssetDirectory: URL {
        FileManager.default.temporaryDirectory.appending(path: "SatchelBodyAssets", directoryHint: .isDirectory)
    }

    public func recordID(forItemID id: String) -> CKRecord.ID {
        CKRecord.ID(recordName: id, zoneID: zoneID)
    }

    // MARK: Item → record

    /// The record for `item`.
    ///
    /// - Parameters:
    ///   - body: the Markdown to store, or nil to leave `body` and `bodyAsset` untouched (a metadata-only save).
    ///     A non-nil body sets one of the two fields and sets the other to nil, so a save with `.changedKeys` clears
    ///     the server's old copy.
    ///   - base: a record to update in place, such as the server copy from a conflict or one rebuilt from saved system
    ///     fields. It must have this item's record ID. Without it, a new record is created.
    ///
    /// On a new record, fields the item doesn't have are left unset, so a `.changedKeys` save never blanks a value
    /// another device wrote (the §7.3 rule that an empty value never overwrites a non-empty one). On a `base` record,
    /// they're set to nil, so the record matches the item exactly.
    public func record(for item: Item, body: String?, updating base: CKRecord? = nil) throws(ItemRecordMappingError)
        -> CKRecord
    {
        let id = recordID(forItemID: item.id)
        let record: CKRecord
        if let base {
            guard base.recordType == Self.recordType else { throw .wrongRecordType(base.recordType) }
            guard base.recordID == id else { throw .recordIDMismatch(base.recordID.recordName) }
            record = base
        } else {
            record = CKRecord(recordType: Self.recordType, recordID: id)
        }
        let clearsMissing = base != nil

        func set<Value: CKRecordValueProtocol>(_ key: String, _ value: Value?) {
            if let value {
                record[key] = value
            } else if clearsMissing {
                record[key] = nil
            }
        }
        func setDate(_ key: String, _ value: String?) throws(ItemRecordMappingError) {
            guard let value else { return set(key, nil as Date?) }
            guard let date = CloudKitTimestamp.date(from: value) else {
                throw .invalidTimestamp(field: key, value: value)
            }
            set(key, date)
        }

        set("schemaVersion", Int64(item.schemaVersion))
        set("kind", item.kind.rawValue)
        set("url", item.url)
        set("canonicalUrl", item.canonicalURL)
        set("normalizedUrl", item.normalizedURL)
        set("title", item.title)
        set("description", item.description)
        set("siteName", item.siteName)
        set("author", item.author)
        try setDate("publishedAt", item.publishedAt)
        set("imageUrl", item.imageURL)
        set("faviconUrl", item.faviconURL)
        set("lang", item.lang)
        // CloudKit reads an empty list back as no value, so an empty tag list is written as an absent field.
        set("tags", item.tags.isEmpty ? nil : item.tags)
        set("note", item.note)
        try setDate("createdAt", item.createdAt)
        try setDate("updatedAt", item.updatedAt)
        try setDate("capturedAt", item.capturedAt)
        set("metadataStatus", item.metadataStatus.rawValue)
        set("source", try json(item.source, field: "source"))
        set("page", try item.page.map { value throws(ItemRecordMappingError) in try json(value, field: "page") })

        if let body {
            let bytes = Data(body.utf8)
            if bytes.count <= Self.maxInlineBodyBytes {
                record["body"] = body
                record["bodyAsset"] = nil
            } else {
                record["body"] = nil
                record["bodyAsset"] = CKAsset(fileURL: try writeAssetFile(bytes, itemID: item.id))
            }
        }
        return record
    }

    // MARK: Record → item

    /// The item `record` holds.
    ///
    /// - Parameter existing: the local copy, if any. When its ID matches, its `extra` fields and `selection` (which
    ///   CloudKit has no column for) are carried over, and each of its timestamp strings is kept when it names the
    ///   same millisecond as the record's date, so a local `+02:00` or no-fraction string isn't rewritten.
    public func item(from record: CKRecord, existing: Item? = nil) throws(ItemRecordMappingError) -> Item {
        guard record.recordType == Self.recordType else { throw .wrongRecordType(record.recordType) }
        let id = record.recordID.recordName
        let existing = existing?.id == id ? existing : nil

        func optionalString(_ key: String) throws(ItemRecordMappingError) -> String? {
            guard let value = record[key] else { return nil }
            guard let string = value as? String else { throw .invalidField(key) }
            return string
        }
        func string(_ key: String) throws(ItemRecordMappingError) -> String {
            guard let value = try optionalString(key) else { throw .missingField(key) }
            return value
        }
        func optionalDate(_ key: String, local: String?) throws(ItemRecordMappingError) -> String? {
            guard let value = record[key] else { return nil }
            guard let date = value as? Date else { throw .invalidField(key) }
            if let local, let localDate = CloudKitTimestamp.date(from: local),
                CloudKitTimestamp.sameMillisecond(localDate, date)
            {
                return local
            }
            return CloudKitTimestamp.string(from: date)
        }
        func date(_ key: String, local: String?) throws(ItemRecordMappingError) -> String {
            guard let value = try optionalDate(key, local: local) else { throw .missingField(key) }
            return value
        }

        guard let schemaVersionValue = record["schemaVersion"] else { throw .missingField("schemaVersion") }
        guard let schemaVersion = schemaVersionValue as? Int else { throw .invalidField("schemaVersion") }
        guard let kind = ItemKind(rawValue: try string("kind")) else { throw .invalidField("kind") }
        guard let metadataStatus = MetadataStatus(rawValue: try string("metadataStatus")) else {
            throw .invalidField("metadataStatus")
        }
        let tags: [String]
        if let value = record["tags"] {
            guard let list = value as? [String] else { throw .invalidField("tags") }
            tags = list
        } else {
            tags = []
        }

        var item = Item(
            id: id, kind: kind, url: try string("url"), canonicalURL: try string("canonicalUrl"),
            normalizedURL: try string("normalizedUrl"), title: try string("title"), tags: tags,
            createdAt: try date("createdAt", local: existing?.createdAt),
            updatedAt: try date("updatedAt", local: existing?.updatedAt), metadataStatus: metadataStatus,
            source: try decode(ItemSource.self, from: try string("source"), field: "source"))
        item.schemaVersion = schemaVersion
        item.description = try optionalString("description")
        item.siteName = try optionalString("siteName")
        item.author = try optionalString("author")
        item.publishedAt = try optionalDate("publishedAt", local: existing?.publishedAt)
        item.imageURL = try optionalString("imageUrl")
        item.faviconURL = try optionalString("faviconUrl")
        item.lang = try optionalString("lang")
        item.note = try optionalString("note")
        item.capturedAt = try optionalDate("capturedAt", local: existing?.capturedAt)
        if let page = try optionalString("page") {
            item.page = try decode(PageInfo.self, from: page, field: "page")
        }
        item.selection = existing?.selection
        item.extra = existing?.extra ?? [:]
        return item
    }

    /// The Markdown `record` holds: `body` if set, otherwise the contents of `bodyAsset`, otherwise nil.
    public func body(from record: CKRecord) throws(ItemRecordMappingError) -> String? {
        if let value = record["body"] {
            guard let body = value as? String else { throw .invalidField("body") }
            return body
        }
        guard let value = record["bodyAsset"] else { return nil }
        guard let asset = value as? CKAsset, let url = asset.fileURL else { throw .invalidField("bodyAsset") }
        guard let data = try? Data(contentsOf: url) else { throw .unreadableBodyAsset }
        guard let body = String(data: data, encoding: .utf8) else { throw .unreadableBodyAsset }
        return body
    }

    // MARK: Asset files

    /// Deletes the `bodyAsset` file this mapper wrote for `record`, once the save that uploads it has finished.
    /// Files outside `assetDirectory` (such as CloudKit's own download cache) are never touched.
    public func removeAssetFile(of record: CKRecord) {
        guard let asset = record["bodyAsset"] as? CKAsset, let url = asset.fileURL, isInAssetDirectory(url) else {
            return
        }
        try? FileManager.default.removeItem(at: url)
    }

    /// Deletes asset files older than `age`: the ones left behind when a process ended before its save finished
    /// (an extension killed mid-upload, or a save that timed out and may still have been uploading).
    public func removeAssetFiles(olderThan age: TimeInterval, now: Date = Date()) {
        let fileManager = FileManager.default
        guard
            let files = try? fileManager.contentsOfDirectory(
                at: assetDirectory, includingPropertiesForKeys: [.contentModificationDateKey])
        else { return }
        for file in files {
            let modified = (try? file.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
            if let modified, now.timeIntervalSince(modified) > age {
                try? fileManager.removeItem(at: file)
            }
        }
    }

    private func writeAssetFile(_ bytes: Data, itemID: String) throws(ItemRecordMappingError) -> URL {
        // A unique name, so two saves of the same item never share (or delete) each other's file.
        let url = assetDirectory.appending(path: "\(itemID)-\(UUID().uuidString).md", directoryHint: .notDirectory)
        do {
            try FileManager.default.createDirectory(at: assetDirectory, withIntermediateDirectories: true)
            try bytes.write(to: url, options: .atomic)
        } catch {
            throw .assetWriteFailed(String(describing: error))
        }
        return url
    }

    private func isInAssetDirectory(_ url: URL) -> Bool {
        url.deletingLastPathComponent().resolvingSymlinksInPath().standardizedFileURL.path
            == assetDirectory.resolvingSymlinksInPath().standardizedFileURL.path
    }

    // MARK: JSON fields

    private func json(_ value: some Encodable, field: String) throws(ItemRecordMappingError) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        guard let data = try? encoder.encode(value), let string = String(data: data, encoding: .utf8) else {
            throw .invalidField(field)
        }
        return string
    }

    private func decode<T: Decodable>(_ type: T.Type, from string: String, field: String)
        throws(ItemRecordMappingError) -> T
    {
        guard let value = try? JSONDecoder().decode(type, from: Data(string.utf8)) else { throw .invalidField(field) }
        return value
    }
}

public enum ItemRecordMappingError: Error, Equatable, Sendable {
    /// The record isn't an `Item` record.
    case wrongRecordType(String)
    /// The `updating:` record has a different record ID from the item.
    case recordIDMismatch(String)
    /// A field `Item` requires is absent.
    case missingField(String)
    /// A field holds the wrong type, an unknown enum value, or JSON that doesn't decode.
    case invalidField(String)
    /// An `Item` timestamp isn't an RFC 3339 date-time, so it has no TIMESTAMP value.
    case invalidTimestamp(field: String, value: String)
    case assetWriteFailed(String)
    /// `bodyAsset` has no readable file, or the file isn't UTF-8.
    case unreadableBodyAsset
}
