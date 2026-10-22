import CloudKit
import Foundation
import Synchronization
import Testing

@testable import SatchelKit

/// An in-memory `CloudDatabase`: a zone set and a record store, with scripted errors and delays.
final class FakeDatabase: CloudDatabase {
    struct State {
        var zones: Set<CKRecordZone.ID> = []
        var records: [CKRecord.ID: CKRecord] = [:]
        /// Thrown, in order, by the next record saves or deletes before they touch the store.
        var recordErrors: [any Error] = []
        var zoneErrors: [any Error] = []
        var delay: Duration?
        var recordSaves = 0
        var zoneSaves = 0
        var deletes = 0
        var policies: [CKModifyRecordsOperation.RecordSavePolicy] = []
        /// Whether the asset file existed when the record was saved.
        var assetFileExisted: Bool?
    }
    let state: Mutex<State>

    init(zones: Set<CKRecordZone.ID> = [], recordErrors: [any Error] = [], delay: Duration? = nil) {
        state = Mutex(State(zones: zones, recordErrors: recordErrors, delay: delay))
    }

    func saveZone(_ zone: CKRecordZone) async throws {
        try state.withLock { state in
            state.zoneSaves += 1
            if !state.zoneErrors.isEmpty { throw state.zoneErrors.removeFirst() }
            state.zones.insert(zone.zoneID)
        }
    }

    func saveRecord(_ record: CKRecord, savePolicy: CKModifyRecordsOperation.RecordSavePolicy) async throws
        -> CKRecord
    {
        if let delay = state.withLock({ $0.delay }) {
            // Ignores cancellation, like a CloudKit call that's already on the wire.
            let clock = ContinuousClock()
            let end = clock.now.advanced(by: delay)
            while clock.now < end { try? await clock.sleep(for: .milliseconds(10)) }
        }
        return try state.withLock { state in
            state.recordSaves += 1
            state.policies.append(savePolicy)
            if let asset = record["bodyAsset"] as? CKAsset, let url = asset.fileURL {
                state.assetFileExisted = FileManager.default.fileExists(atPath: url.path(percentEncoded: false))
            }
            if !state.recordErrors.isEmpty { throw state.recordErrors.removeFirst() }
            guard state.zones.contains(record.recordID.zoneID) else { throw CKError(.zoneNotFound) }
            state.records[record.recordID] = record
            return record
        }
    }

    func deleteRecord(withID id: CKRecord.ID) async throws {
        try state.withLock { state in
            state.deletes += 1
            if !state.recordErrors.isEmpty { throw state.recordErrors.removeFirst() }
            guard state.zones.contains(id.zoneID) else { throw CKError(.zoneNotFound) }
            guard state.records.removeValue(forKey: id) != nil else { throw CKError(.unknownItem) }
        }
    }
}

let libraryZone = CKRecordZone.ID(zoneName: "Library", ownerName: CKCurrentUserDefaultName)

@Suite struct OneShotSaverTests {
    @Test func savesWithChangedKeysIntoAnExistingZone() async throws {
        let test = TestMapper()
        defer { test.cleanUp() }
        let database = FakeDatabase(zones: [libraryZone])
        let saver = OneShotSaver(database: database, mapper: test.mapper)
        let item = try fixtureItem("page-full.json")

        let record = try await saver.save(item, body: "# Body").get()
        #expect(record.recordID.recordName == item.id)
        #expect(try test.mapper.item(from: record, existing: item) == item)
        database.state.withLock { state in
            #expect(state.recordSaves == 1)
            #expect(state.zoneSaves == 0)  // no extra round trip when the zone exists
            #expect(state.policies == [.changedKeys])
            #expect(state.records[record.recordID] != nil)
        }
    }

    @Test func createsTheZoneWhenMissingAndRetries() async throws {
        let test = TestMapper()
        defer { test.cleanUp() }
        let database = FakeDatabase()
        let saver = OneShotSaver(database: database, mapper: test.mapper)

        _ = try await saver.save(try fixtureItem("link-minimal.json"), body: nil).get()
        database.state.withLock { state in
            #expect(state.zones == [libraryZone])
            #expect(state.zoneSaves == 1)
            #expect(state.recordSaves == 2)
        }
        // The next save finds the zone.
        _ = try await saver.save(try fixtureItem("page-full.json"), body: nil).get()
        database.state.withLock { state in
            #expect(state.zoneSaves == 1)
            #expect(state.recordSaves == 3)
        }
    }

    @Test func toleratesAZoneThatAnotherProcessCreated() async throws {
        let test = TestMapper()
        defer { test.cleanUp() }
        let database = FakeDatabase(recordErrors: [CKError(.zoneNotFound)])
        database.state.withLock { state in
            state.zones = [libraryZone]
            state.zoneErrors = [CKError(.serverRecordChanged)]
        }
        let saver = OneShotSaver(database: database, mapper: test.mapper)
        let result = await saver.save(try fixtureItem("link-minimal.json"), body: nil)
        #expect((try? result.get()) != nil)
    }

    @Test func reportsZoneNotFoundWhenTheRetryStillFails() async throws {
        let test = TestMapper()
        defer { test.cleanUp() }
        let database = FakeDatabase(recordErrors: [CKError(.zoneNotFound), CKError(.zoneNotFound)])
        let saver = OneShotSaver(database: database, mapper: test.mapper)
        let result = await saver.save(try fixtureItem("link-minimal.json"), body: nil)
        #expect(result == .failure(.zoneNotFound))
        database.state.withLock { #expect($0.recordSaves == 2) }  // one retry, not a loop
    }

    @Test func zoneCreationFailureIsReported() async throws {
        let test = TestMapper()
        defer { test.cleanUp() }
        let database = FakeDatabase()
        database.state.withLock { $0.zoneErrors = [CKError(.notAuthenticated)] }
        let saver = OneShotSaver(database: database, mapper: test.mapper)
        let result = await saver.save(try fixtureItem("link-minimal.json"), body: nil)
        #expect(result == .failure(.notAuthenticated))
    }

    static let errorMappings: [(CKError.Code, OneShotFailure)] = [
        (.notAuthenticated, .notAuthenticated),
        (.networkUnavailable, .network),
        (.networkFailure, .network),
        (.serviceUnavailable, .network),
        (.requestRateLimited, .network),
        (.zoneBusy, .network),
        (.serverResponseLost, .network),
        (.quotaExceeded, .quotaExceeded),
        (.userDeletedZone, .zoneNotFound),
        (.serverRecordChanged, .serverRecordChanged(nil)),
    ]

    @Test(arguments: errorMappings)
    func mapsCloudKitErrors(code: CKError.Code, expected: OneShotFailure) async throws {
        let test = TestMapper()
        defer { test.cleanUp() }
        let database = FakeDatabase(zones: [libraryZone], recordErrors: [CKError(code)])
        let saver = OneShotSaver(database: database, mapper: test.mapper)
        #expect(await saver.save(try fixtureItem("link-minimal.json"), body: nil) == .failure(expected))
    }

    @Test func mapsOtherErrors() {
        #expect(OneShotFailure(URLError(.notConnectedToInternet)) == .network)
        #expect(OneShotFailure(CancellationError()) == .other("cancelled"))
        guard case .other(let message) = OneShotFailure(CKError(.permissionFailure)) else {
            Issue.record("expected .other")
            return
        }
        #expect(message.hasPrefix("CKError \(CKError.Code.permissionFailure.rawValue)"))
    }

    @Test func serverRecordChangedCarriesTheServerCopy() throws {
        let server = CKRecord(recordType: "Item", recordID: CKRecord.ID(recordName: "u_x", zoneID: libraryZone))
        let error = CKError(.serverRecordChanged, userInfo: [CKRecordChangedErrorServerRecordKey: server])
        guard case .serverRecordChanged(let record) = OneShotFailure(error) else {
            Issue.record("expected .serverRecordChanged")
            return
        }
        #expect(record === server)
    }

    @Test func unwrapsAPartialFailure() async throws {
        let test = TestMapper()
        defer { test.cleanUp() }
        let item = try fixtureItem("link-minimal.json")
        let partial = CKError(
            .partialFailure,
            userInfo: [CKPartialErrorsByItemIDKey: [test.mapper.recordID(forItemID: item.id): CKError(.quotaExceeded)]]
        )
        #expect(OneShotFailure(partial) == .quotaExceeded)
        // And a wrapped zoneNotFound still triggers zone creation.
        let zonePartial = CKError(
            .partialFailure,
            userInfo: [CKPartialErrorsByItemIDKey: [test.mapper.recordID(forItemID: item.id): CKError(.zoneNotFound)]]
        )
        let database = FakeDatabase(recordErrors: [zonePartial])
        let saver = OneShotSaver(database: database, mapper: test.mapper)
        #expect((try? await saver.save(item, body: nil).get()) != nil)
        database.state.withLock { #expect($0.zoneSaves == 1) }
    }

    @Test func timesOutEvenIfTheCallIgnoresCancellation() async throws {
        let test = TestMapper()
        defer { test.cleanUp() }
        let database = FakeDatabase(zones: [libraryZone], delay: .seconds(5))
        let saver = OneShotSaver(database: database, mapper: test.mapper, timeout: .milliseconds(100))
        let clock = ContinuousClock()
        let start = clock.now
        let result = await saver.save(try fixtureItem("link-minimal.json"), body: nil)
        #expect(result == .failure(.timedOut))
        #expect(clock.now - start < .seconds(2))
    }

    @Test func defaultTimeoutIsEightSeconds() {
        #expect(OneShotSaver.defaultTimeout == .seconds(8))
    }

    @Test func invalidItemsFailWithoutANetworkCall() async throws {
        let test = TestMapper()
        defer { test.cleanUp() }
        let database = FakeDatabase(zones: [libraryZone])
        let saver = OneShotSaver(database: database, mapper: test.mapper)
        var item = try fixtureItem("link-minimal.json")
        item.createdAt = "not a date"
        guard case .failure(.invalidItem) = await saver.save(item, body: nil) else {
            Issue.record("expected .invalidItem")
            return
        }
        database.state.withLock { #expect($0.recordSaves == 0) }
    }

    // MARK: Asset files

    @Test func assetFileLivesUntilTheSaveFinishes() async throws {
        let test = TestMapper()
        defer { test.cleanUp() }
        let database = FakeDatabase(zones: [libraryZone])
        let saver = OneShotSaver(database: database, mapper: test.mapper)
        _ = try await saver.save(try fixtureItem("page-full.json"), body: String(repeating: "a", count: 600_000)).get()
        database.state.withLock { #expect($0.assetFileExisted == true) }
        #expect(test.files().isEmpty)
    }

    @Test func assetFileIsRemovedAfterAFailure() async throws {
        let test = TestMapper()
        defer { test.cleanUp() }
        let database = FakeDatabase(zones: [libraryZone], recordErrors: [CKError(.networkUnavailable)])
        let saver = OneShotSaver(database: database, mapper: test.mapper)
        let result = await saver.save(try fixtureItem("page-full.json"), body: String(repeating: "a", count: 600_000))
        #expect(result == .failure(.network))
        #expect(test.files().isEmpty)
    }

    @Test func assetFileIsKeptAfterATimeout() async throws {
        let test = TestMapper()
        defer { test.cleanUp() }
        let database = FakeDatabase(zones: [libraryZone], delay: .milliseconds(500))
        let saver = OneShotSaver(database: database, mapper: test.mapper, timeout: .milliseconds(50))
        let result = await saver.save(try fixtureItem("page-full.json"), body: String(repeating: "a", count: 600_000))
        #expect(result == .failure(.timedOut))
        // The upload may still be reading it; the next save's sweep removes it once it's stale.
        #expect(test.files().count == 1)
    }

    // MARK: Delete

    @Test func deletesARecord() async throws {
        let test = TestMapper()
        defer { test.cleanUp() }
        let database = FakeDatabase(zones: [libraryZone])
        let saver = OneShotSaver(database: database, mapper: test.mapper)
        let item = try fixtureItem("link-minimal.json")
        _ = try await saver.save(item, body: nil).get()
        try await saver.delete(id: item.id).get()
        database.state.withLock { #expect($0.records.isEmpty) }
    }

    @Test func deletingWhatIsAlreadyGoneSucceeds() async throws {
        let test = TestMapper()
        defer { test.cleanUp() }
        let saver = OneShotSaver(database: FakeDatabase(zones: [libraryZone]), mapper: test.mapper)
        try await saver.delete(id: "u_missing").get()  // unknownItem
        let noZone = OneShotSaver(database: FakeDatabase(), mapper: test.mapper)
        try await noZone.delete(id: "u_missing").get()  // zoneNotFound
    }

    @Test func deleteReportsFailures() async throws {
        let test = TestMapper()
        defer { test.cleanUp() }
        let saver = OneShotSaver(
            database: FakeDatabase(zones: [libraryZone], recordErrors: [CKError(.notAuthenticated)]),
            mapper: test.mapper)
        guard case .failure(let failure) = await saver.delete(id: "u_x") else {
            Issue.record("expected a failure")
            return
        }
        #expect(failure == .notAuthenticated)
    }
}
