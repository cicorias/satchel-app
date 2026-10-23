import Foundation
import Synchronization

/// Loads a page and reads its metadata: `WebMetadataLoader` in the app, a fake in tests.
public protocol LinkMetadataLoader: Sendable {
    func metadata(for url: String) async throws -> LinkMetadata
}

/// Whether enrichment may use the network now: `NetworkPath` in the app, a fake in tests.
public protocol NetworkConditions: Sendable {
    var allowsEnrichment: Bool { get async }
}

/// Fills in links saved with `metadataStatus: pending`, such as URLs shared from other apps (spec §9.2.4): loads
/// each page, reads its metadata, and saves it, which queues the change for sync. The host app runs it on foreground
/// and from background refresh, off the main actor.
///
/// - **Retries:** a failed load is retried after `retryDelays`; after `maxAttempts` the item is marked `failed`.
///   Attempt counts live in the store's `syncState` under `enrichment/<id>`.
/// - **Limits:** at most `batchLimit` loads per run, one at a time, at least `perHostInterval` apart for the same
///   host, each within `timeout`. Nothing runs when `NetworkConditions` says no (cellular in Low Data Mode).
/// - One run at a time; a second call while one is running returns at once.
public final class Enricher: Sendable {
    public struct Policy: Sendable {
        public var maxAttempts = 3
        /// The wait after the first, second, … failure.
        public var retryDelays: [Duration] = [.seconds(5 * 60), .seconds(60 * 60)]
        public var perHostInterval: Duration = .seconds(2)
        public var timeout: Duration = .seconds(20)
        public var batchLimit = 20

        public init() {}
    }

    public struct Report: Sendable, Equatable {
        public var enriched: [String] = []
        public var failed: [String] = []
        /// Loads that failed and will be retried.
        public var retrying: [String] = []
        /// The network didn't allow enrichment, or a run was already going.
        public var skipped = false
    }

    struct Attempts: Codable, Equatable {
        var count: Int
        var nextAttempt: Date
    }

    static let keyPrefix = "enrichment/"

    public let store: Store
    private let loader: any LinkMetadataLoader
    private let network: any NetworkConditions
    private let policy: Policy
    private let now: @Sendable () -> Date
    private let sleep: @Sendable (Duration) async -> Void
    private let running = Mutex(false)

    public init(
        store: Store, loader: any LinkMetadataLoader, network: any NetworkConditions, policy: Policy = .init(),
        now: @escaping @Sendable () -> Date = Date.init,
        sleep: @escaping @Sendable (Duration) async -> Void = { try? await Task.sleep(for: $0) }
    ) {
        self.store = store
        self.loader = loader
        self.network = network
        self.policy = policy
        self.now = now
        self.sleep = sleep
    }

    @discardableResult
    public func run() async -> Report {
        var report = Report()
        let started = running.withLock { running in
            guard !running else { return false }
            running = true
            return true
        }
        guard started else {
            report.skipped = true
            return report
        }
        defer { running.withLock { $0 = false } }
        guard await network.allowsEnrichment else {
            report.skipped = true
            return report
        }

        let pending =
            (try? await store.items(filter: ItemFilter(metadataStatus: .pending, order: .recentlyCreated)))
            ?? []
        var lastRequest: [String: ContinuousClock.Instant] = [:]
        var loads = 0
        for item in pending where loads < policy.batchLimit {
            if Task.isCancelled { break }
            let attempts = try? await attempts(for: item.id)
            if let attempts, attempts.nextAttempt > now() { continue }
            let host = URL(string: item.url)?.host()?.lowercased() ?? ""
            if let last = lastRequest[host] {
                let wait = policy.perHostInterval - (ContinuousClock.now - last)
                if wait > .zero { await sleep(wait) }
            }
            lastRequest[host] = ContinuousClock.now
            loads += 1
            do {
                let metadata = try await load(item.url)
                try await store.save(item: item.enriched(with: metadata, at: ItemSaver.timestamp(now())))
                try await store.setSyncState(nil, forKey: Self.keyPrefix + item.id)
                report.enriched.append(item.id)
            } catch {
                let count = (attempts?.count ?? 0) + 1
                if count >= policy.maxAttempts {
                    try? await store.setMetadataStatus(.failed, for: item.id, updatedAt: ItemSaver.timestamp(now()))
                    try? await store.setSyncState(nil, forKey: Self.keyPrefix + item.id)
                    report.failed.append(item.id)
                } else {
                    let delay = policy.retryDelays[min(count - 1, policy.retryDelays.count - 1)]
                    let next = now().addingTimeInterval(Double(delay.components.seconds))
                    try? await setAttempts(Attempts(count: count, nextAttempt: next), for: item.id)
                    report.retrying.append(item.id)
                }
            }
        }
        return report
    }

    private func load(_ url: String) async throws -> LinkMetadata {
        let loader = self.loader
        return try await withThrowingTaskGroup(of: LinkMetadata?.self) { group in
            group.addTask { try await loader.metadata(for: url) }
            group.addTask { [timeout = policy.timeout] in
                try await Task.sleep(for: timeout)
                return nil
            }
            defer { group.cancelAll() }
            guard let first = try await group.next(), let metadata = first else { throw EnrichmentError.timedOut }
            return metadata
        }
    }

    func attempts(for id: String) async throws -> Attempts? {
        guard let data = try await store.syncState(forKey: Self.keyPrefix + id) else { return nil }
        return try JSONDecoder().decode(Attempts.self, from: data)
    }

    private func setAttempts(_ attempts: Attempts, for id: String) async throws {
        try await store.setSyncState(try JSONEncoder().encode(attempts), forKey: Self.keyPrefix + id)
    }
}

public enum EnrichmentError: Error, Equatable, Sendable {
    case timedOut
    /// The page loaded but the capture script failed or returned nothing usable.
    case capture(String)
    case load(String)
}
