import CloudKit
import Foundation
import Synchronization
import os

/// Where the host app's sync stands, for the library and settings (ticket 12).
public enum SyncStatus: Sendable, Equatable {
    case starting
    case syncing
    case upToDate
    /// No iCloud account, or iCloud is restricted. Saves stay in the outbox until one signs in.
    case noAccount
    /// iCloud is signed in but not ready yet (for example, terms to accept). Saves stay in the outbox.
    case temporarilyUnavailable
    /// The library belongs to a different iCloud account. Sync stays paused so the two accounts' data never mix;
    /// `LibrarySync.startOver()` erases this device's library and syncs the current account instead.
    case otherAccount
    case failed(String)
}

/// The host app's sync (spec §9.2.4): CKSyncEngine against the `Library` zone of the private database. Only the host
/// app runs this; the extensions save with `OneShotSaver` (§9.2.3).
///
/// Call `start()` at launch, `syncNow()` on foreground and from the background refresh task, and `fetchChanges()`
/// when a CloudKit push arrives. While the engine runs, every change to the outbox (including saves from the
/// extensions) is queued for sending.
public final class LibrarySync: CKSyncEngineDelegate, Sendable {
    private struct State {
        var engine: CKSyncEngine?
        var status = SyncStatus.starting
        var observers: [UUID: AsyncStream<SyncStatus>.Continuation] = [:]
        var outboxTask: Task<Void, Never>?
        var accountTask: Task<Void, Never>?
    }

    public let coordinator: SyncCoordinator
    private let containerIdentifier: String
    private let state = Mutex(State())
    private let log = Logger(subsystem: "com.cedarlogic.satchel", category: "sync")

    public init(store: Store, environment: AppEnvironment) {
        coordinator = SyncCoordinator(store: store, mapper: ItemRecordMapper(environment: environment))
        containerIdentifier = environment.iCloudContainer
    }

    deinit {
        state.withLock { state in
            state.outboxTask?.cancel()
            state.accountTask?.cancel()
            for observer in state.observers.values { observer.finish() }
        }
    }

    private var container: CKContainer { CKContainer(identifier: containerIdentifier) }

    // MARK: Status

    public var status: SyncStatus { state.withLock { $0.status } }

    /// The current status, then every change.
    public func statusUpdates() -> AsyncStream<SyncStatus> {
        let id = UUID()
        let (stream, continuation) = AsyncStream<SyncStatus>.makeStream(bufferingPolicy: .bufferingNewest(1))
        continuation.onTermination = { [weak self] _ in
            self?.state.withLock { _ = $0.observers.removeValue(forKey: id) }
        }
        state.withLock { state in
            state.observers[id] = continuation
            continuation.yield(state.status)
        }
        return stream
    }

    private func setStatus(_ status: SyncStatus) {
        state.withLock { state in
            guard state.status != status else { return }
            state.status = status
            for observer in state.observers.values { observer.yield(status) }
        }
    }

    // MARK: Lifecycle

    /// Checks the iCloud account and starts the engine if this library may sync with it. Safe to call again; it also
    /// runs by itself when the iCloud account changes while the engine is stopped.
    public func start() async {
        observeAccountChanges()
        guard state.withLock({ $0.engine }) == nil else { return }
        setStatus(.starting)
        do {
            switch try await container.accountStatus() {
            case .available: break
            case .noAccount, .restricted: return setStatus(.noAccount)
            case .temporarilyUnavailable: return setStatus(.temporarilyUnavailable)
            case .couldNotDetermine: return setStatus(.failed("iCloud account status unknown"))
            @unknown default: return setStatus(.failed("iCloud account status unknown"))
            }
            let user = try await container.userRecordID()
            if try await coordinator.checkAccount(userRecordName: user.recordName) == .different {
                return setStatus(.otherAccount)
            }
            try await startEngine()
        } catch {
            log.error("start failed: \(error, privacy: .public)")
            setStatus(.failed(OneShotFailure(error).description))
        }
    }

    /// Fetches remote changes and sends local ones now: on foreground and from the background refresh task.
    public func syncNow() async {
        guard let engine = await engineStartingIfNeeded() else { return }
        do {
            try await coordinator.enqueueOutbox(into: engine.state)
            try await engine.fetchChanges()
            try await engine.sendChanges()
        } catch {
            log.error("sync failed: \(error, privacy: .public)")
        }
    }

    /// Fetches remote changes: when a CloudKit push arrives.
    public func fetchChanges() async {
        guard let engine = await engineStartingIfNeeded() else { return }
        do {
            try await engine.fetchChanges()
        } catch {
            log.error("fetch failed: \(error, privacy: .public)")
        }
    }

    /// Erases this device's library, outbox, and sync state, then syncs with the iCloud account now signed in. For a
    /// library that belongs to another account (`SyncStatus.otherAccount`); unsent saves are lost.
    public func startOver() async throws {
        stopEngine()
        try await coordinator.store.removeAllData()
        await start()
    }

    private func engineStartingIfNeeded() async -> CKSyncEngine? {
        if let engine = state.withLock({ $0.engine }) { return engine }
        await start()
        return state.withLock { $0.engine }
    }

    private func startEngine() async throws {
        let saved = try await coordinator.engineState()
        var configuration = CKSyncEngine.Configuration(
            database: container.privateCloudDatabase, stateSerialization: saved, delegate: self)
        configuration.automaticallySync = true
        let engine = CKSyncEngine(configuration)
        let started = state.withLock { state -> Bool in
            guard state.engine == nil else { return false }
            state.engine = engine
            return true
        }
        guard started else { return }
        if saved == nil {
            // First run against this account: make sure the zone exists before the first save.
            engine.state.add(pendingDatabaseChanges: [.saveZone(CKRecordZone(zoneID: coordinator.mapper.zoneID))])
        }
        try await coordinator.enqueueOutbox(into: engine.state)
        observeOutbox(engine)
        setStatus(.upToDate)
    }

    private func stopEngine() {
        state.withLock { state in
            state.engine = nil
            state.outboxTask?.cancel()
            state.outboxTask = nil
        }
    }

    /// Queues every outbox change while the engine runs, so saves from the extensions are sent without a relaunch.
    private func observeOutbox(_ engine: CKSyncEngine) {
        let coordinator = self.coordinator
        let log = self.log
        let task = Task {
            do {
                for try await _ in coordinator.store.observeUnsentOutbox() {
                    try await coordinator.enqueueOutbox(into: engine.state)
                }
            } catch {
                log.error("outbox observation ended: \(error, privacy: .public)")
            }
        }
        state.withLock { state in
            state.outboxTask?.cancel()
            state.outboxTask = task
        }
    }

    /// Restarts when the iCloud account changes while the engine is stopped (for example, after signing in).
    private func observeAccountChanges() {
        let task = Task { [weak self] in
            for await _ in NotificationCenter.default.notifications(named: .CKAccountChanged) {
                guard let self else { return }
                if self.state.withLock({ $0.engine }) == nil { await self.start() }
            }
        }
        let replaced = state.withLock { state -> Bool in
            guard state.accountTask == nil else { return false }
            state.accountTask = task
            return true
        }
        if !replaced { task.cancel() }
    }

    // MARK: CKSyncEngineDelegate

    public func handleEvent(_ event: CKSyncEngine.Event, syncEngine: CKSyncEngine) async {
        do {
            switch event {
            case .stateUpdate(let update):
                try await coordinator.saveEngineState(update.stateSerialization)
            case .accountChange(let change):
                try await handleAccountChange(change.changeType)
            case .fetchedDatabaseChanges(let changes):
                for deletion in changes.deletions where deletion.zoneID == coordinator.mapper.zoneID {
                    try await coordinator.handleZoneDeleted(reason: deletion.reason, queue: syncEngine.state)
                }
            case .fetchedRecordZoneChanges(let changes):
                try await coordinator.handleFetched(
                    modifications: changes.modifications.map(\.record), deletions: changes.deletions.map(\.recordID),
                    queue: syncEngine.state)
            case .sentRecordZoneChanges(let sent):
                try await coordinator.handleSent(
                    saved: sent.savedRecords,
                    failedSaves: sent.failedRecordSaves.map { .init(record: $0.record, error: $0.error) },
                    deleted: sent.deletedRecordIDs, failedDeletes: sent.failedRecordDeletes, queue: syncEngine.state)
            case .sentDatabaseChanges(let sent):
                for failure in sent.failedZoneSaves {
                    log.error("zone save failed: \(failure.error, privacy: .public)")
                }
            case .willFetchChanges, .willSendChanges:
                setStatus(.syncing)
            case .didFetchChanges, .didSendChanges:
                setStatus(.upToDate)
            case .willFetchRecordZoneChanges, .didFetchRecordZoneChanges:
                break
            @unknown default:
                break
            }
        } catch {
            log.error("handling \(String(describing: event), privacy: .public) failed: \(error, privacy: .public)")
            setStatus(.failed(String(describing: error)))
        }
    }

    public func nextRecordZoneChangeBatch(_ context: CKSyncEngine.SendChangesContext, syncEngine: CKSyncEngine) async
        -> CKSyncEngine.RecordZoneChangeBatch?
    {
        let scope = context.options.scope
        let changes = syncEngine.state.pendingRecordZoneChanges.filter { scope.contains($0) }
        let coordinator = self.coordinator
        let queue = syncEngine.state
        return await CKSyncEngine.RecordZoneChangeBatch(pendingChanges: changes) { id in
            await coordinator.record(for: id, queue: queue)
        }
    }

    private func handleAccountChange(_ change: CKSyncEngine.Event.AccountChange.ChangeType) async throws {
        switch change {
        case .signIn(let user):
            if try await coordinator.checkAccount(userRecordName: user.recordName) == .different {
                stopEngine()
                setStatus(.otherAccount)
            }
        case .signOut:
            // Keep the library and the outbox; drop what belonged to the server session.
            stopEngine()
            try await coordinator.forgetServerState()
            setStatus(.noAccount)
        case .switchAccounts:
            stopEngine()
            try await coordinator.forgetServerState()
            setStatus(.otherAccount)
        @unknown default:
            break
        }
    }
}
