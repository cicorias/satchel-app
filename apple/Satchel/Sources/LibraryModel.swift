import Foundation
import SatchelKit

/// The library's live data: every item, newest first, which ones haven't reached CloudKit yet (FR-8), and where sync
/// stands. The lists update when sync or either extension writes to the shared store.
@MainActor @Observable
final class LibraryModel {
    private(set) var items: [Item] = []
    private(set) var unsent: [String: OutboxState] = [:]
    private(set) var syncStatus = SyncStatus.starting
    private(set) var error: String?

    private let store: Store?
    private let sync: LibrarySync?

    init(services: AppServices = .shared) {
        store = services.store
        sync = services.sync
        error = services.openError
    }

    func observe() async {
        guard let store else { return }
        async let items: Void = observeItems(store)
        async let outbox: Void = observeOutbox(store)
        async let status: Void = observeSync()
        _ = await (items, outbox, status)
    }

    /// Deletes locally and queues the delete; sync sends it.
    func delete(_ item: Item) async {
        do {
            try await store?.delete(id: item.id)
        } catch {
            self.error = "Couldn't delete: \(error)"
        }
    }

    func refresh() async {
        await sync?.syncNow()
    }

    private func observeItems(_ store: Store) async {
        do {
            for try await items in store.observeItems() { self.items = items }
        } catch {
            self.error = "\(error)"
        }
    }

    private func observeOutbox(_ store: Store) async {
        do {
            for try await unsent in store.observeUnsentOutbox() { self.unsent = unsent }
        } catch {
            self.error = "\(error)"
        }
    }

    private func observeSync() async {
        guard let sync else { return }
        for await status in sync.statusUpdates() { syncStatus = status }
    }
}
