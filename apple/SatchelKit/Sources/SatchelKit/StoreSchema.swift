import Foundation
import GRDB

/// The local store's schema (ADR-0017).
///
/// The app and both extensions open the same file, and an extension process that is still running can open a
/// database that a newer app has already migrated. So every migration must be additive and leave the database
/// usable by the previous version: add tables, columns with defaults, and indexes; never rename or drop. A store
/// whose file has migrations it doesn't know opens normally.
enum StoreSchema {
    static var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()
        migrator.registerMigration("v1") { db in
            try createV1(db)
        }
        return migrator
    }

    private static func createV1(_ db: Database) throws {
        // `seq` is the FTS rowid. An explicit INTEGER PRIMARY KEY keeps it stable across VACUUM.
        try db.create(table: "items") { t in
            t.column("seq", .integer).primaryKey(autoincrement: true)
            t.column("id", .text).notNull().unique()
            t.column("kind", .text).notNull()
            t.column("createdAt", .text).notNull()
            t.column("updatedAt", .text).notNull()
            // Seconds since 1970, parsed from the ISO 8601 strings, for sorting.
            t.column("createdTime", .double).notNull()
            t.column("updatedTime", .double).notNull()
            t.column("metadataStatus", .text).notNull()
            // Search columns, kept beside the JSON so the FTS index reads them back exactly (see `itemSearch`).
            t.column("title", .text).notNull()
            t.column("description", .text)
            t.column("site", .text)
            t.column("tags", .text).notNull()
            // The whole item as packages/model JSON, unknown fields included (spec §7.1).
            t.column("json", .text).notNull()
        }
        try db.create(index: "items_kind", on: "items", columns: ["kind"])
        try db.create(index: "items_createdTime", on: "items", columns: ["createdTime"])
        try db.create(index: "items_updatedTime", on: "items", columns: ["updatedTime"])
        try db.create(index: "items_metadataStatus", on: "items", columns: ["metadataStatus"])

        // Rowid tables throughout: GRDB's observation doesn't see changes to WITHOUT ROWID tables.
        try db.create(table: "itemTags") { t in
            t.column("itemID", .text).notNull().references("items", column: "id", onDelete: .cascade)
            t.column("tag", .text).notNull()
            t.primaryKey(["itemID", "tag"])
        }
        try db.create(index: "itemTags_tag", on: "itemTags", columns: ["tag"])

        try db.create(table: "bodies") { t in
            t.primaryKey("itemID", .text).references("items", column: "id", onDelete: .cascade)
            t.column("markdown", .text).notNull()
        }

        try db.create(table: "outbox") { t in
            t.autoIncrementedPrimaryKey("id")
            t.column("itemID", .text).notNull()
            t.column("operation", .text).notNull()
            t.column("payload", .text)
            t.column("state", .text).notNull().defaults(to: OutboxState.pending.rawValue)
            t.column("attempts", .integer).notNull().defaults(to: 0)
            t.column("lastError", .text)
            t.column("createdAt", .datetime).notNull()
            t.column("updatedAt", .datetime).notNull()
        }
        try db.create(index: "outbox_state", on: "outbox", columns: ["state", "id"])
        try db.create(index: "outbox_itemID", on: "outbox", columns: ["itemID", "id"])

        // Opaque values by key; ticket 07 keeps the CKSyncEngine serialized state here.
        try db.create(table: "syncState") { t in
            t.primaryKey("key", .text)
            t.column("value", .blob).notNull()
        }

        // FTS5 over title, description, site, tags, and body (FR-7), external content from this view. The store
        // keeps it in sync with explicit 'delete' and insert statements that read the same view (`Store.unindex`
        // and `Store.index`), so the indexed values always match.
        try db.execute(
            sql: """
                CREATE VIEW itemSearch AS
                SELECT items.seq AS seq, items.title AS title, items.description AS description,
                       items.site AS site, items.tags AS tags, bodies.markdown AS body
                FROM items LEFT JOIN bodies ON bodies.itemID = items.id;

                CREATE VIRTUAL TABLE itemsFTS USING fts5(
                    title, description, site, tags, body,
                    content = 'itemSearch', content_rowid = 'seq',
                    tokenize = 'unicode61 remove_diacritics 2',
                    prefix = '2 3'
                );
                """)
    }
}
