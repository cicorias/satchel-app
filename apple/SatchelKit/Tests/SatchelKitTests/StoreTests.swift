import Foundation
import GRDB
import Synchronization
import Testing

@testable import SatchelKit

// MARK: - Helpers

/// A stand-in for ticket 03's `SatchelModel.merge`: just enough of §7.3 to exercise the store. The newer
/// `updatedAt` wins the fields, `createdAt` keeps the earliest, tags are a union, `page` beats `link`, and the
/// newer page owns the body.
let fakeMerge: ItemMerge = { a, b in
    let bIsNewer = b.updatedAt >= a.updatedAt
    var item = bIsNewer ? b : a
    item.createdAt = min(a.createdAt, b.createdAt)
    var tags = (bIsNewer ? a : b).tags
    for tag in item.tags where !tags.contains(tag) { tags.append(tag) }
    item.tags = tags
    item.kind = a.kind == .page || b.kind == .page ? .page : .link
    let body: MergeResult.BodySource =
        switch (a.kind, b.kind) {
        case (.page, .page): bIsNewer ? .b : .a
        case (.page, .link): .a
        case (.link, .page): .b
        case (.link, .link): .none
        }
    item.page = body == .a ? a.page : body == .b ? b.page : nil
    return MergeResult(item: item, body: body, replacesBody: a.kind == .page && b.kind == .page)
}

func makeItem(
    _ slug: String, kind: ItemKind = .link, title: String = "Untitled", description: String? = nil,
    siteName: String? = nil, host: String = "example.com", tags: [String] = [],
    createdAt: String = "2026-10-01T10:00:00.000Z", updatedAt: String? = nil
) -> Item {
    let url = "https://\(host)/\(slug)"
    var item = Item(
        id: "u_\(slug)", kind: kind, url: url, canonicalURL: url, normalizedURL: url, title: title, tags: tags,
        createdAt: createdAt, updatedAt: updatedAt ?? createdAt, metadataStatus: .complete,
        source: ItemSource(client: .iosShare, version: "2026.10.0"))
    item.description = description
    item.siteName = siteName
    if kind == .page { item.page = PageInfo(wordCount: 100, readingMinutes: 1, engine: "test") }
    return item
}

/// A fresh directory per test, removed afterwards.
final class TempDirectory: Sendable {
    let url: URL

    init() throws {
        url = FileManager.default.temporaryDirectory.appending(path: "SatchelKitTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    deinit { try? FileManager.default.removeItem(at: url) }

    var database: URL { url.appending(path: "satchel.sqlite") }

    func store(merge: @escaping ItemMerge = fakeMerge) throws -> Store {
        try Store(url: database, merge: merge)
    }
}

/// Waits for the sequence to produce a value that satisfies `predicate`.
func next<I: AsyncIteratorProtocol>(
    _ iterator: inout I, where predicate: (I.Element) -> Bool
) async throws -> I.Element? {
    while let value = try await iterator.next() {
        if predicate(value) { return value }
    }
    return nil
}

// MARK: - Schema

@Suite struct StoreSchemaTests {
    let temp: TempDirectory

    init() throws { temp = try TempDirectory() }

    @Test func migratesAFreshFileInWALMode() async throws {
        let store = try temp.store()
        #expect(try await store.journalMode() == "wal")

        let queue = try DatabaseQueue(path: temp.database.path(percentEncoded: false))
        let (tables, applied) = try await queue.read { db in
            (
                try String.fetchSet(db, sql: "SELECT name FROM sqlite_master WHERE type IN ('table', 'view')"),
                try StoreSchema.migrator.appliedIdentifiers(db)
            )
        }
        #expect(
            tables.isSuperset(of: ["items", "itemTags", "bodies", "outbox", "syncState", "itemSearch", "itemsFTS"]))
        #expect(applied == ["v1"])
    }

    @Test func reopeningKeepsTheData() async throws {
        try await temp.store().save(item: makeItem("a"), body: nil)
        let reopened = try temp.store()
        #expect(try await reopened.item(id: "u_a") != nil)
    }

    @Test func opensADatabaseANewerVersionMigrated() async throws {
        // A newer app adds an (additive) migration; an older extension still opens the file and writes to it.
        do {
            var newer = StoreSchema.migrator
            newer.registerMigration("v999-future") { db in
                try db.alter(table: "items") { t in t.add(column: "future", .text) }
            }
            let pool = try DatabasePool(path: temp.database.path(percentEncoded: false))
            try newer.migrate(pool)
        }
        let store = try temp.store()
        try await store.save(item: makeItem("a"), body: nil)
        #expect(try await store.items().map(\.id) == ["u_a"])
    }
}

// MARK: - Items

@Suite struct StoreItemTests {
    let temp: TempDirectory
    let store: Store

    init() throws {
        temp = try TempDirectory()
        store = try temp.store()
    }

    @Test func savesAndReadsBack() async throws {
        let item = makeItem("a", kind: .page, title: "A page", tags: ["one"])
        let saved = try await store.save(item: item, body: "# A page\n\nHello.")
        #expect(saved == item)
        #expect(try await store.item(id: "u_a") == item)
        #expect(try await store.body(for: "u_a") == "# A page\n\nHello.")
        #expect(try await store.item(id: "u_missing") == nil)
        #expect(try await store.body(for: "u_missing") == nil)
    }

    @Test(arguments: try ContractFixtures.all().map(\.name))
    func roundTripsContractFixtures(name: String) async throws {
        let data = try Data(contentsOf: ContractFixtures.directory.appending(path: name))
        let item = try JSONDecoder().decode(Item.self, from: data)
        try await store.save(item: item, body: nil)
        let stored = try #require(try await store.item(id: item.id))
        #expect(stored == item)
        // Unknown fields survive the database too (spec §7.1).
        #expect(
            try JSONDecoder().decode(JSONValue.self, from: JSONEncoder().encode(stored))
                == JSONDecoder().decode(JSONValue.self, from: data))
    }

    @Test func reSaveMergesWithTheStoredItem() async throws {
        try await store.save(item: makeItem("a", tags: ["first"], createdAt: "2026-10-01T10:00:00.000Z"))
        let page = makeItem(
            "a", kind: .page, title: "Now a page", tags: ["second"], createdAt: "2026-10-05T10:00:00.000Z")
        let merged = try await store.save(item: page, body: "page body")

        #expect(merged.kind == .page)
        #expect(merged.tags == ["first", "second"])
        #expect(merged.createdAt == "2026-10-01T10:00:00.000Z")
        #expect(merged.title == "Now a page")
        #expect(try await store.item(id: "u_a") == merged)
        #expect(try await store.body(for: "u_a") == "page body")
        #expect(try await store.items().count == 1)

        // A newer link save of the same URL keeps the saved page body (the merge says `.a`).
        let link = makeItem("a", title: "Link again", createdAt: "2026-10-09T10:00:00.000Z")
        let again = try await store.save(item: link, body: nil)
        #expect(again.kind == .page)
        #expect(try await store.body(for: "u_a") == "page body")
        try await store.checkSearchIndex()
    }

    @Test func passesStoredThenIncomingToTheMerge() async throws {
        let calls = Calls()
        let store = try temp.store { a, b in
            calls.record(a.title, b.title)
            return MergeResult(item: b, body: .b, replacesBody: false)
        }
        try await store.save(item: makeItem("a", title: "stored"), body: "old")
        try await store.save(item: makeItem("a", title: "incoming"), body: "new")
        #expect(calls.all == [["stored", "incoming"]])
        #expect(try await store.body(for: "u_a") == "new")
    }

    @Test func mergeChoosingNoBodyDropsIt() async throws {
        let store = try temp.store { _, b in MergeResult(item: b, body: .none, replacesBody: false) }
        try await store.save(item: makeItem("a"), body: "stale")
        try await store.save(item: makeItem("a"), body: "ignored")
        #expect(try await store.body(for: "u_a") == nil)
    }

    @Test func failedMergeRollsBack() async throws {
        struct Boom: Error {}
        let store = try temp.store { _, _ in throw Boom() }
        try await store.save(item: makeItem("a", title: "kept"), body: "kept body")
        let before = try await store.pendingOutbox()
        await #expect(throws: Boom.self) { try await store.save(item: makeItem("a", title: "lost"), body: "lost") }
        #expect(try await store.item(id: "u_a")?.title == "kept")
        #expect(try await store.body(for: "u_a") == "kept body")
        #expect(try await store.pendingOutbox() == before)
    }

    @Test func rejectsAMergeThatChangesTheID() async throws {
        let store = try temp.store { _, _ in MergeResult(item: makeItem("other"), body: .none, replacesBody: false) }
        try await store.save(item: makeItem("a"))
        await #expect(throws: StoreError.mergeChangedID(expected: "u_a", actual: "u_other")) {
            try await store.save(item: makeItem("a"))
        }
    }

    @Test func listsNewestFirstAndFilters() async throws {
        try await store.save(item: makeItem("old", tags: ["swift"], createdAt: "2026-10-01T10:00:00.000Z"))
        try await store.save(
            item: makeItem("mid", kind: .page, tags: ["swift", "ios"], createdAt: "2026-10-02T10:00:00.000Z"),
            body: "b")
        try await store.save(item: makeItem("new", tags: ["ios"], createdAt: "2026-10-03T10:00:00Z"))

        #expect(try await store.items().map(\.id) == ["u_new", "u_mid", "u_old"])
        #expect(try await store.items(filter: .init(kind: .page)).map(\.id) == ["u_mid"])
        #expect(try await store.items(filter: .init(tag: " Swift ")).map(\.id) == ["u_mid", "u_old"])
        #expect(try await store.items(filter: .init(kind: .link, tag: "ios")).map(\.id) == ["u_new"])
        #expect(try await store.items(filter: .init(limit: 2)).map(\.id) == ["u_new", "u_mid"])

        // Re-saving moves an item up by update time, but not by creation time.
        try await store.save(item: makeItem("old", createdAt: "2026-10-04T10:00:00.000Z"))
        #expect(try await store.items().map(\.id) == ["u_old", "u_new", "u_mid"])
        #expect(try await store.items(filter: .init(order: .recentlyCreated)).map(\.id) == ["u_new", "u_mid", "u_old"])
    }

    @Test func filtersByMetadataStatus() async throws {
        var pending = makeItem("p")
        pending.metadataStatus = .pending
        try await store.save(item: pending)
        try await store.save(item: makeItem("c"))
        #expect(try await store.items(filter: .init(metadataStatus: .pending)).map(\.id) == ["u_p"])
    }

    @Test func deleteRemovesTheItemBodyAndTags() async throws {
        try await store.save(item: makeItem("a", kind: .page, title: "Kayak", tags: ["boats"]), body: "paddle")
        #expect(try await store.delete(id: "u_a"))
        #expect(try await store.item(id: "u_a") == nil)
        #expect(try await store.body(for: "u_a") == nil)
        #expect(try await store.tags().isEmpty)
        #expect(try await store.items(matching: "kayak").isEmpty)
        #expect(try await store.delete(id: "u_a") == false)
        try await store.checkSearchIndex()
    }

    @Test func tagsMostUsedFirst() async throws {
        try await store.save(item: makeItem("a", tags: ["swift", "ios"]))
        try await store.save(item: makeItem("b", tags: ["swift", "sqlite"]))
        try await store.save(item: makeItem("c", tags: ["swift", "ios", "grdb"]))
        #expect(try await store.tags() == ["swift", "ios", "grdb", "sqlite"])
        #expect(try await store.tags(prefix: "S") == ["swift", "sqlite"])
        #expect(try await store.tags(limit: 2) == ["swift", "ios"])
    }

    @Test func syncStateRoundTrips() async throws {
        #expect(try await store.syncState(forKey: "engine") == nil)
        try await store.setSyncState(Data([1, 2, 3]), forKey: "engine")
        try await store.setSyncState(Data([4]), forKey: "engine")
        #expect(try await store.syncState(forKey: "engine") == Data([4]))
        try await store.setSyncState(nil, forKey: "engine")
        #expect(try await store.syncState(forKey: "engine") == nil)
    }
}

/// Records merge calls from a `@Sendable` closure.
final class Calls: Sendable {
    private let calls = Mutex<[[String]]>([])
    func record(_ values: String...) { calls.withLock { $0.append(values) } }
    var all: [[String]] { calls.withLock { $0 } }
}

// MARK: - Search

@Suite struct StoreSearchTests {
    let temp: TempDirectory
    let store: Store

    init() async throws {
        temp = try TempDirectory()
        store = try temp.store()
        try await store.save(
            item: makeItem(
                "kayak", kind: .page, title: "Choosing a sea kayak", description: "Stability versus speed",
                siteName: "Paddler Weekly", tags: ["boats", "outdoors"]),
            body: "Rudders, skegs, and the **Café** at the put-in.")
        try await store.save(
            item: makeItem(
                "grdb", title: "GRDB.swift", description: "A toolkit for SQLite databases", host: "www.github.com",
                tags: ["swift", "sqlite"], createdAt: "2026-10-02T10:00:00.000Z"))
    }

    func ids(_ query: String?, _ filter: ItemFilter = .init()) async throws -> [String] {
        try await store.items(matching: query, filter: filter).map(\.id)
    }

    @Test func matchesEachIndexedField() async throws {
        #expect(try await ids("choosing") == ["u_kayak"])  // title
        #expect(try await ids("stability") == ["u_kayak"])  // description
        #expect(try await ids("paddler") == ["u_kayak"])  // site name
        #expect(try await ids("github") == ["u_grdb"])  // host, without www.
        #expect(try await ids("outdoors") == ["u_kayak"])  // tags
        #expect(try await ids("skegs") == ["u_kayak"])  // body
    }

    @Test func matchesPrefixesCaseAndDiacriticsInsensitively() async throws {
        #expect(try await ids("kay") == ["u_kayak"])
        #expect(try await ids("SQL") == ["u_grdb"])
        #expect(try await ids("cafe") == ["u_kayak"])
        #expect(try await ids("café") == ["u_kayak"])
    }

    @Test func requiresEveryWord() async throws {
        #expect(try await ids("sea kay") == ["u_kayak"])
        #expect(try await ids("sea sqlite").isEmpty)
    }

    @Test func blankQueriesMatchEverything() async throws {
        #expect(try await ids(nil) == ["u_grdb", "u_kayak"])
        #expect(try await ids("   ") == ["u_grdb", "u_kayak"])
        #expect(try await ids("* - ()") == ["u_grdb", "u_kayak"])
    }

    @Test(arguments: [
        "\"", "\"kayak", "title:kayak", "kayak OR", "NEAR(kayak", "^kayak", "kayak*", "a AND", "{title}: x", "'",
        "kayak\"; DROP TABLE items; --",
    ])
    func treatsFTSSyntaxAsText(query: String) async throws {
        _ = try await ids(query)
        #expect(try await ids("kayak") == ["u_kayak"])
    }

    @Test func combinesSearchWithFilters() async throws {
        #expect(try await ids("s", .init(kind: .link)) == ["u_grdb"])
        #expect(try await ids("s", .init(tag: "boats")) == ["u_kayak"])
    }

    @Test func ranksByRelevanceWhenAsked() async throws {
        try await store.save(
            item: makeItem("other", kind: .page, title: "Unrelated"),
            body: Array(repeating: "filler", count: 200).joined(separator: " ") + " kayak")
        let ranked = try await ids("kayak", .init(order: .relevance))
        #expect(Set(ranked) == ["u_kayak", "u_other"])
        #expect(ranked.first == "u_kayak")
    }

    @Test func reindexesOnReSave() async throws {
        var renamed = makeItem("kayak", kind: .page, title: "Canoe or kayak", updatedAt: "2026-10-09T10:00:00.000Z")
        renamed.createdAt = "2026-10-01T10:00:00.000Z"
        try await store.save(item: renamed, body: "new body text")
        #expect(try await ids("canoe") == ["u_kayak"])
        #expect(try await ids("choosing").isEmpty)
        #expect(try await ids("skegs").isEmpty)
        #expect(try await ids("body") == ["u_kayak"])
        try await store.checkSearchIndex()
    }

    @Test func buildsSafePatterns() {
        #expect(SearchPattern.make(nil) == nil)
        #expect(SearchPattern.make(" \t") == nil)
        #expect(SearchPattern.make("kay") == "\"kay\"*")
        #expect(SearchPattern.make("say \"hi\"") == "\"say\"* \"\"\"hi\"\"\"*")
        #expect(SearchPattern.make("-- ** sea") == "\"sea\"*")
    }
}

// MARK: - Outbox

@Suite struct StoreOutboxTests {
    let temp: TempDirectory
    let store: Store

    init() throws {
        temp = try TempDirectory()
        store = try temp.store()
    }

    @Test func saveQueuesAnUpsert() async throws {
        let item = makeItem("a")
        try await store.save(item: item)
        let entries = try await store.pendingOutbox()
        #expect(entries.count == 1)
        let entry = try #require(entries.first)
        #expect(entry.itemID == "u_a")
        #expect(entry.operation == .upsert)
        #expect(entry.item == item)
        #expect(entry.state == .pending)
        #expect(entry.attempts == 0)
        #expect(entry.lastError == nil)
        #expect(try await store.outboxState(for: "u_a") == .pending)
        #expect(try await store.outboxState(for: "u_missing") == nil)
    }

    @Test func failedThenSent() async throws {
        try await store.save(item: makeItem("a"))
        let id = try #require(try await store.pendingOutbox().first?.id)

        try await store.markFailed(id, error: "network unavailable")
        let failed = try #require(try await store.pendingOutbox().first)
        #expect(failed.id == id)
        #expect(failed.state == .failed)
        #expect(failed.attempts == 1)
        #expect(failed.lastError == "network unavailable")
        #expect(try await store.outboxState(for: "u_a") == .failed)

        try await store.markSent(id)
        #expect(try await store.pendingOutbox().isEmpty)
        #expect(try await store.outboxState(for: "u_a") == .sent)

        // Sent is final.
        try await store.markFailed(id, error: "late")
        #expect(try await store.outboxState(for: "u_a") == .sent)
    }

    @Test func aNewerChangeReplacesTheEntry() async throws {
        try await store.save(item: makeItem("a", title: "first"))
        let first = try #require(try await store.pendingOutbox().first)
        try await store.save(item: makeItem("a", title: "second", updatedAt: "2026-10-02T10:00:00.000Z"))
        let entries = try await store.pendingOutbox()
        #expect(entries.count == 1)
        #expect(entries.first?.item?.title == "second")

        // The sender of the replaced entry reports success: nothing changes.
        try await store.markSent(first.id)
        #expect(try await store.pendingOutbox().map(\.id) == entries.map(\.id))
    }

    @Test func deleteQueuesADelete() async throws {
        try await store.save(item: makeItem("a"))
        try await store.save(item: makeItem("b"))
        try await store.delete(id: "u_a")
        let entries = try await store.pendingOutbox()
        #expect(entries.map(\.itemID) == ["u_b", "u_a"])
        #expect(entries.last?.operation == .delete)
        #expect(entries.last?.item == nil)
    }

    @Test func pendingIsOldestFirstAndLimited() async throws {
        for slug in ["a", "b", "c"] { try await store.save(item: makeItem(slug)) }
        #expect(try await store.pendingOutbox(limit: 2).map(\.itemID) == ["u_a", "u_b"])
    }
}

// MARK: - Two processes

/// Two `Store`s on one file stand in for the app and an extension: separate connection pools, as in separate
/// processes, which GRDB's in-process observation can't see between.
@Suite struct StoreSharingTests {
    let temp: TempDirectory

    init() throws { temp = try TempDirectory() }

    @Test(.timeLimit(.minutes(1)))
    func twoStoresWriteConcurrently() async throws {
        let app = try temp.store()
        let extensionStore = try temp.store()
        try await withThrowingTaskGroup(of: Void.self) { group in
            for (name, store) in [("app", app), ("ext", extensionStore)] {
                group.addTask {
                    for index in 0..<40 {
                        try await store.save(item: makeItem("\(name)-\(index)", tags: [name]), body: nil)
                        // Both also keep re-saving one shared item, so the merges contend.
                        try await store.save(item: makeItem("shared", tags: [name]), body: nil)
                    }
                }
            }
            try await group.waitForAll()
        }
        #expect(try await app.items().count == 81)
        #expect(try await extensionStore.items(filter: .init(tag: "ext")).count == 41)
        #expect(try await app.item(id: "u_shared")?.tags.sorted() == ["app", "ext"])
        #expect(try await app.pendingOutbox(limit: 1000).count == 81)
        try await app.checkSearchIndex()
    }

    @Test(.timeLimit(.minutes(1)))
    func oneStoreSeesTheOthersWrites() async throws {
        let app = try temp.store()
        let extensionStore = try temp.store()

        let items = app.observeItems()
        var itemIterator = items.makeAsyncIterator()
        #expect(try await itemIterator.next() == [])
        let outbox = app.observeUnsentOutbox()
        var outboxIterator = outbox.makeAsyncIterator()
        #expect(try await outboxIterator.next() == [:])

        try await extensionStore.save(item: makeItem("shared-from-extension"), body: nil)

        let seen = try await next(&itemIterator) { !$0.isEmpty }
        #expect(seen?.map(\.id) == ["u_shared-from-extension"])
        let states = try await next(&outboxIterator) { !$0.isEmpty }
        #expect(states == ["u_shared-from-extension": .pending])

        // The app sends it; the extension's observation sees the badge clear.
        let extensionOutbox = extensionStore.observeUnsentOutbox()
        var extensionIterator = extensionOutbox.makeAsyncIterator()
        _ = try await extensionIterator.next()
        let entry = try #require(try await app.pendingOutbox().first)
        try await app.markSent(entry.id)
        let cleared = try await next(&extensionIterator) { $0.isEmpty }
        #expect(cleared == [:])
    }

    @Test func usesTheSameNotificationNameForTheSameFile() throws {
        let a = try temp.store()
        let b = try Store(url: temp.url.appending(path: "./satchel.sqlite"), merge: fakeMerge)
        #expect(a.changeNotificationName == b.changeNotificationName)
        let other = try Store(url: temp.url.appending(path: "other.sqlite"), merge: fakeMerge)
        #expect(other.changeNotificationName != a.changeNotificationName)
    }
}

// MARK: - Values

@Suite struct StoreValueTests {
    @Test func parsesISODates() {
        #expect(Store.epoch("1970-01-01T00:00:01.500Z") == 1.5)
        #expect(Store.epoch("1970-01-01T00:00:01Z") == 1)
        #expect(Store.epoch("1970-01-01T01:00:00+01:00") == 0)
        #expect(Store.epoch("not a date") == 0)
    }

    @Test func siteIncludesTheHost() {
        #expect(Store.site(of: makeItem("a", siteName: "Example", host: "www.example.com")) == "Example example.com")
        #expect(Store.site(of: makeItem("a", host: "news.example.org")) == "news.example.org")
    }
}
