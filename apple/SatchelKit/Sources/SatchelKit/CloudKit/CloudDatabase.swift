import CloudKit
import Foundation

/// The CloudKit calls `OneShotSaver` makes, behind a protocol so tests can use a fake. Each method throws the
/// `CKError` for its one zone or record, not a `partialFailure` wrapper.
public protocol CloudDatabase: Sendable {
    /// Creates `zone`, or does nothing if it exists.
    func saveZone(_ zone: CKRecordZone) async throws
    /// Saves one record and returns the server's copy.
    func saveRecord(_ record: CKRecord, savePolicy: CKModifyRecordsOperation.RecordSavePolicy) async throws -> CKRecord
    func deleteRecord(withID id: CKRecord.ID) async throws
}

/// `CloudDatabase` over a real `CKDatabase`, normally the private database of the app's container.
public struct CloudKitDatabase: CloudDatabase {
    public let database: CKDatabase

    public init(_ database: CKDatabase) {
        self.database = database
    }

    /// The private database of `containerIdentifier` (`AppEnvironment.iCloudContainer`). The calling target needs the
    /// iCloud (CloudKit) entitlement for that container.
    public init(containerIdentifier: String) {
        self.init(CKContainer(identifier: containerIdentifier).privateCloudDatabase)
    }

    public func saveZone(_ zone: CKRecordZone) async throws {
        let (saved, _) = try await configured { try await $0.modifyRecordZones(saving: [zone], deleting: []) }
        guard let result = saved[zone.zoneID] else { throw CKError(.internalError) }
        _ = try result.get()
    }

    public func saveRecord(_ record: CKRecord, savePolicy: CKModifyRecordsOperation.RecordSavePolicy) async throws
        -> CKRecord
    {
        let (saved, _) = try await configured {
            try await $0.modifyRecords(saving: [record], deleting: [], savePolicy: savePolicy)
        }
        guard let result = saved[record.recordID] else { throw CKError(.internalError) }
        return try result.get()
    }

    public func deleteRecord(withID id: CKRecord.ID) async throws {
        let (_, deleted) = try await configured { try await $0.modifyRecords(saving: [], deleting: [id]) }
        guard let result = deleted[id] else { throw CKError(.internalError) }
        try result.get()
    }

    /// Runs `body` with user-initiated priority: the user is waiting on a share sheet or popup.
    private func configured<R: Sendable>(_ body: @Sendable (CKDatabase) async throws -> R) async throws -> R {
        let configuration = CKOperation.Configuration()
        configuration.qualityOfService = .userInitiated
        return try await database.configuredWith(configuration: configuration, body: body)
    }
}
