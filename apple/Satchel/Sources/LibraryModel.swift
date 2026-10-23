import Foundation
import SatchelKit

/// The library's live data: the items matching the search and filters, which ones haven't reached CloudKit yet
/// (FR-8), and where sync stands. The lists update when sync or either extension writes to the shared store.
@MainActor @Observable
final class LibraryModel {
    enum KindFilter: String, CaseIterable, Identifiable {
        case all, pages, links
        var id: Self { self }
        var kind: ItemKind? {
            switch self {
            case .all: nil
            case .pages: .page
            case .links: .link
            }
        }
        var title: String {
            switch self {
            case .all: "All"
            case .pages: "Pages"
            case .links: "Links"
            }
        }
    }

    /// What the list shows; changing it restarts the items observation.
    struct Query: Hashable {
        var text = ""
        var kind = KindFilter.all
        var tag: String?

        var isFiltered: Bool { kind != .all || tag != nil }

        var filter: ItemFilter {
            let searching = !text.trimmingCharacters(in: .whitespaces).isEmpty
            return ItemFilter(kind: kind.kind, tag: tag, order: searching ? .relevance : .recentlyCreated)
        }
    }

    private(set) var items: [Item] = []
    private(set) var unsent: [String: OutboxState] = [:]
    private(set) var tags: [String] = []
    private(set) var syncStatus = SyncStatus.starting
    private(set) var error: String?
    var query = Query()

    private let services: AppServices

    init(services: AppServices = .shared) {
        self.services = services
        error = services.openError
        loadsRemoteImages = services.loadsRemoteImages
        showingOnboarding = services.needsOnboarding
    }

    /// "Load remote images", read by the rows and the detail view and set in Settings.
    var loadsRemoteImages: Bool {
        didSet { services.loadsRemoteImages = loadsRemoteImages }
    }
    var showingOnboarding: Bool

    /// The sync note under the list, shown when sync isn't working (hidden in the screenshot demo, which runs signed
    /// out on the simulator).
    var showsSyncNote: Bool {
        #if DEBUG
            if DemoLibrary.isRequested { return false }
        #endif
        return !syncStatus.isHealthy
    }

    var siteURL: URL? { (try? AppEnvironment.current())?.siteURL }
    var version: String {
        (try? AppEnvironment.current()).map { "\($0.version) (\($0.build))" } ?? "—"
    }

    func finishOnboarding() {
        services.finishOnboarding()
        showingOnboarding = false
    }

    /// Erases this iPhone's library and syncs the iCloud account now signed in (for `SyncStatus.otherAccount`).
    func startOver() async {
        do {
            try await services.sync?.startOver()
        } catch {
            self.error = "Couldn't start over: \(error)"
        }
    }

    /// Outbox state, tags, and sync status, for as long as the library is on screen.
    func observe() async {
        guard let store = services.store else { return }
        #if DEBUG
            if UITestSeed.isRequested, let model = services.model {
                try? await UITestSeed.seed(store: store, model: model)
            }
            if DemoLibrary.isRequested, let model = services.model {
                try? await DemoLibrary.seed(store: store, model: model)
            }
        #endif
        async let outbox: Void = observeOutbox(store)
        async let tags: Void = observeTags(store)
        async let status: Void = observeSync()
        _ = await (outbox, tags, status)
    }

    /// The items for the current query; restarted by the view whenever `query` changes.
    func observeItems() async {
        guard let store = services.store else { return }
        do {
            for try await items in store.observeItems(matching: query.text, filter: query.filter) { self.items = items }
        } catch is CancellationError {
        } catch {
            self.error = "\(error)"
        }
    }

    /// Deletes locally and queues the delete; sync sends it.
    func delete(_ item: Item) async {
        do {
            try await services.store?.delete(id: item.id)
        } catch {
            self.error = "Couldn't delete: \(error)"
        }
    }

    func refresh() async {
        await services.syncAndEnrich()
    }

    func body(for item: Item) async -> String? {
        try? await services.store?.body(for: item.id)
    }

    /// The `.md` export (spec §5): frontmatter from the item, then the body or, for a link, the description.
    func markdownFile(for item: Item, body: String?) -> String? {
        try? services.model?.markdownFile(for: item, body: body)
    }

    /// Writes the export to a temporary `<title>.md` for the share sheet.
    func exportFile(for item: Item, markdown: String) -> URL? {
        let directory = FileManager.default.temporaryDirectory.appending(path: "Export", directoryHint: .isDirectory)
        let url = directory.appending(path: "\(Self.fileName(for: item)).md")
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try Data(markdown.utf8).write(to: url, options: .atomic)
            return url
        } catch {
            return nil
        }
    }

    /// The title, kept to characters that are safe in a file name, at most 80 of them.
    static func fileName(for item: Item) -> String {
        let allowed = CharacterSet.alphanumerics.union(.whitespaces).union(CharacterSet(charactersIn: "-_.,()"))
        let cleaned = String(String.UnicodeScalarView(item.title.unicodeScalars.filter(allowed.contains)))
            .split(whereSeparator: \.isWhitespace).joined(separator: " ")
        let name = String(cleaned.prefix(80)).trimmingCharacters(in: CharacterSet(charactersIn: " ."))
        return name.isEmpty ? item.id : name
    }

    private func observeOutbox(_ store: Store) async {
        do {
            for try await unsent in store.observeUnsentOutbox() { self.unsent = unsent }
        } catch {
            self.error = "\(error)"
        }
    }

    private func observeTags(_ store: Store) async {
        do {
            for try await tags in store.observeTags() { self.tags = tags }
        } catch {
            self.error = "\(error)"
        }
    }

    private func observeSync() async {
        guard let sync = services.sync else { return }
        for await status in sync.statusUpdates() { syncStatus = status }
    }
}
