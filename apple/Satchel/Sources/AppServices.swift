import BackgroundTasks
import Foundation
import SatchelKit
import os

/// The app's one `Store` and its sync (spec §9.2.4), opened at launch and shared by every view.
@MainActor
final class AppServices {
    static let shared = AppServices()

    let store: Store?
    let model: SatchelModel?
    let sync: LibrarySync?
    /// Fills in links shared from other apps (spec §9.2.4).
    let enricher: Enricher?
    let openError: String?
    /// `<bundle ID>.sync`, listed in Info.plist's `BGTaskSchedulerPermittedIdentifiers`.
    let refreshTaskID: String
    /// Settings shared with the extensions through the App Group.
    let settings: UserDefaults

    private let log = Logger(subsystem: "com.cedarlogic.satchel", category: "app")

    private init() {
        refreshTaskID = "\(Bundle.main.bundleIdentifier ?? "com.cedarlogic.satchel").sync"
        let environment = try? AppEnvironment.current()
        settings = environment.flatMap { UserDefaults(suiteName: $0.appGroup) } ?? .standard
        // Spec §11: on by default in development builds; the store default is decided in Phase 7.
        #if DEBUG
            settings.register(defaults: [Self.remoteImagesKey: true])
            if ProcessInfo.processInfo.arguments.contains("-SatchelResetOnboarding") {
                settings.removeObject(forKey: Self.onboardingKey)
            }
        #endif
        do {
            let environment = try AppEnvironment.current()
            let model = try SatchelModel.bundled()
            let store = try Store(environment: environment, merge: model.itemMerge)
            self.store = store
            self.model = model
            sync = LibrarySync(store: store, environment: environment)
            enricher = WebMetadataLoader.bundled().map {
                Enricher(store: store, loader: $0, network: NetworkPath())
            }
            openError = nil
        } catch {
            store = nil
            model = nil
            sync = nil
            enricher = nil
            openError = "The library couldn't be opened: \(error)"
        }
    }

    static let remoteImagesKey = "loadRemoteImages"
    static let onboardingKey = "onboardingDone"

    /// "Load remote images" (spec §11): off in store builds, on in Debug builds. UI tests turn it off with
    /// `-SatchelRemoteImagesOff`.
    var loadsRemoteImages: Bool {
        get {
            #if DEBUG
                if ProcessInfo.processInfo.arguments.contains("-SatchelRemoteImagesOff") { return false }
            #endif
            return settings.bool(forKey: Self.remoteImagesKey)
        }
        set { settings.set(newValue, forKey: Self.remoteImagesKey) }
    }

    /// The first-run page hasn't been dismissed yet. UI tests skip it with `-SatchelOnboardingDone` and bring it back
    /// with `-SatchelResetOnboarding`.
    var needsOnboarding: Bool {
        #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("-SatchelOnboardingDone") { return false }
        #endif
        return !settings.bool(forKey: Self.onboardingKey)
    }

    func finishOnboarding() {
        settings.set(true, forKey: Self.onboardingKey)
    }

    /// Syncs, then enriches pending links, off the main actor (on foreground and from background refresh).
    nonisolated func syncAndEnrich() async {
        let (sync, enricher) = await MainActor.run { (self.sync, self.enricher) }
        await sync?.syncNow()
        if let enricher {
            await Task.detached(priority: .utility) { await enricher.run() }.value
        }
    }

    /// Asks for a background refresh in about 15 minutes; iOS decides when it actually runs.
    func scheduleRefresh() {
        let request = BGAppRefreshTaskRequest(identifier: refreshTaskID)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 15 * 60)
        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            // Unavailable in the simulator and when Background App Refresh is off.
            log.info("background refresh not scheduled: \(error, privacy: .public)")
        }
    }
}
