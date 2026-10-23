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
    let openError: String?
    /// `<bundle ID>.sync`, listed in Info.plist's `BGTaskSchedulerPermittedIdentifiers`.
    let refreshTaskID: String
    /// Settings shared with the extensions through the App Group (the toggles arrive in ticket 12).
    let settings: UserDefaults

    private let log = Logger(subsystem: "com.cedarlogic.satchel", category: "app")

    private init() {
        refreshTaskID = "\(Bundle.main.bundleIdentifier ?? "com.cedarlogic.satchel").sync"
        let environment = try? AppEnvironment.current()
        settings = environment.flatMap { UserDefaults(suiteName: $0.appGroup) } ?? .standard
        do {
            let environment = try AppEnvironment.current()
            let model = try SatchelModel.bundled()
            let store = try Store(environment: environment, merge: model.itemMerge)
            self.store = store
            self.model = model
            sync = LibrarySync(store: store, environment: environment)
            openError = nil
        } catch {
            store = nil
            model = nil
            sync = nil
            openError = "The library couldn't be opened: \(error)"
        }
    }

    /// "Load remote images" (spec §11). Off unless the user turns it on.
    var loadsRemoteImages: Bool { settings.bool(forKey: "loadRemoteImages") }

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
