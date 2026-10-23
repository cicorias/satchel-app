import Foundation

/// The write path shared by the Share Extension and the Safari extension handler (spec §9.2.2–9.2.3): build the
/// item, save it to the local store (which queues it in the outbox), then try a one-shot CloudKit save and record the
/// outcome on the outbox entry. A failed CloudKit save leaves the entry for the host app's sync (ticket 07).
public struct ItemSaver: Sendable {
    public let store: Store
    public let model: SatchelModel
    public let cloud: OneShotSaver
    public let environment: AppEnvironment

    public init(store: Store, model: SatchelModel, cloud: OneShotSaver, environment: AppEnvironment) {
        self.store = store
        self.model = model
        self.cloud = cloud
        self.environment = environment
    }

    /// Opens the App Group store with the bundled model and the default CloudKit container.
    public static func standard(bundle: Bundle = .main) throws -> ItemSaver {
        let environment = try AppEnvironment.current(bundle: bundle)
        let model = try SatchelModel.bundled(in: bundle)
        return ItemSaver(
            store: try Store(environment: environment, merge: model.itemMerge), model: model,
            cloud: OneShotSaver(environment: environment), environment: environment)
    }

    public enum CloudOutcome: Sendable, Equatable {
        /// The record is in CloudKit.
        case saved
        /// The save is queued; the host app retries it. The failure says why the one-shot save didn't work.
        case queued(OneShotFailure)
    }

    public struct Outcome: Sendable, Equatable {
        /// The item as stored, after merging with any earlier save of the same URL.
        public let item: Item
        public let cloud: CloudOutcome
    }

    /// Saves `url` as a link waiting for enrichment (`metadataStatus: pending`), the path for a URL shared from any
    /// app (FR-4). Re-sharing a saved URL merges into the existing item (§7.3).
    public func saveLink(
        url: String, title: String? = nil, tags: [String] = [], note: String? = nil, client: ClientID,
        now: Date = Date()
    ) async throws -> Outcome {
        let normalized = try model.normalizedURL(pageURL: url)
        let timestamp = Self.timestamp(now)
        var item = Item(
            id: try model.itemID(forNormalizedURL: normalized), kind: .link, url: url, canonicalURL: url,
            normalizedURL: normalized, title: title.flatMap(Self.nonBlank) ?? Self.fallbackTitle(for: url),
            tags: tags, createdAt: timestamp, updatedAt: timestamp, metadataStatus: .pending,
            source: ItemSource(client: client, version: environment.version))
        item.note = note.flatMap(Self.nonBlank)
        return try await save(item, body: nil)
    }

    /// Stores `item` (merging with any saved copy), then tries CloudKit with the merged item and, when `body` was
    /// given, the body the merge kept.
    public func save(_ item: Item, body: String?) async throws -> Outcome {
        let stored = try await store.save(item: item, body: body)
        let entry = try await store.unsentOutboxEntry(for: stored.id)
        let keptBody = body == nil ? nil : try await store.body(for: stored.id)
        let result = await cloud.save(stored, body: keptBody)
        switch result {
        case .success:
            if let entry { try await store.markSent(entry.id) }
            return Outcome(item: stored, cloud: .saved)
        case .failure(let failure):
            if let entry { try await store.markFailed(entry.id, error: failure.description) }
            return Outcome(item: stored, cloud: .queued(failure))
        }
    }

    /// The model's timestamp format: ISO 8601 in UTC with milliseconds, as JavaScript's `toISOString()` writes.
    public static func timestamp(_ date: Date) -> String {
        date.formatted(
            .iso8601.year().month().day().time(includingFractionalSeconds: true).timeZone(separator: .omitted))
    }

    /// The capture engine's last-resort title (§4.2): hostname + path.
    static func fallbackTitle(for url: String) -> String {
        guard let components = URLComponents(string: url), let host = components.host else { return url }
        return components.path == "/" || components.path.isEmpty ? host : host + components.path
    }

    private static func nonBlank(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
