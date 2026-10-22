import Foundation

// The saved-item model (spec §7.1), mirroring `packages/model/src/item.ts` and checked against the same contract
// fixtures (`fixtures/model/`). Dates stay the ISO 8601 strings the JSON holds, so they round-trip exactly.
// Every type keeps the fields it doesn't know in `extra` and writes them back.

public let itemSchemaVersion = 1

/// `link` or `page`. Closed: a new kind would need a new schema version.
public enum ItemKind: String, Codable, Sendable, CaseIterable {
    case link
    case page
}

/// Which client saved the item. Open, so an item from a newer client still decodes.
public struct ClientID: RawRepresentable, Codable, Sendable, Hashable, ExpressibleByStringLiteral {
    public var rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public init(stringLiteral value: String) { rawValue = value }

    public init(from decoder: any Decoder) throws { rawValue = try decoder.singleValueContainer().decode(String.self) }
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    public static let chrome: ClientID = "chrome"
    public static let edge: ClientID = "edge"
    public static let safariIOS: ClientID = "safari-ios"
    public static let safariMacOS: ClientID = "safari-macos"
    public static let iosShare: ClientID = "ios-share"
    public static let iosApp: ClientID = "ios-app"
    public static let macosApp: ClientID = "macos-app"
    /// The values `packages/model` defines today (`CLIENT_IDS`).
    public static let known: [ClientID] = [.chrome, .edge, .safariIOS, .safariMacOS, .iosShare, .iosApp, .macosApp]
}

/// `pending` means the item is waiting for metadata enrichment.
public enum MetadataStatus: String, Codable, Sendable, CaseIterable {
    case complete
    case pending
    case failed
}

/// Only `remote` exists until Phase 5 stores images.
public enum ImageStatus: String, Codable, Sendable, CaseIterable {
    case remote
    case stored
    case failed
}

public struct ImageRef: Codable, Sendable, Equatable {
    public var originalURL: String
    public var alt: String?
    public var status: ImageStatus
    /// Provider-specific reference once the image is stored.
    public var assetKey: String?
    public var contentType: String?
    public var bytes: Int?
    public var extra: [String: JSONValue] = [:]

    public init(originalURL: String, alt: String? = nil, status: ImageStatus = .remote) {
        self.originalURL = originalURL
        self.alt = alt
        self.status = status
    }

    static let keys: Set<String> = ["originalUrl", "alt", "status", "assetKey", "contentType", "bytes"]

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: AnyCodingKey.self)
        originalURL = try c.decode(String.self, forKey: .init("originalUrl"))
        alt = try c.decodeIfPresent(String.self, forKey: .init("alt"))
        status = try c.decode(ImageStatus.self, forKey: .init("status"))
        assetKey = try c.decodeIfPresent(String.self, forKey: .init("assetKey"))
        contentType = try c.decodeIfPresent(String.self, forKey: .init("contentType"))
        bytes = try c.decodeIfPresent(Int.self, forKey: .init("bytes"))
        extra = try c.unknownFields(excluding: Self.keys)
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: AnyCodingKey.self)
        try c.encode(originalURL, forKey: .init("originalUrl"))
        try c.encodeIfPresent(alt, forKey: .init("alt"))
        try c.encode(status, forKey: .init("status"))
        try c.encodeIfPresent(assetKey, forKey: .init("assetKey"))
        try c.encodeIfPresent(contentType, forKey: .init("contentType"))
        try c.encodeIfPresent(bytes, forKey: .init("bytes"))
        try c.encodeUnknownFields(extra)
    }
}

public struct ItemSource: Codable, Sendable, Equatable {
    public var client: ClientID
    public var version: String
    public var extra: [String: JSONValue] = [:]

    public init(client: ClientID, version: String) {
        self.client = client
        self.version = version
    }

    static let keys: Set<String> = ["client", "version"]

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: AnyCodingKey.self)
        client = try c.decode(ClientID.self, forKey: .init("client"))
        version = try c.decode(String.self, forKey: .init("version"))
        extra = try c.unknownFields(excluding: Self.keys)
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: AnyCodingKey.self)
        try c.encode(client, forKey: .init("client"))
        try c.encode(version, forKey: .init("version"))
        try c.encodeUnknownFields(extra)
    }
}

public struct PageInfo: Codable, Sendable, Equatable {
    public var wordCount: Int
    public var readingMinutes: Int
    public var engine: String
    public var images: [ImageRef]
    public var extra: [String: JSONValue] = [:]

    public init(wordCount: Int, readingMinutes: Int, engine: String, images: [ImageRef] = []) {
        self.wordCount = wordCount
        self.readingMinutes = readingMinutes
        self.engine = engine
        self.images = images
    }

    static let keys: Set<String> = ["wordCount", "readingMinutes", "engine", "images"]

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: AnyCodingKey.self)
        wordCount = try c.decode(Int.self, forKey: .init("wordCount"))
        readingMinutes = try c.decode(Int.self, forKey: .init("readingMinutes"))
        engine = try c.decode(String.self, forKey: .init("engine"))
        images = try c.decode([ImageRef].self, forKey: .init("images"))
        extra = try c.unknownFields(excluding: Self.keys)
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: AnyCodingKey.self)
        try c.encode(wordCount, forKey: .init("wordCount"))
        try c.encode(readingMinutes, forKey: .init("readingMinutes"))
        try c.encode(engine, forKey: .init("engine"))
        try c.encode(images, forKey: .init("images"))
        try c.encodeUnknownFields(extra)
    }
}

public struct Item: Codable, Sendable, Equatable, Identifiable {
    public var schemaVersion: Int
    /// `"u_"` + the first 32 hex characters of SHA-256(normalizedURL) (§7.2).
    public var id: String
    public var kind: ItemKind
    /// As captured.
    public var url: String
    public var canonicalURL: String
    /// §7.2; the input to `id`.
    public var normalizedURL: String
    public var title: String
    public var description: String?
    public var siteName: String?
    public var author: String?
    /// ISO 8601.
    public var publishedAt: String?
    public var imageURL: String?
    public var faviconURL: String?
    public var lang: String?
    /// Lowercase, trimmed, deduplicated.
    public var tags: [String]
    public var note: String?
    /// The capture was a selection, not the whole page (FR-10).
    public var selection: Bool?
    /// First save; never changes. ISO 8601.
    public var createdAt: String
    public var updatedAt: String
    /// Last page capture.
    public var capturedAt: String?
    public var metadataStatus: MetadataStatus
    public var source: ItemSource
    public var page: PageInfo?
    public var extra: [String: JSONValue] = [:]

    public init(
        id: String, kind: ItemKind, url: String, canonicalURL: String, normalizedURL: String, title: String,
        tags: [String] = [], createdAt: String, updatedAt: String, metadataStatus: MetadataStatus, source: ItemSource
    ) {
        self.schemaVersion = itemSchemaVersion
        self.id = id
        self.kind = kind
        self.url = url
        self.canonicalURL = canonicalURL
        self.normalizedURL = normalizedURL
        self.title = title
        self.tags = tags
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.metadataStatus = metadataStatus
        self.source = source
    }

    /// The JSON keys this version knows, in `packages/model`'s spelling (`ITEM_SHAPE`).
    static let keys: Set<String> = [
        "schemaVersion", "id", "kind", "url", "canonicalUrl", "normalizedUrl", "title", "description", "siteName",
        "author", "publishedAt", "imageUrl", "faviconUrl", "lang", "tags", "note", "selection", "createdAt",
        "updatedAt", "capturedAt", "metadataStatus", "source", "page",
    ]

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: AnyCodingKey.self)
        schemaVersion = try c.decode(Int.self, forKey: .init("schemaVersion"))
        id = try c.decode(String.self, forKey: .init("id"))
        kind = try c.decode(ItemKind.self, forKey: .init("kind"))
        url = try c.decode(String.self, forKey: .init("url"))
        canonicalURL = try c.decode(String.self, forKey: .init("canonicalUrl"))
        normalizedURL = try c.decode(String.self, forKey: .init("normalizedUrl"))
        title = try c.decode(String.self, forKey: .init("title"))
        description = try c.decodeIfPresent(String.self, forKey: .init("description"))
        siteName = try c.decodeIfPresent(String.self, forKey: .init("siteName"))
        author = try c.decodeIfPresent(String.self, forKey: .init("author"))
        publishedAt = try c.decodeIfPresent(String.self, forKey: .init("publishedAt"))
        imageURL = try c.decodeIfPresent(String.self, forKey: .init("imageUrl"))
        faviconURL = try c.decodeIfPresent(String.self, forKey: .init("faviconUrl"))
        lang = try c.decodeIfPresent(String.self, forKey: .init("lang"))
        tags = try c.decode([String].self, forKey: .init("tags"))
        note = try c.decodeIfPresent(String.self, forKey: .init("note"))
        selection = try c.decodeIfPresent(Bool.self, forKey: .init("selection"))
        createdAt = try c.decode(String.self, forKey: .init("createdAt"))
        updatedAt = try c.decode(String.self, forKey: .init("updatedAt"))
        capturedAt = try c.decodeIfPresent(String.self, forKey: .init("capturedAt"))
        metadataStatus = try c.decode(MetadataStatus.self, forKey: .init("metadataStatus"))
        source = try c.decode(ItemSource.self, forKey: .init("source"))
        page = try c.decodeIfPresent(PageInfo.self, forKey: .init("page"))
        extra = try c.unknownFields(excluding: Self.keys)
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: AnyCodingKey.self)
        try c.encode(schemaVersion, forKey: .init("schemaVersion"))
        try c.encode(id, forKey: .init("id"))
        try c.encode(kind, forKey: .init("kind"))
        try c.encode(url, forKey: .init("url"))
        try c.encode(canonicalURL, forKey: .init("canonicalUrl"))
        try c.encode(normalizedURL, forKey: .init("normalizedUrl"))
        try c.encode(title, forKey: .init("title"))
        try c.encodeIfPresent(description, forKey: .init("description"))
        try c.encodeIfPresent(siteName, forKey: .init("siteName"))
        try c.encodeIfPresent(author, forKey: .init("author"))
        try c.encodeIfPresent(publishedAt, forKey: .init("publishedAt"))
        try c.encodeIfPresent(imageURL, forKey: .init("imageUrl"))
        try c.encodeIfPresent(faviconURL, forKey: .init("faviconUrl"))
        try c.encodeIfPresent(lang, forKey: .init("lang"))
        try c.encode(tags, forKey: .init("tags"))
        try c.encodeIfPresent(note, forKey: .init("note"))
        try c.encodeIfPresent(selection, forKey: .init("selection"))
        try c.encode(createdAt, forKey: .init("createdAt"))
        try c.encode(updatedAt, forKey: .init("updatedAt"))
        try c.encodeIfPresent(capturedAt, forKey: .init("capturedAt"))
        try c.encode(metadataStatus, forKey: .init("metadataStatus"))
        try c.encode(source, forKey: .init("source"))
        try c.encodeIfPresent(page, forKey: .init("page"))
        try c.encodeUnknownFields(extra)
    }
}
