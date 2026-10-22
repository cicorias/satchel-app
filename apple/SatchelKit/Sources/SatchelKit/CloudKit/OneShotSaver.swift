import CloudKit
import Foundation
import Synchronization

/// Saves or deletes one item in CloudKit from an extension (spec §9.2.2–9.2.3).
///
/// The caller writes the outbox row first, then calls this and marks the row from the result: `sent` on success,
/// otherwise left for the host app, whose CKSyncEngine drains the outbox. This type never runs CKSyncEngine, so an
/// extension never competes with the host app's sync state.
///
/// - **Zone:** the save goes straight to the `Library` zone. Only if CloudKit answers `zoneNotFound` does the saver
///   create the zone (an existing zone isn't an error) and retry once, so the usual save is a single round trip.
/// - **Policy:** `.changedKeys`, so only the fields the mapper set are written, and there's no change-tag conflict.
/// - **Time:** the whole call, zone creation and retry included, gives up after `timeout` and reports `timedOut`.
///   CloudKit may still finish that save in the background; the host app's retry of the same record is harmless.
public struct OneShotSaver: Sendable {
    /// Extensions get a few seconds at most, and the user is watching a confirmation.
    public static let defaultTimeout: Duration = .seconds(8)
    /// Asset files older than this are swept before each save (see `ItemRecordMapper.removeAssetFiles(olderThan:)`).
    public static let staleAssetAge: TimeInterval = 60 * 60

    public let database: any CloudDatabase
    public let mapper: ItemRecordMapper
    public let timeout: Duration

    public init(database: any CloudDatabase, mapper: ItemRecordMapper, timeout: Duration = Self.defaultTimeout) {
        self.database = database
        self.mapper = mapper
        self.timeout = timeout
    }

    /// The real saver: the private database of `environment.iCloudContainer`, zone `environment.cloudKitZone`.
    public init(environment: AppEnvironment, timeout: Duration = Self.defaultTimeout) {
        self.init(
            database: CloudKitDatabase(containerIdentifier: environment.iCloudContainer),
            mapper: ItemRecordMapper(environment: environment), timeout: timeout)
    }

    /// Saves `item`, and `body` if given (nil leaves the stored body as it is). Returns the server's record.
    public func save(_ item: Item, body: String?) async -> Result<CKRecord, OneShotFailure> {
        mapper.removeAssetFiles(olderThan: Self.staleAssetAge)
        let record: CKRecord
        do {
            record = try mapper.record(for: item, body: body)
        } catch {
            return .failure(.invalidItem(String(describing: error)))
        }
        let result = await withDeadline(timeout) { [database, mapper] () async -> Result<CKRecord, OneShotFailure> in
            do {
                return .success(try await Self.save(record, to: database, zoneID: mapper.zoneID))
            } catch {
                return .failure(OneShotFailure(error))
            }
        }
        // A timed-out save may still be uploading the asset, so its file is left for the next sweep.
        if result != .failure(.timedOut) { mapper.removeAssetFile(of: record) }
        return result
    }

    /// Deletes the record for item `id`. A record or zone that's already gone counts as success.
    public func delete(id: String) async -> Result<Void, OneShotFailure> {
        let recordID = mapper.recordID(forItemID: id)
        return await withDeadline(timeout) { [database] () async -> Result<Void, OneShotFailure> in
            do {
                try await database.deleteRecord(withID: recordID)
                return .success(())
            } catch {
                switch OneShotFailure.code(of: error) {
                case .unknownItem?, .zoneNotFound?: return .success(())
                default: return .failure(OneShotFailure(error))
                }
            }
        }
    }

    private static func save(_ record: CKRecord, to database: any CloudDatabase, zoneID: CKRecordZone.ID)
        async throws -> CKRecord
    {
        do {
            return try await database.saveRecord(record, savePolicy: .changedKeys)
        } catch  where OneShotFailure.code(of: error) == .zoneNotFound {
            do {
                try await database.saveZone(CKRecordZone(zoneID: zoneID))
            } catch  where OneShotFailure.code(of: error) == .serverRecordChanged {
                // Another process created it first.
            }
            return try await database.saveRecord(record, savePolicy: .changedKeys)
        }
    }
}

/// Why a one-shot save or delete failed, from the `CKError` code, so the caller can mark the outbox row.
public enum OneShotFailure: Error, Equatable, Sendable, CustomStringConvertible {
    /// No iCloud account, or iCloud Drive / CloudKit is off for the app.
    case notAuthenticated
    /// Offline, a dropped connection, or CloudKit asking to retry later (unavailable, rate-limited, zone busy).
    case network
    /// The user's iCloud storage is full.
    case quotaExceeded
    /// The server has a newer version; it carries the server copy when CloudKit sent one. `.changedKeys` saves don't
    /// normally see this.
    case serverRecordChanged(CKRecord?)
    /// The zone is missing even after creating it, or the user deleted it (`userDeletedZone`); the host app decides.
    case zoneNotFound
    /// The call didn't finish within the saver's timeout.
    case timedOut
    /// The item couldn't be mapped to a record (for example, a timestamp that isn't ISO 8601). Retrying won't help.
    case invalidItem(String)
    /// Anything else, described for the outbox row's last error.
    case other(String)

    public init(_ error: any Error) {
        guard let ckError = Self.ckError(error) else {
            if error is URLError {
                self = .network
            } else if error is CancellationError {
                self = .other("cancelled")
            } else {
                self = .other(String(describing: error))
            }
            return
        }
        switch ckError.code {
        case .notAuthenticated:
            self = .notAuthenticated
        case .networkUnavailable, .networkFailure, .serviceUnavailable, .requestRateLimited, .zoneBusy,
            .serverResponseLost:
            self = .network
        case .quotaExceeded:
            self = .quotaExceeded
        case .serverRecordChanged:
            self = .serverRecordChanged(ckError.serverRecord)
        case .zoneNotFound, .userDeletedZone:
            self = .zoneNotFound
        default:
            self = .other("CKError \(ckError.code.rawValue): \(ckError.localizedDescription)")
        }
    }

    public var description: String {
        switch self {
        case .notAuthenticated: "not signed in to iCloud"
        case .network: "network unavailable"
        case .quotaExceeded: "iCloud storage full"
        case .serverRecordChanged: "server record changed"
        case .zoneNotFound: "zone not found"
        case .timedOut: "timed out"
        case .invalidItem(let reason): "invalid item: \(reason)"
        case .other(let reason): reason
        }
    }

    /// The error's `CKError` code, looking inside a `partialFailure` that wraps a single item's error.
    static func code(of error: any Error) -> CKError.Code? {
        ckError(error)?.code
    }

    private static func ckError(_ error: any Error) -> CKError? {
        guard let ckError = error as? CKError else { return nil }
        if ckError.code == .partialFailure, let inner = ckError.partialErrorsByItemID?.values.first as? CKError {
            return inner
        }
        return ckError
    }
}

// MARK: Deadline

/// Runs `operation`, returning `.failure(.timedOut)` if it takes longer than `timeout`. It returns on time even when
/// the operation ignores cancellation (a task group would wait for it); the operation is cancelled and left to finish.
func withDeadline<Success: Sendable>(
    _ timeout: Duration, _ operation: @escaping @Sendable () async -> Result<Success, OneShotFailure>
) async -> Result<Success, OneShotFailure> {
    let race = Race<Result<Success, OneShotFailure>>()
    return await withTaskCancellationHandler {
        await withCheckedContinuation { continuation in
            race.start(continuation)
            race.add(Task { race.finish(await operation()) })
            race.add(
                Task {
                    guard (try? await Task.sleep(for: timeout)) != nil else { return }
                    race.finish(.failure(.timedOut))
                })
        }
    } onCancel: {
        race.finish(.failure(.other("cancelled")))
    }
}

/// The first `finish` wins: it resumes the continuation and cancels every task in the race.
private final class Race<Value: Sendable>: Sendable {
    private struct State {
        var continuation: CheckedContinuation<Value, Never>?
        var result: Value?
        var tasks: [Task<Void, Never>] = []
    }
    private let state = Mutex(State())

    func start(_ continuation: CheckedContinuation<Value, Never>) {
        let finished: Value? = state.withLock { state in
            if let result = state.result { return result }
            state.continuation = continuation
            return nil
        }
        if let finished { continuation.resume(returning: finished) }
    }

    func add(_ task: Task<Void, Never>) {
        let finished = state.withLock { state in
            if state.result != nil { return true }
            state.tasks.append(task)
            return false
        }
        if finished { task.cancel() }
    }

    func finish(_ value: Value) {
        let taken: (CheckedContinuation<Value, Never>?, [Task<Void, Never>])? = state.withLock { state in
            guard state.result == nil else { return nil }
            state.result = value
            defer {
                state.continuation = nil
                state.tasks = []
            }
            return (state.continuation, state.tasks)
        }
        guard let taken else { return }
        let (continuation, tasks) = taken
        continuation?.resume(returning: value)
        for task in tasks { task.cancel() }
    }
}
