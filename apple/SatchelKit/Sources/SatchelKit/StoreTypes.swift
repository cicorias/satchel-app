import Foundation

/// Narrows `Store.items(matching:filter:)`. Every field left `nil` matches everything.
public struct ItemFilter: Sendable, Equatable {
    public enum Order: Sendable, Equatable {
        /// Most recently updated first (re-saves and enrichment move an item up). The library default.
        case recentlyUpdated
        /// Most recently saved first (`createdAt`).
        case recentlyCreated
        /// Best search match first, then most recently updated. Without a query, the same as `recentlyUpdated`.
        case relevance
    }

    public var kind: ItemKind?
    /// Matched exactly after lowercasing and trimming, like the stored tags.
    public var tag: String?
    public var metadataStatus: MetadataStatus?
    public var order: Order
    public var limit: Int?

    public init(
        kind: ItemKind? = nil, tag: String? = nil, metadataStatus: MetadataStatus? = nil,
        order: Order = .recentlyUpdated, limit: Int? = nil
    ) {
        self.kind = kind
        self.tag = tag
        self.metadataStatus = metadataStatus
        self.order = order
        self.limit = limit
    }
}

public enum OutboxOperation: String, Codable, Sendable, CaseIterable {
    case upsert
    case delete
}

/// `pending` → `sent` or `failed`; a `failed` entry stays in `Store.pendingOutbox(limit:)` until it is sent or
/// replaced by a newer save or delete of the same item.
public enum OutboxState: String, Codable, Sendable, CaseIterable {
    case pending
    case sent
    case failed
}

/// One change waiting to reach the storage provider (FR-8). The store keeps at most one entry per item: a new save
/// or delete replaces the previous entry, so a stale `markSent` for a replaced entry does nothing.
public struct OutboxEntry: Sendable, Equatable, Identifiable {
    public typealias ID = Int64

    public let id: ID
    public let itemID: String
    public let operation: OutboxOperation
    /// The merged item as saved, for an `upsert`; `nil` for a `delete`. Read the body with `Store.body(for:)`.
    public let item: Item?
    public let state: OutboxState
    public let attempts: Int
    public let lastError: String?
    public let createdAt: Date
    public let updatedAt: Date
}

public enum StoreError: Error, Equatable {
    /// The App Group container isn't available (a missing entitlement, or the wrong identifier).
    case appGroupUnavailable(String)
    /// The merge function returned an item with a different ID.
    case mergeChangedID(expected: String, actual: String)
    /// `notify_register_dispatch` failed with this status.
    case changeNotificationUnavailable(UInt32)
}
