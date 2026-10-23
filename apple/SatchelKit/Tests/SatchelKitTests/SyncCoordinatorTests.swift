import CloudKit
import Foundation
import Synchronization
import Testing

@testable import SatchelKit

/// Stands in for `CKSyncEngine.State`: the pending changes the coordinator adds and removes.
final class FakeQueue: SyncChangeQueue {
    private let changes = Mutex<
        (records: [CKSyncEngine.PendingRecordZoneChange], zones: [CKSyncEngine.PendingDatabaseChange])
    >(
        ([], []))

    var pendingRecordZoneChanges: [CKSyncEngine.PendingRecordZoneChange] { changes.withLock { $0.records } }
    var pendingDatabaseChanges: [CKSyncEngine.PendingDatabaseChange] { changes.withLock { $0.zones } }

    func add(pendingRecordZoneChanges added: [CKSyncEngine.PendingRecordZoneChange]) {
        changes.withLock { state in
            for change in added where !state.records.contains(change) { state.records.append(change) }
        }
    }

    func remove(pendingRecordZoneChanges removed: [CKSyncEngine.PendingRecordZoneChange]) {
        changes.withLock { $0.records.removeAll { removed.contains($0) } }
    }

    func add(pendingDatabaseChanges added: [CKSyncEngine.PendingDatabaseChange]) {
        changes.withLock { state in
            for change in added where !state.zones.contains(change) { state.zones.append(change) }
        }
    }
}

@Suite struct SyncCoordinatorTests {
    final class Fixture {
        let directory: TempDirectory
        let store: Store
        let mapper: ItemRecordMapper
        let coordinator: SyncCoordinator
        let queue = FakeQueue()

        init() throws {
            directory = try TempDirectory()
            store = try Store(url: directory.database, merge: SatchelModelTests.model.itemMerge)
            mapper = ItemRecordMapper(zoneName: "Library", assetDirectory: directory.url.appending(path: "assets"))
            coordinator = SyncCoordinator(store: store, mapper: mapper)
        }

        func id(_ itemID: String) -> CKRecord.ID { mapper.recordID(forItemID: itemID) }

        /// The server's copy of `item`, as another device would have written it.
        func serverRecord(_ item: Item, body: String? = nil) throws -> CKRecord {
            try mapper.record(for: item, body: body)
        }

        func outbox(_ itemID: String) async throws -> OutboxState? { try await store.outboxState(for: itemID) }
    }

    // MARK: Outbox → engine

    @Test func queuesEveryUnsentOutboxEntryOnce() async throws {
        let f = try Fixture()
        try await f.store.save(item: makeItem("a"))
        try await f.store.save(item: makeItem("b"))
        try await f.store.save(item: makeItem("c"))
        try await f.store.delete(id: "u_b")
        try await f.store.markSent(try #require(try await f.store.unsentOutboxEntry(for: "u_c")).id)

        #expect(try await f.coordinator.enqueueOutbox(into: f.queue) == 2)
        #expect(f.queue.pendingRecordZoneChanges == [.saveRecord(f.id("u_a")), .deleteRecord(f.id("u_b"))])
        #expect(try await f.coordinator.enqueueOutbox(into: f.queue) == 0)
    }

    @Test func aLocalDeleteReplacesAPendingSave() async throws {
        let f = try Fixture()
        try await f.store.save(item: makeItem("a"))
        try await f.coordinator.enqueueOutbox(into: f.queue)
        try await f.store.delete(id: "u_a")
        try await f.coordinator.enqueueOutbox(into: f.queue)
        #expect(f.queue.pendingRecordZoneChanges == [.deleteRecord(f.id("u_a"))])
    }

    // MARK: Sending

    @Test func aSavedRecordMarksItsOutboxEntrySent() async throws {
        let f = try Fixture()
        try await f.store.save(item: makeItem("a", title: "Hello"))
        try await f.coordinator.enqueueOutbox(into: f.queue)
        let record = try #require(await f.coordinator.record(for: f.id("u_a"), queue: f.queue))
        #expect(record["title"] as? String == "Hello")

        try await f.coordinator.handleSent(
            saved: [record], failedSaves: [], deleted: [], failedDeletes: [:], queue: f.queue)
        #expect(try await f.outbox("u_a") == .sent)
        #expect(try await f.store.syncState(forKey: SyncCoordinator.Key.systemFieldsPrefix + "u_a") != nil)
    }

    @Test func aSaveMadeWhileSendingStaysPending() async throws {
        let f = try Fixture()
        try await f.store.save(item: makeItem("a"))
        let record = try #require(await f.coordinator.record(for: f.id("u_a"), queue: f.queue))
        try await f.store.save(item: makeItem("a", tags: ["later"], updatedAt: "2026-10-02T10:00:00.000Z"))

        try await f.coordinator.handleSent(
            saved: [record], failedSaves: [], deleted: [], failedDeletes: [:], queue: f.queue)
        #expect(try await f.outbox("u_a") == .pending)
    }

    @Test func nothingToSendRemovesThePendingChange() async throws {
        let f = try Fixture()
        try await f.store.save(item: makeItem("a"))
        try await f.store.markSent(try #require(try await f.store.unsentOutboxEntry(for: "u_a")).id)
        f.queue.add(pendingRecordZoneChanges: [.saveRecord(f.id("u_a")), .saveRecord(f.id("u_missing"))])

        #expect(await f.coordinator.record(for: f.id("u_a"), queue: f.queue) == nil)
        #expect(await f.coordinator.record(for: f.id("u_missing"), queue: f.queue) == nil)
        #expect(f.queue.pendingRecordZoneChanges.isEmpty)
    }

    // MARK: Conflicts

    @Test func aConflictMergesTheServerCopyAndSendsAgain() async throws {
        let f = try Fixture()
        let local = makeItem("a", title: "Local title", tags: ["swift"], updatedAt: "2026-10-03T10:00:00.000Z")
        try await f.store.save(item: local)
        let attempt = try #require(await f.coordinator.record(for: f.id("u_a"), queue: f.queue))

        var remote = makeItem("a", title: "Server title", tags: ["ios"], updatedAt: "2026-10-02T10:00:00.000Z")
        remote.note = "from the Mac"
        let server = try f.serverRecord(remote)
        let conflict = CKError(.serverRecordChanged, userInfo: [CKRecordChangedErrorServerRecordKey: server])
        try await f.coordinator.handleSent(
            saved: [], failedSaves: [.init(record: attempt, error: conflict)], deleted: [], failedDeletes: [:],
            queue: f.queue)

        let merged = try #require(try await f.store.item(id: "u_a"))
        #expect(Set(merged.tags) == ["swift", "ios"])
        #expect(merged.title == "Local title")
        #expect(merged.note == "from the Mac")
        #expect(try await f.outbox("u_a") == .pending)
        #expect(try await f.store.unsentOutboxEntry(for: "u_a")?.item == merged)
        #expect(f.queue.pendingRecordZoneChanges == [.saveRecord(f.id("u_a"))])

        // The retry carries the merged item on top of the server's record, and succeeds.
        let retry = try #require(await f.coordinator.record(for: f.id("u_a"), queue: f.queue))
        #expect(Set(retry["tags"] as? [String] ?? []) == ["swift", "ios"])
        #expect(retry["note"] as? String == "from the Mac")
        try await f.coordinator.handleSent(
            saved: [retry], failedSaves: [], deleted: [], failedDeletes: [:], queue: f.queue)
        #expect(try await f.outbox("u_a") == .sent)
    }

    @Test func aConflictWithoutTheServerCopyIsMarkedFailed() async throws {
        let f = try Fixture()
        try await f.store.save(item: makeItem("a"))
        let attempt = try #require(await f.coordinator.record(for: f.id("u_a"), queue: f.queue))
        try await f.coordinator.handleSent(
            saved: [], failedSaves: [.init(record: attempt, error: CKError(.serverRecordChanged))], deleted: [],
            failedDeletes: [:], queue: f.queue)
        #expect(try await f.outbox("u_a") == .failed)
    }

    @Test func aMissingZoneIsCreatedBeforeSavingAgain() async throws {
        let f = try Fixture()
        try await f.store.save(item: makeItem("a"))
        let attempt = try #require(await f.coordinator.record(for: f.id("u_a"), queue: f.queue))
        try await f.coordinator.handleSent(
            saved: [], failedSaves: [.init(record: attempt, error: CKError(.zoneNotFound))], deleted: [],
            failedDeletes: [:], queue: f.queue)
        #expect(f.queue.pendingDatabaseChanges == [.saveZone(CKRecordZone(zoneID: f.mapper.zoneID))])
        #expect(f.queue.pendingRecordZoneChanges == [.saveRecord(f.id("u_a"))])
    }

    @Test func aNetworkFailureShowsOnTheOutboxEntry() async throws {
        let f = try Fixture()
        try await f.store.save(item: makeItem("a"))
        let attempt = try #require(await f.coordinator.record(for: f.id("u_a"), queue: f.queue))
        try await f.coordinator.handleSent(
            saved: [], failedSaves: [.init(record: attempt, error: CKError(.networkUnavailable))], deleted: [],
            failedDeletes: [:], queue: f.queue)
        let entry = try #require(try await f.store.unsentOutboxEntry(for: "u_a"))
        #expect(entry.state == .failed)
        #expect(entry.lastError == "network unavailable")
    }

    @Test func aDeleteOfAMissingRecordCountsAsSent() async throws {
        let f = try Fixture()
        try await f.store.save(item: makeItem("a"))
        try await f.store.delete(id: "u_a")
        try await f.coordinator.handleSent(
            saved: [], failedSaves: [], deleted: [], failedDeletes: [f.id("u_a"): CKError(.unknownItem)],
            queue: f.queue)
        #expect(try await f.outbox("u_a") == .sent)
    }

    // MARK: Fetched changes

    @Test func aFetchedRecordReplacesASyncedItem() async throws {
        let f = try Fixture()
        try await f.store.save(item: makeItem("a", tags: ["keep", "drop"]))
        try await f.store.markSent(try #require(try await f.store.unsentOutboxEntry(for: "u_a")).id)

        let server = try f.serverRecord(makeItem("a", tags: ["keep"], updatedAt: "2026-10-02T10:00:00.000Z"))
        try await f.coordinator.handleFetched(modifications: [server], deletions: [], queue: f.queue)
        // No merge: a tag removed on another device stays removed.
        #expect(try await f.store.item(id: "u_a")?.tags == ["keep"])
        #expect(f.queue.pendingRecordZoneChanges.isEmpty)
        #expect(try await f.outbox("u_a") == .sent)
    }

    @Test func aFetchedRecordMergesIntoAnUnsentSave() async throws {
        let f = try Fixture()
        try await f.store.save(item: makeItem("a", tags: ["offline"], updatedAt: "2026-10-03T10:00:00.000Z"))
        let server = try f.serverRecord(makeItem("a", tags: ["online"], updatedAt: "2026-10-02T10:00:00.000Z"))
        try await f.coordinator.handleFetched(modifications: [server], deletions: [], queue: f.queue)

        #expect(Set(try await f.store.item(id: "u_a")?.tags ?? []) == ["offline", "online"])
        #expect(f.queue.pendingRecordZoneChanges == [.saveRecord(f.id("u_a"))])
    }

    @Test func aFetchedPageBringsItsBody() async throws {
        let f = try Fixture()
        let server = try f.serverRecord(makeItem("a", kind: .page), body: "# Hello\n")
        try await f.coordinator.handleFetched(modifications: [server], deletions: [], queue: f.queue)
        #expect(try await f.store.body(for: "u_a") == "# Hello\n")
        #expect(try await f.outbox("u_a") == nil)
    }

    @Test func anUnsentLocalDeleteWinsOverAFetchedRecord() async throws {
        let f = try Fixture()
        try await f.store.save(item: makeItem("a"))
        try await f.store.delete(id: "u_a")
        try await f.coordinator.handleFetched(
            modifications: [try f.serverRecord(makeItem("a", title: "Edited elsewhere"))], deletions: [],
            queue: f.queue)
        #expect(try await f.store.item(id: "u_a") == nil)
        #expect(try await f.store.unsentOutboxEntry(for: "u_a")?.operation == .delete)
    }

    @Test func aFetchedDeletionRemovesTheItem() async throws {
        let f = try Fixture()
        try await f.store.save(item: makeItem("a"))
        try await f.store.markSent(try #require(try await f.store.unsentOutboxEntry(for: "u_a")).id)
        try await f.coordinator.handleFetched(modifications: [], deletions: [f.id("u_a")], queue: f.queue)
        #expect(try await f.store.item(id: "u_a") == nil)
        #expect(try await f.outbox("u_a") == nil)
        #expect(try await f.store.items().isEmpty)
    }

    @Test func anUnsentSaveSurvivesAFetchedDeletion() async throws {
        let f = try Fixture()
        try await f.store.save(item: makeItem("a"))
        try await f.coordinator.handleFetched(modifications: [], deletions: [f.id("u_a")], queue: f.queue)
        #expect(try await f.store.item(id: "u_a") != nil)
        #expect(f.queue.pendingRecordZoneChanges == [.saveRecord(f.id("u_a"))])
    }

    // MARK: Account and zone

    @Test func theFirstAccountOwnsTheLibrary() async throws {
        let f = try Fixture()
        #expect(try await f.coordinator.checkAccount(userRecordName: "_alice") == .adopted)
        #expect(try await f.coordinator.checkAccount(userRecordName: "_alice") == .same)
        #expect(try await f.coordinator.checkAccount(userRecordName: "_bob") == .different)
    }

    @Test func signingOutKeepsTheLibraryAndOutbox() async throws {
        let f = try Fixture()
        try await f.store.save(item: makeItem("a"))
        _ = try await f.coordinator.checkAccount(userRecordName: "_alice")
        let record = try #require(await f.coordinator.record(for: f.id("u_a"), queue: f.queue))
        try await f.coordinator.handleSent(
            saved: [record], failedSaves: [], deleted: [], failedDeletes: [:], queue: f.queue)
        try await f.store.save(item: makeItem("b"))

        try await f.coordinator.forgetServerState()
        #expect(try await f.store.syncState(forKey: SyncCoordinator.Key.systemFieldsPrefix + "u_a") == nil)
        #expect(try await f.store.items().count == 2)
        #expect(try await f.outbox("u_b") == .pending)
        #expect(try await f.coordinator.checkAccount(userRecordName: "_alice") == .same)
    }

    @Test func aPurgedZoneErasesTheLocalCopy() async throws {
        let f = try Fixture()
        _ = try await f.coordinator.checkAccount(userRecordName: "_alice")
        try await f.store.save(item: makeItem("a"))
        try await f.coordinator.handleZoneDeleted(reason: .purged, queue: f.queue)
        #expect(try await f.store.items().isEmpty)
        #expect(try await f.store.pendingOutbox().isEmpty)
        #expect(try await f.coordinator.checkAccount(userRecordName: "_alice") == .same)
    }

    @Test func anEncryptedDataResetUploadsEverythingAgain() async throws {
        let f = try Fixture()
        for slug in ["a", "b"] {
            try await f.store.save(item: makeItem(slug))
            try await f.store.markSent(try #require(try await f.store.unsentOutboxEntry(for: "u_\(slug)")).id)
        }
        try await f.coordinator.handleZoneDeleted(reason: .encryptedDataReset, queue: f.queue)
        #expect(f.queue.pendingDatabaseChanges == [.saveZone(CKRecordZone(zoneID: f.mapper.zoneID))])
        #expect(Set(f.queue.pendingRecordZoneChanges) == [.saveRecord(f.id("u_a")), .saveRecord(f.id("u_b"))])
    }
}
