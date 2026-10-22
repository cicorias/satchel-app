import CryptoKit
import Foundation
import GRDB
import SQLite3
import notify

/// The local cache and outbox that the app and both extensions share (spec §9.2.1, ADR-0017).
///
/// SQLite in WAL mode through a GRDB `DatabasePool`, so separate processes can read while one writes. Each process
/// opens its own `Store` on the same file. A write posts a Darwin notification, and every `Store` on that file
/// refreshes its observations when it hears one, so a save from an extension shows up in the app without a
/// relaunch.
///
/// Merge rules aren't implemented here: the caller injects them (`SatchelModel.merge`, ADR-0020).
public final class Store: Sendable {
    public let url: URL
    /// The Darwin notification name every `Store` on this file posts after a write and listens for.
    public let changeNotificationName: String

    private let pool: DatabasePool
    private let merge: ItemMerge
    private let notifyToken: Int32

    /// Opens (creating and migrating if needed) the database at `url`.
    ///
    /// - Parameters:
    ///   - changeNotificationName: shared by every process that opens this file. The default is derived from the
    ///     file path; `init(environment:merge:)` uses one prefixed with the App Group, as the sandbox expects.
    ///   - merge: merges a stored item with an incoming save of the same ID (spec §7.3).
    public init(url: URL, changeNotificationName: String? = nil, merge: @escaping ItemMerge) throws {
        let url = url.standardizedFileURL
        self.url = url
        self.changeNotificationName = changeNotificationName ?? Self.defaultNotificationName(for: url)
        self.merge = merge
        self.pool = try Self.openPool(at: url)

        // Another process (or another Store in this one) wrote: tell this pool's observations to refetch. GRDB
        // can't see writes made through other connections (GRDB "Sharing a Database").
        let pool = self.pool
        var token: Int32 = 0
        let status = notify_register_dispatch(
            self.changeNotificationName, &token, DispatchQueue.global(qos: .utility)
        ) { _ in
            pool.asyncWrite({ db in try db.notifyChanges(in: .fullDatabase) }, completion: { _, _ in })
        }
        guard status == NOTIFY_STATUS_OK else { throw StoreError.changeNotificationUnavailable(status) }
        self.notifyToken = token
    }

    /// Opens the shared store in the App Group container (`AppEnvironment.appGroup`).
    public convenience init(environment: AppEnvironment, merge: @escaping ItemMerge) throws {
        try self.init(
            url: try Self.databaseURL(appGroup: environment.appGroup),
            changeNotificationName: "\(environment.appGroup).store.changed",
            merge: merge)
    }

    deinit {
        notify_cancel(notifyToken)
    }

    /// `<App Group container>/Library/Application Support/Satchel/satchel.sqlite`.
    public static func databaseURL(appGroup: String, fileManager: FileManager = .default) throws -> URL {
        guard let container = fileManager.containerURL(forSecurityApplicationGroupIdentifier: appGroup) else {
            throw StoreError.appGroupUnavailable(appGroup)
        }
        return container.appending(path: "Library/Application Support/Satchel/satchel.sqlite")
    }

    // MARK: - Items

    /// Saves an item and its Markdown body, merging with any stored copy of the same ID, and queues an outbox
    /// `upsert`, all in one transaction. Returns the item as stored.
    ///
    /// The merge decides which body survives: `.a` keeps the stored body, `.b` takes `body` (or keeps the stored
    /// one when `body` is `nil`, so a save without a body never loses one), and `.none` stores no body. An
    /// interactive re-save of a page should ask "Replace saved copy?" before calling this (spec §7.3).
    @discardableResult
    public func save(item: Item, body: String? = nil) async throws -> Item {
        let merge = self.merge
        let saved = try await pool.write { db -> Item in
            var final = item
            var finalBody = body
            let seq: Int64
            if let stored = try Row.fetchOne(db, sql: "SELECT seq, json FROM items WHERE id = ?", arguments: [item.id])
            {
                seq = stored["seq"]
                let storedBody = try String.fetchOne(
                    db, sql: "SELECT markdown FROM bodies WHERE itemID = ?", arguments: [item.id])
                let result = try merge(try Self.decodeItem(stored["json"]), item)
                guard result.item.id == item.id else {
                    throw StoreError.mergeChangedID(expected: item.id, actual: result.item.id)
                }
                final = result.item
                switch result.body {
                case .a: finalBody = storedBody
                case .b: finalBody = body ?? storedBody
                case .none: finalBody = nil
                }
                try Self.unindex(seq: seq, db)
                try Self.writeItem(final, seq: seq, db)
            } else {
                seq = try Self.writeItem(final, seq: nil, db)
            }
            try Self.writeTags(final, db)
            if let finalBody {
                try db.execute(
                    sql: """
                        INSERT INTO bodies (itemID, markdown) VALUES (?, ?)
                        ON CONFLICT (itemID) DO UPDATE SET markdown = excluded.markdown
                        """,
                    arguments: [final.id, finalBody])
            } else {
                try db.execute(sql: "DELETE FROM bodies WHERE itemID = ?", arguments: [final.id])
            }
            try Self.index(seq: seq, db)
            try Self.enqueue(.upsert, itemID: final.id, payload: try Self.encodeItem(final), db)
            return final
        }
        postChange()
        return saved
    }

    public func item(id: String) async throws -> Item? {
        try await pool.read { db in
            try String.fetchOne(db, sql: "SELECT json FROM items WHERE id = ?", arguments: [id]).map(Self.decodeItem)
        }
    }

    /// The Markdown body, or `nil` for a link or an unknown ID.
    public func body(for itemID: String) async throws -> String? {
        try await pool.read { db in
            try String.fetchOne(db, sql: "SELECT markdown FROM bodies WHERE itemID = ?", arguments: [itemID])
        }
    }

    /// Items matching a search over title, description, site, tags, and body (FR-7), narrowed by `filter`. A
    /// `nil` or blank query matches every item. Words match as prefixes, and diacritics are ignored.
    public func items(matching query: String? = nil, filter: ItemFilter = .init()) async throws -> [Item] {
        try await pool.read { db in try Self.fetchItems(db, query: query, filter: filter) }
    }

    /// The same results as `items(matching:filter:)`, then fresh results after every change, including changes
    /// made by other processes. For SwiftUI: `for try await items in store.observeItems() { … }`.
    public func observeItems(
        matching query: String? = nil, filter: ItemFilter = .init()
    ) -> some AsyncSequence<[Item], any Error> & Sendable {
        ValueObservation.tracking { db in try Self.fetchItems(db, query: query, filter: filter) }
            .removeDuplicates()
            .values(in: pool)
    }

    /// Deletes the item, its body, and its tags locally and queues an outbox `delete`. Returns `false`, queuing
    /// nothing, when no item has this ID.
    @discardableResult
    public func delete(id: String) async throws -> Bool {
        let deleted = try await pool.write { db -> Bool in
            guard let seq = try Int64.fetchOne(db, sql: "SELECT seq FROM items WHERE id = ?", arguments: [id]) else {
                return false
            }
            try Self.unindex(seq: seq, db)
            try db.execute(sql: "DELETE FROM items WHERE seq = ?", arguments: [seq])
            try Self.enqueue(.delete, itemID: id, payload: nil, db)
            return true
        }
        if deleted { postChange() }
        return deleted
    }

    /// Tags in use, most used first (then alphabetically), for autocomplete. `prefix` is matched after lowercasing.
    public func tags(prefix: String? = nil, limit: Int? = nil) async throws -> [String] {
        try await pool.read { db in
            var sql = "SELECT tag FROM itemTags"
            var arguments = StatementArguments()
            if let prefix = prefix.map(Self.normalizeTag), !prefix.isEmpty {
                sql += " WHERE substr(tag, 1, ?) = ?"
                arguments += [prefix.unicodeScalars.count, prefix]
            }
            sql += " GROUP BY tag ORDER BY COUNT(*) DESC, tag"
            if let limit {
                sql += " LIMIT ?"
                arguments += [limit]
            }
            return try String.fetchAll(db, sql: sql, arguments: arguments)
        }
    }

    // MARK: - Outbox

    /// Entries not yet sent (`pending` and `failed`), oldest first.
    public func pendingOutbox(limit: Int = 50) async throws -> [OutboxEntry] {
        try await pool.read { db in
            try Row.fetchAll(
                db, sql: "SELECT * FROM outbox WHERE state != ? ORDER BY id LIMIT ?",
                arguments: [OutboxState.sent.rawValue, limit]
            ).map(Self.outboxEntry)
        }
    }

    /// Marks an entry sent. Does nothing if a newer save or delete has replaced it.
    public func markSent(_ id: OutboxEntry.ID) async throws {
        try await updateOutbox(id, state: .sent, error: nil)
    }

    /// Records a failed attempt. The entry stays in `pendingOutbox(limit:)` for the host app to retry.
    public func markFailed(_ id: OutboxEntry.ID, error: String) async throws {
        try await updateOutbox(id, state: .failed, error: error)
    }

    /// The state of the item's latest outbox entry, or `nil` if it has none, for the pending badge (FR-8).
    public func outboxState(for itemID: String) async throws -> OutboxState? {
        try await pool.read { db in
            try String.fetchOne(
                db, sql: "SELECT state FROM outbox WHERE itemID = ? ORDER BY id DESC LIMIT 1", arguments: [itemID]
            ).flatMap(OutboxState.init(rawValue:))
        }
    }

    /// Every item with an unsent outbox entry, and that entry's state (`pending` or `failed`), then fresh values
    /// after every change, including changes made by other processes.
    public func observeUnsentOutbox() -> some AsyncSequence<[String: OutboxState], any Error> & Sendable {
        ValueObservation.tracking(Self.fetchUnsentStates).removeDuplicates().values(in: pool)
    }

    // MARK: - Sync state

    /// An opaque value stored by key, such as the CKSyncEngine serialized state (ticket 07).
    public func syncState(forKey key: String) async throws -> Data? {
        try await pool.read { db in
            try Data.fetchOne(db, sql: "SELECT value FROM syncState WHERE key = ?", arguments: [key])
        }
    }

    /// Stores `value` under `key`, or removes the key when `value` is `nil`.
    public func setSyncState(_ value: Data?, forKey key: String) async throws {
        try await pool.write { db in
            if let value {
                try db.execute(
                    sql: """
                        INSERT INTO syncState (key, value) VALUES (?, ?)
                        ON CONFLICT (key) DO UPDATE SET value = excluded.value
                        """,
                    arguments: [key, value])
            } else {
                try db.execute(sql: "DELETE FROM syncState WHERE key = ?", arguments: [key])
            }
        }
    }

    // MARK: - Internals

    /// Runs FTS5's own consistency check against the content view. Throws if the index has drifted.
    func checkSearchIndex() async throws {
        try await pool.write { db in
            try db.execute(sql: "INSERT INTO itemsFTS (itemsFTS, rank) VALUES ('integrity-check', 1)")
        }
    }

    /// The SQLite journal mode, for tests.
    func journalMode() async throws -> String? {
        try await pool.read { db in try String.fetchOne(db, sql: "PRAGMA journal_mode") }
    }

    private func postChange() {
        notify_post(changeNotificationName)
    }

    private func updateOutbox(_ id: OutboxEntry.ID, state: OutboxState, error: String?) async throws {
        let changed = try await pool.write { db -> Bool in
            try db.execute(
                sql: """
                    UPDATE outbox SET state = ?, lastError = ?, attempts = attempts + 1, updatedAt = ?
                    WHERE id = ? AND state != ?
                    """,
                arguments: [state.rawValue, error, Date(), id, OutboxState.sent.rawValue])
            return db.changesCount > 0
        }
        if changed { postChange() }
    }

    private static func openPool(at url: URL) throws -> DatabasePool {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        var configuration = Configuration()
        // Writers in other processes wait for each other instead of failing with SQLITE_BUSY.
        configuration.busyMode = .timeout(10)
        // The app posts `Database.suspendNotification` before suspension so iOS doesn't kill it (0xDEAD10CC)
        // for holding a lock.
        configuration.observesSuspensionNotifications = true
        configuration.prepareDatabase { db in
            // Persistent WAL keeps the -wal and -shm files, so a connection in another process never has to
            // recreate them (GRDB "Sharing a Database").
            if !db.configuration.readonly {
                var flag: CInt = 1
                let code = sqlite3_file_control(db.sqliteConnection, nil, SQLITE_FCNTL_PERSIST_WAL, &flag)
                guard code == SQLITE_OK else { throw DatabaseError(resultCode: ResultCode(rawValue: code)) }
            }
        }

        // Several processes may create or migrate the file at once; coordinate that.
        var pool: DatabasePool?
        var openError: (any Error)?
        var coordinationError: NSError?
        NSFileCoordinator(filePresenter: nil).coordinate(
            writingItemAt: url, options: .forMerging, error: &coordinationError
        ) { url in
            do {
                let opened = try DatabasePool(path: url.path(percentEncoded: false), configuration: configuration)
                try StoreSchema.migrator.migrate(opened)
                pool = opened
            } catch {
                openError = error
            }
        }
        if let error = openError ?? coordinationError { throw error }
        guard let pool else { throw CocoaError(.fileReadUnknown) }
        return pool
    }

    private static func defaultNotificationName(for url: URL) -> String {
        let path = url.resolvingSymlinksInPath().path(percentEncoded: false)
        let digest = SHA256.hash(data: Data(path.utf8)).prefix(12).map { String(format: "%02x", $0) }.joined()
        return "satchel.store.\(digest).changed"
    }

    // MARK: Rows

    @discardableResult
    private static func writeItem(_ item: Item, seq: Int64?, _ db: Database) throws -> Int64 {
        let arguments: StatementArguments = [
            item.kind.rawValue, item.createdAt, item.updatedAt, epoch(item.createdAt), epoch(item.updatedAt),
            item.metadataStatus.rawValue, item.title, item.description, site(of: item),
            item.tags.joined(separator: " "),
            try encodeItem(item),
        ]
        if let seq {
            try db.execute(
                sql: """
                    UPDATE items SET kind = ?, createdAt = ?, updatedAt = ?, createdTime = ?, updatedTime = ?,
                        metadataStatus = ?, title = ?, description = ?, site = ?, tags = ?, json = ?
                    WHERE seq = ?
                    """,
                arguments: arguments + [seq])
            return seq
        }
        try db.execute(
            sql: """
                INSERT INTO items (id, kind, createdAt, updatedAt, createdTime, updatedTime, metadataStatus,
                    title, description, site, tags, json)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """,
            arguments: [item.id] + arguments)
        return db.lastInsertedRowID
    }

    private static func writeTags(_ item: Item, _ db: Database) throws {
        try db.execute(sql: "DELETE FROM itemTags WHERE itemID = ?", arguments: [item.id])
        for tag in Set(item.tags.map(normalizeTag)) where !tag.isEmpty {
            try db.execute(sql: "INSERT INTO itemTags (itemID, tag) VALUES (?, ?)", arguments: [item.id, tag])
        }
    }

    /// Adds the item's current search values (read back from `itemSearch`) to the FTS index.
    private static func index(seq: Int64, _ db: Database) throws {
        try db.execute(
            sql: """
                INSERT INTO itemsFTS (rowid, title, description, site, tags, body)
                SELECT seq, title, description, site, tags, body FROM itemSearch WHERE seq = ?
                """,
            arguments: [seq])
    }

    /// Removes the item from the FTS index. Must run before its row or body changes, so the 'delete' command
    /// passes exactly the values that were indexed.
    private static func unindex(seq: Int64, _ db: Database) throws {
        try db.execute(
            sql: """
                INSERT INTO itemsFTS (itemsFTS, rowid, title, description, site, tags, body)
                SELECT 'delete', seq, title, description, site, tags, body FROM itemSearch WHERE seq = ?
                """,
            arguments: [seq])
    }

    /// Replaces any earlier entry for the item, so the outbox holds only the latest change per item.
    private static func enqueue(_ operation: OutboxOperation, itemID: String, payload: String?, _ db: Database) throws {
        let now = Date()
        try db.execute(sql: "DELETE FROM outbox WHERE itemID = ?", arguments: [itemID])
        try db.execute(
            sql: """
                INSERT INTO outbox (itemID, operation, payload, state, attempts, createdAt, updatedAt)
                VALUES (?, ?, ?, ?, 0, ?, ?)
                """,
            arguments: [itemID, operation.rawValue, payload, OutboxState.pending.rawValue, now, now])
    }

    private static func fetchItems(_ db: Database, query: String?, filter: ItemFilter) throws -> [Item] {
        var sql = "SELECT items.json FROM items"
        var conditions: [String] = []
        var arguments = StatementArguments()
        let pattern = SearchPattern.make(query)
        if let pattern {
            sql += " JOIN itemsFTS ON itemsFTS.rowid = items.seq"
            conditions.append("itemsFTS MATCH ?")
            arguments += [pattern]
        }
        if let kind = filter.kind {
            conditions.append("items.kind = ?")
            arguments += [kind.rawValue]
        }
        if let tag = filter.tag.map(normalizeTag) {
            conditions.append("EXISTS (SELECT 1 FROM itemTags WHERE itemTags.itemID = items.id AND itemTags.tag = ?)")
            arguments += [tag]
        }
        if let status = filter.metadataStatus {
            conditions.append("items.metadataStatus = ?")
            arguments += [status.rawValue]
        }
        if !conditions.isEmpty {
            sql += " WHERE " + conditions.joined(separator: " AND ")
        }
        switch filter.order {
        case .relevance where pattern != nil:
            sql += " ORDER BY itemsFTS.rank, items.updatedTime DESC, items.seq DESC"
        case .recentlyCreated:
            sql += " ORDER BY items.createdTime DESC, items.seq DESC"
        case .recentlyUpdated, .relevance:
            sql += " ORDER BY items.updatedTime DESC, items.seq DESC"
        }
        if let limit = filter.limit {
            sql += " LIMIT ?"
            arguments += [limit]
        }
        return try String.fetchAll(db, sql: sql, arguments: arguments).map(decodeItem)
    }

    private static func fetchUnsentStates(_ db: Database) throws -> [String: OutboxState] {
        var states: [String: OutboxState] = [:]
        let rows = try Row.fetchAll(
            db, sql: "SELECT itemID, state FROM outbox WHERE state != ? ORDER BY id",
            arguments: [OutboxState.sent.rawValue])
        for row in rows {
            if let state = OutboxState(rawValue: row["state"]) { states[row["itemID"]] = state }
        }
        return states
    }

    private static func outboxEntry(_ row: Row) throws -> OutboxEntry {
        let payload: String? = row["payload"]
        return OutboxEntry(
            id: row["id"],
            itemID: row["itemID"],
            operation: OutboxOperation(rawValue: row["operation"]) ?? .upsert,
            item: try payload.map(decodeItem),
            state: OutboxState(rawValue: row["state"]) ?? .pending,
            attempts: row["attempts"],
            lastError: row["lastError"],
            createdAt: row["createdAt"],
            updatedAt: row["updatedAt"])
    }

    // MARK: Values

    private static func encodeItem(_ item: Item) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return String(decoding: try encoder.encode(item), as: UTF8.self)
    }

    private static func decodeItem(_ json: String) throws -> Item {
        try JSONDecoder().decode(Item.self, from: Data(json.utf8))
    }

    static func normalizeTag(_ tag: String) -> String {
        tag.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    /// The site name plus the host (without `www.`), so searching "github" finds github.com pages.
    static func site(of item: Item) -> String? {
        var host = URL(string: item.canonicalURL)?.host(percentEncoded: false) ?? URL(string: item.url)?.host()
        if let current = host, current.hasPrefix("www.") { host = String(current.dropFirst(4)) }
        let parts = [item.siteName, host].compactMap { $0 }.filter { !$0.isEmpty }
        return parts.isEmpty ? nil : parts.joined(separator: " ")
    }

    /// Seconds since 1970 for an ISO 8601 string, with or without fractional seconds; 0 if it doesn't parse.
    static func epoch(_ iso: String) -> Double {
        if let date = try? Date(iso, strategy: Date.ISO8601FormatStyle(includingFractionalSeconds: true)) {
            return date.timeIntervalSince1970
        }
        if let date = try? Date(iso, strategy: .iso8601) { return date.timeIntervalSince1970 }
        return 0
    }
}
