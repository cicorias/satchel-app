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

#if DEBUG
    import UIKit

    /// `-SatchelDemoLibrary`: a tidy sample library for App Store screenshots (`mise run art:screenshots`), with
    /// generated thumbnails and every item marked synced. Debug builds only; nothing here is personal data.
    enum DemoLibrary {
        static let argument = "-SatchelDemoLibrary"
        static var isRequested: Bool { ProcessInfo.processInfo.arguments.contains(argument) }
        /// `-SatchelDemoPreview`: leave out the sample article, which the app preview video saves live from Safari.
        static var leavesOutSample: Bool { ProcessInfo.processInfo.arguments.contains("-SatchelDemoPreview") }

        private struct Entry {
            let slug: String
            let title: String
            let site: String
            let description: String
            let tags: [String]
            let symbol: String
            let colors: (UIColor, UIColor)
            let minutes: Int?
            var body: String?
        }

        private static let cedar = UIColor(red: 0.29, green: 0.18, blue: 0.10, alpha: 1)
        private static let leather = UIColor(red: 0.77, green: 0.54, blue: 0.31, alpha: 1)
        private static let ribbon = UIColor(red: 0.18, green: 0.42, blue: 0.31, alpha: 1)
        private static let sky = UIColor(red: 0.27, green: 0.47, blue: 0.67, alpha: 1)
        private static let clay = UIColor(red: 0.69, green: 0.33, blue: 0.24, alpha: 1)

        private static let entries: [Entry] = [
            Entry(
                slug: "plain-text", title: "The Quiet Revolution of Plain Text", site: "Satchel Notes",
                description: "Why notes written in plain Markdown outlast every app they were written in.",
                tags: ["writing", "markdown"], symbol: "doc.plaintext", colors: (cedar, leather), minutes: 3,
                body: """
                    # The Quiet Revolution of Plain Text

                    Every few years a new notes app promises to organize your life. Every few years, its format \
                    becomes a museum piece. The notes that survive are the ones written as **plain text**: readable \
                    today, readable in twenty years, and readable in any editor you'll ever own.

                    ## Formats outlive apps

                    A Markdown file is just characters. There is nothing to export, no database to migrate, and no \
                    company that has to stay in business.

                    > The best file format is the one you never have to think about again.

                    ## Structure without ceremony

                    - **Headings** to outline an idea.
                    - **Lists** for steps and checklists.
                    - **Links** that still work when you move the file.
                    - **Code blocks** that keep their spacing.

                    ```yaml
                    title: The Quiet Revolution of Plain Text
                    tags: [writing, markdown]
                    saved: 2026-10-23
                    ```

                    ## A small habit

                    Save what you read as plain text, tag it, and keep it somewhere you control.

                    | Format | Readable in 20 years? |
                    | --- | --- |
                    | Plain text / Markdown | Yes |
                    | A proprietary database | Maybe |
                    """),
            Entry(
                slug: "sourdough", title: "A Field Guide to Sourdough Starters", site: "Example Kitchen",
                description: "Feeding schedules, flour choices, and how to rescue a sluggish starter.",
                tags: ["baking"], symbol: "fork.knife", colors: (clay, leather), minutes: 7,
                body: "# A Field Guide to Sourdough Starters\n\nFeed it, wait, and watch it rise.\n"),
            Entry(
                slug: "coast-path", title: "Three Days on the Coast Path", site: "Trail Notes",
                description: "Cliffs, tide tables, and the best bakery on the whole route.",
                tags: ["travel", "hiking"], symbol: "figure.hiking", colors: (sky, ribbon), minutes: 9,
                body: "# Three Days on the Coast Path\n\nThe first morning started with fog.\n"),
            Entry(
                slug: "sync-engines", title: "How Sync Engines Resolve Conflicts", site: "Example Engineering",
                description: "Change tags, merges, and why the last writer shouldn't always win.",
                tags: ["engineering", "swift"], symbol: "arrow.triangle.2.circlepath", colors: (ribbon, sky),
                minutes: 12, body: "# How Sync Engines Resolve Conflicts\n\nTwo devices, one record.\n"),
            Entry(
                slug: "keyboards", title: "Choosing a Mechanical Keyboard", site: "Example Reviews",
                description: "Switches, layouts, and what actually matters for long writing sessions.",
                tags: ["gear"], symbol: "keyboard", colors: (cedar, sky), minutes: nil),
            Entry(
                slug: "reading-list", title: "Weekly Reading List: Slow Software", site: "Example Letters",
                description: "Seven essays on tools that respect your attention.",
                tags: ["reading"], symbol: "books.vertical", colors: (leather, clay), minutes: nil),
        ]

        static func seed(store: Store, model: SatchelModel) async throws {
            let directory = FileManager.default.temporaryDirectory.appending(
                path: "DemoImages", directoryHint: .isDirectory)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            // Oldest first, so the list (newest first) shows them in this order.
            for (index, entry) in entries.enumerated().reversed() where !(leavesOutSample && entry.slug == "plain-text")
            {
                let url = "https://example.com/\(entry.slug)"
                let normalized = try model.normalizedURL(pageURL: url)
                let saved = ItemSaver.timestamp(Date().addingTimeInterval(-Double(index) * 5400))
                let image = directory.appending(path: "\(entry.slug).png")
                try thumbnail(entry).write(to: image)
                var item = Item(
                    id: try model.itemID(forNormalizedURL: normalized), kind: entry.body == nil ? .link : .page,
                    url: url, canonicalURL: url, normalizedURL: normalized, title: entry.title, tags: entry.tags,
                    createdAt: saved, updatedAt: saved, metadataStatus: .complete,
                    source: ItemSource(client: .safariIOS, version: "2026.10.0"))
                item.siteName = entry.site
                item.description = entry.description
                item.imageURL = image.absoluteString
                if let minutes = entry.minutes {
                    item.capturedAt = saved
                    item.page = PageInfo(wordCount: minutes * 230, readingMinutes: minutes, engine: "demo")
                }
                let stored = try await store.save(item: item, body: entry.body)
                // Shown as synced: screenshots show a library signed in to iCloud.
                if let outbox = try await store.unsentOutboxEntry(for: stored.id) {
                    try await store.markSent(outbox.id)
                }
            }
        }

        private static func thumbnail(_ entry: Entry) -> Data {
            let size = CGSize(width: 240, height: 240)
            return UIGraphicsImageRenderer(size: size).pngData { context in
                let colors = [entry.colors.0.cgColor, entry.colors.1.cgColor] as CFArray
                if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: nil)
                {
                    context.cgContext.drawLinearGradient(
                        gradient, start: .zero, end: CGPoint(x: size.width, y: size.height), options: [])
                }
                let configuration = UIImage.SymbolConfiguration(pointSize: 96, weight: .medium)
                if let symbol = UIImage(systemName: entry.symbol, withConfiguration: configuration)?
                    .withTintColor(.white.withAlphaComponent(0.92), renderingMode: .alwaysOriginal)
                {
                    let rect = CGRect(
                        x: (size.width - symbol.size.width) / 2, y: (size.height - symbol.size.height) / 2,
                        width: symbol.size.width, height: symbol.size.height)
                    symbol.draw(in: rect)
                }
            }
        }
    }
#endif
