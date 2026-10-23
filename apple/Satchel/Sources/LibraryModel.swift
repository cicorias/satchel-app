import Foundation
import SatchelKit

/// The library's live data: every item, newest first, and which ones haven't reached CloudKit yet (FR-8). Both update
/// when the Share Extension or the Safari extension writes to the shared store.
@MainActor @Observable
final class LibraryModel {
    private(set) var items: [Item] = []
    private(set) var unsent: [String: OutboxState] = [:]
    private(set) var error: String?

    private let store: Store?

    init() {
        do {
            let environment = try AppEnvironment.current()
            let model = try SatchelModel.bundled()
            store = try Store(environment: environment, merge: model.itemMerge)
        } catch {
            store = nil
            self.error = "The library couldn't be opened: \(error)"
        }
    }

    func observe() async {
        guard let store else { return }
        async let items: Void = observeItems(store)
        async let outbox: Void = observeOutbox(store)
        _ = await (items, outbox)
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
}
