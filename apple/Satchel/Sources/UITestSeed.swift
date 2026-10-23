#if DEBUG
    import Foundation
    import SatchelKit

    /// UI tests launch the app with `-SatchelSeedLibrary` to get known items (ticket 10). Debug builds only.
    ///
    /// The page's body tries what the detail view must refuse: an inline script, an event handler, and remote images
    /// (spec §11). Seeding saves through `Store` only, never CloudKit, and re-seeding merges into the same items.
    enum UITestSeed {
        static let argument = "-SatchelSeedLibrary"
        static let pageTitle = "Satchel seeded page"
        static let linkTitle = "Satchel seeded link"

        static var isRequested: Bool { ProcessInfo.processInfo.arguments.contains(argument) }

        static let pageBody = """
            # Satchel seeded page

            A page with a [link to Example](https://example.com/) and a footnote.[^1]

            ![Remote image](https://example.com/satchel-seed.png)

            <img src="https://example.com/satchel-tracker.png" onerror="document.body.dataset.ran = 'handler'">

            <script>document.body.dataset.ran = 'script'</script>

            ```swift
            let saved = true
            ```

            [^1]: The footnote.
            """

        static func seed(store: Store, model: SatchelModel) async throws {
            let now = ItemSaver.timestamp(Date())
            for (slug, title, kind) in [("page", pageTitle, ItemKind.page), ("link", linkTitle, .link)] {
                let url = "https://example.com/satchel-seed/\(slug)"
                let normalized = try model.normalizedURL(pageURL: url)
                var item = Item(
                    id: try model.itemID(forNormalizedURL: normalized), kind: kind, url: url, canonicalURL: url,
                    normalizedURL: normalized, title: title, tags: ["seed", slug], createdAt: now, updatedAt: now,
                    metadataStatus: .complete, source: ItemSource(client: .iosApp, version: "2026.10.0"))
                item.siteName = "Example"
                item.description = "Seeded for UI tests."
                if kind == .page {
                    item.capturedAt = now
                    item.page = PageInfo(wordCount: 20, readingMinutes: 1, engine: "seed")
                }
                try await store.save(item: item, body: kind == .page ? pageBody : nil)
            }
        }
    }
#endif
