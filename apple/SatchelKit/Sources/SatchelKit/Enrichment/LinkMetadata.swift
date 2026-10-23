import Foundation

/// What `captureLink` reads from a page (`PageMetadata` in `packages/capture`, spec §4.2).
public struct LinkMetadata: Codable, Sendable, Equatable {
    public var title: String
    public var description: String?
    public var siteName: String?
    public var canonicalUrl: String?
    public var imageUrl: String?
    public var author: String?
    public var publishedAt: String?
    public var faviconUrl: String?
    public var lang: String?

    public init(
        title: String, description: String? = nil, siteName: String? = nil, canonicalUrl: String? = nil,
        imageUrl: String? = nil, author: String? = nil, publishedAt: String? = nil, faviconUrl: String? = nil,
        lang: String? = nil
    ) {
        self.title = title
        self.description = description
        self.siteName = siteName
        self.canonicalUrl = canonicalUrl
        self.imageUrl = imageUrl
        self.author = author
        self.publishedAt = publishedAt
        self.faviconUrl = faviconUrl
        self.lang = lang
    }
}

extension Item {
    /// The item with what enrichment found (spec §9.2.4), marked `complete`. Blank values never replace stored ones,
    /// and identity (ID, URLs) never changes: a canonical URL found now doesn't re-key a saved item.
    public func enriched(with metadata: LinkMetadata, at timestamp: String) -> Item {
        func value(_ new: String?, else old: String?) -> String? {
            guard let trimmed = new?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
                return old
            }
            return trimmed
        }
        var item = self
        item.title = value(metadata.title, else: title) ?? title
        item.description = value(metadata.description, else: description)
        item.siteName = value(metadata.siteName, else: siteName)
        item.author = value(metadata.author, else: author)
        item.publishedAt = value(metadata.publishedAt, else: publishedAt)
        item.imageURL = value(metadata.imageUrl, else: imageURL)
        item.faviconURL = value(metadata.faviconUrl, else: faviconURL)
        item.lang = value(metadata.lang, else: lang)
        item.metadataStatus = .complete
        item.updatedAt = timestamp
        return item
    }
}
