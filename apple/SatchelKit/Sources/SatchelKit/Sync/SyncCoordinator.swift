import CloudKit
import Foundation
import Synchronization

/// The pending changes a `SyncCoordinator` reads and edits: `CKSyncEngine.State` in the app, a fake in tests.
public protocol SyncChangeQueue: Sendable {
    var pendingRecordZoneChanges: [CKSyncEngine.PendingRecordZoneChange] { get }
    func add(pendingRecordZoneChanges: [CKSyncEngine.PendingRecordZoneChange])
    func remove(pendingRecordZoneChanges: [CKSyncEngine.PendingRecordZoneChange])
    func add(pendingDatabaseChanges: [CKSyncEngine.PendingDatabaseChange])
}

extension CKSyncEngine.State: SyncChangeQueue {}

/// What the host app's sync does with CloudKit's answers (spec §9.2.4), apart from CKSyncEngine itself, so it can be
/// tested with plain records and errors. `LibrarySync` forwards the engine's events and batch requests here.
///
/// - **Outbox:** every unsent outbox entry (from the app or either extension) becomes a pending save or delete.
///   Records are built from the item as stored when the engine asks for them, on top of the server's last known
///   system fields, so CloudKit's change tag catches conflicts. A save is marked `sent` only if its outbox entry
///   wasn't replaced by a newer change meanwhile.
/// - **Conflicts:** on `serverRecordChanged`, the server copy is merged into the local item with `SatchelModel.merge`
///   (spec §7.3) and sent again on top of the server's system fields.
/// - **Fetched changes** go through `Store.applyRemote(_:body:)` and `Store.applyRemoteDeletion(id:)`, where an unsent
///   local change wins.
public final class SyncCoordinator: Sendable {
    /// `syncState` keys.
    public enum Key {
        /// `CKSyncEngine.State.Serialization`, as JSON.
        public static let engineState = "ckSyncEngine.state"
        /// The record name of the iCloud user the library belongs to.
        public static let account = "account.userRecordName"
        /// Prefix of each record's archived system fields (change tag and so on), keyed by item ID.
        public static let systemFieldsPrefix = "systemFields/"
    }

    /// Whether the iCloud account now signed in may sync this library.
    public enum AccountCheck: Sendable, Equatable {
        /// The first account seen; the library now belongs to it.
        case adopted
        case same
        /// The library belongs to another iCloud account. Syncing would mix two accounts' data, so it stays paused.
        case different
    }

    public let store: Store
    public let mapper: ItemRecordMapper
    /// The outbox entry each record in flight was built from, by item ID.
    private let inFlight = Mutex<[String: OutboxEntry.ID]>([:])

    public init(store: Store, mapper: ItemRecordMapper) {
        self.store = store
        self.mapper = mapper
    }

    // MARK: Account

    /// Compares the signed-in user with the one the library belongs to, adopting it if there's none yet.
    public func checkAccount(userRecordName: String) async throws -> AccountCheck {
        guard let stored = try await store.syncState(forKey: Key.account) else {
            try await store.setSyncState(Data(userRecordName.utf8), forKey: Key.account)
            return .adopted
        }
        return String(decoding: stored, as: UTF8.self) == userRecordName ? .same : .different
    }

    /// Forgets the engine state and every record's system fields, which belong to the account that signed out. The
    /// library, its owner, and the outbox are kept.
    public func forgetServerState() async throws {
        try await store.setSyncState(nil, forKey: Key.engineState)
        try await store.removeSyncState(keyPrefix: Key.systemFieldsPrefix)
        inFlight.withLock { $0.removeAll() }
    }

    public func engineState() async throws -> CKSyncEngine.State.Serialization? {
        guard let data = try await store.syncState(forKey: Key.engineState) else { return nil }
        return try? JSONDecoder().decode(CKSyncEngine.State.Serialization.self, from: data)
    }

    public func saveEngineState(_ state: CKSyncEngine.State.Serialization) async throws {
        try await store.setSyncState(try JSONEncoder().encode(state), forKey: Key.engineState)
    }

    // MARK: Outbox → engine

    /// Adds a pending save or delete for every unsent outbox entry that the queue doesn't already have. Returns how
    /// many changes were added.
    @discardableResult
    public func enqueueOutbox(into queue: some SyncChangeQueue) async throws -> Int {
        let entries = try await store.pendingOutbox(limit: .max)
        let pending = Set(queue.pendingRecordZoneChanges)
        var added: [CKSyncEngine.PendingRecordZoneChange] = []
        var replaced: [CKSyncEngine.PendingRecordZoneChange] = []
        for entry in entries {
            let id = mapper.recordID(forItemID: entry.itemID)
            let change: CKSyncEngine.PendingRecordZoneChange
            let opposite: CKSyncEngine.PendingRecordZoneChange
            switch entry.operation {
            case .upsert: (change, opposite) = (.saveRecord(id), .deleteRecord(id))
            case .delete: (change, opposite) = (.deleteRecord(id), .saveRecord(id))
            }
            if pending.contains(opposite) { replaced.append(opposite) }
            if !pending.contains(change) { added.append(change) }
        }
        if !replaced.isEmpty { queue.remove(pendingRecordZoneChanges: replaced) }
        if !added.isEmpty { queue.add(pendingRecordZoneChanges: added) }
        return added.count
    }

    /// The record to send for a pending save, or `nil` (removing the pending change) when there's nothing to send:
    /// the item is gone, its outbox entry was already sent, or it can't be mapped (its entry is marked failed).
    public func record(for recordID: CKRecord.ID, queue: some SyncChangeQueue) async -> CKRecord? {
        let itemID = recordID.recordName
        do {
            guard let item = try await store.item(id: itemID),
                let entry = try await store.unsentOutboxEntry(for: itemID), entry.operation == .upsert
            else {
                queue.remove(pendingRecordZoneChanges: [.saveRecord(recordID)])
                return nil
            }
            do {
                let record = try mapper.record(
                    for: item, body: try await store.body(for: itemID), updating: try await systemFields(for: itemID))
                inFlight.withLock { $0[itemID] = entry.id }
                return record
            } catch let error as ItemRecordMappingError {
                try await store.markFailed(entry.id, error: OneShotFailure.invalidItem("\(error)").description)
                queue.remove(pendingRecordZoneChanges: [.saveRecord(recordID)])
                return nil
            }
        } catch {
            // The store failed to read; leave the change pending for the next send.
            return nil
        }
    }

    // MARK: Sent changes

    public struct FailedSave: Sendable {
        public let record: CKRecord
        public let error: CKError

        public init(record: CKRecord, error: CKError) {
            self.record = record
            self.error = error
        }
    }

    /// Applies the result of a send: marks outbox entries, keeps system fields, and handles each failure.
    public func handleSent(
        saved: [CKRecord], failedSaves: [FailedSave], deleted: [CKRecord.ID], failedDeletes: [CKRecord.ID: CKError],
        queue: some SyncChangeQueue
    ) async throws {
        for record in saved {
            let itemID = record.recordID.recordName
            try await setSystemFields(of: record)
            if let entryID = inFlight.withLock({ $0.removeValue(forKey: itemID) }) {
                try await store.markSent(entryID)
            }
            mapper.removeAssetFile(of: record)
        }
        for failure in failedSaves {
            try await handleFailedSave(failure, queue: queue)
        }
        for id in deleted {
            try await markDeleteSent(id)
        }
        for (id, error) in failedDeletes {
            switch error.code {
            case .unknownItem, .zoneNotFound, .userDeletedZone:
                try await markDeleteSent(id)
            default:
                if let entry = try await store.unsentOutboxEntry(for: id.recordName), entry.operation == .delete {
                    try await store.markFailed(entry.id, error: OneShotFailure(error).description)
                }
            }
        }
    }

    private func handleFailedSave(_ failure: FailedSave, queue: some SyncChangeQueue) async throws {
        let record = failure.record
        let recordID = record.recordID
        let itemID = recordID.recordName
        mapper.removeAssetFile(of: record)
        let entryID = inFlight.withLock { $0.removeValue(forKey: itemID) }
        switch failure.error.code {
        case .serverRecordChanged:
            guard let server = failure.error.serverRecord else {
                try await markFailed(entryID, failure.error)
                return
            }
            // Merge the server copy into the local one and send the result on top of the server's change tag.
            try await setSystemFields(of: server)
            if case .merged = try await applyFetched(server) {
                queue.add(pendingRecordZoneChanges: [.saveRecord(recordID)])
            }
        case .zoneNotFound, .userDeletedZone:
            // Create the zone, then save again as a new record.
            try await store.setSyncState(nil, forKey: Key.systemFieldsPrefix + itemID)
            queue.add(pendingDatabaseChanges: [.saveZone(CKRecordZone(zoneID: mapper.zoneID))])
            queue.add(pendingRecordZoneChanges: [.saveRecord(recordID)])
        case .unknownItem:
            // The record was deleted on the server; the local save wins and creates it again.
            try await store.setSyncState(nil, forKey: Key.systemFieldsPrefix + itemID)
            queue.add(pendingRecordZoneChanges: [.saveRecord(recordID)])
        case .networkFailure, .networkUnavailable, .zoneBusy, .serviceUnavailable, .notAuthenticated,
            .operationCancelled, .requestRateLimited:
            // CKSyncEngine retries these itself.
            try await markFailed(entryID, failure.error)
        case .quotaExceeded:
            try await markFailed(entryID, failure.error)
            queue.add(pendingRecordZoneChanges: [.saveRecord(recordID)])
        default:
            try await markFailed(entryID, failure.error)
        }
    }

    private func markFailed(_ entryID: OutboxEntry.ID?, _ error: CKError) async throws {
        guard let entryID else { return }
        try await store.markFailed(entryID, error: OneShotFailure(error).description)
    }

    private func markDeleteSent(_ id: CKRecord.ID) async throws {
        try await store.setSyncState(nil, forKey: Key.systemFieldsPrefix + id.recordName)
        if let entry = try await store.unsentOutboxEntry(for: id.recordName), entry.operation == .delete {
            try await store.markSent(entry.id)
        }
    }

    // MARK: Fetched changes

    /// Applies records and deletions fetched from the server. Items whose unsent local change won are queued to send.
    public func handleFetched(modifications: [CKRecord], deletions: [CKRecord.ID], queue: some SyncChangeQueue)
        async throws
    {
        for record in modifications where record.recordType == ItemRecordMapper.recordType {
            try await setSystemFields(of: record)
            if case .merged = try await applyFetched(record) {
                queue.add(pendingRecordZoneChanges: [.saveRecord(record.recordID)])
            }
        }
        for id in deletions {
            try await store.setSyncState(nil, forKey: Key.systemFieldsPrefix + id.recordName)
            if case .keptLocalSave = try await store.applyRemoteDeletion(id: id.recordName) {
                queue.add(pendingRecordZoneChanges: [.saveRecord(id)])
            }
        }
    }

    /// Applies one server record to the store. A record this version can't read (a field it doesn't understand)
    /// is skipped and left as it is on the server.
    private func applyFetched(_ record: CKRecord) async throws -> Store.RemoteChange? {
        let local = try await store.item(id: record.recordID.recordName)
        let item: Item
        let body: String?
        do {
            item = try mapper.item(from: record, existing: local)
            body = try mapper.body(from: record)
        } catch {
            return nil
        }
        return try await store.applyRemote(item, body: body)
    }

    /// The `Library` zone was deleted on the server. `.purged` and `.deleted` mean the user removed Satchel's data
    /// from iCloud, so the local copy goes too. `.encryptedDataReset` means CloudKit lost the encryption keys, so
    /// the whole library is uploaded again.
    public func handleZoneDeleted(reason: CKDatabase.DatabaseChange.Deletion.Reason, queue: some SyncChangeQueue)
        async throws
    {
        try await store.removeSyncState(keyPrefix: Key.systemFieldsPrefix)
        inFlight.withLock { $0.removeAll() }
        switch reason {
        case .encryptedDataReset:
            queue.add(pendingDatabaseChanges: [.saveZone(CKRecordZone(zoneID: mapper.zoneID))])
            try await store.queueAllForUpload()
            try await enqueueOutbox(into: queue)
        default:
            let owner = try await store.syncState(forKey: Key.account)
            try await store.removeAllData()
            try await store.setSyncState(owner, forKey: Key.account)
        }
    }

    // MARK: System fields

    private func systemFields(for itemID: String) async throws -> CKRecord? {
        guard let data = try await store.syncState(forKey: Key.systemFieldsPrefix + itemID),
            let coder = try? NSKeyedUnarchiver(forReadingFrom: data)
        else { return nil }
        coder.requiresSecureCoding = true
        defer { coder.finishDecoding() }
        return CKRecord(coder: coder)
    }

    private func setSystemFields(of record: CKRecord) async throws {
        let coder = NSKeyedArchiver(requiringSecureCoding: true)
        record.encodeSystemFields(with: coder)
        coder.finishEncoding()
        try await store.setSyncState(coder.encodedData, forKey: Key.systemFieldsPrefix + record.recordID.recordName)
    }
}
