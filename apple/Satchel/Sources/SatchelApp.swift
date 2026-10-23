import SatchelKit
import SwiftUI
import UIKit

@main
struct SatchelApp: App {
    @UIApplicationDelegateAdaptor private var appDelegate: AppDelegate
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            LibraryView()
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active:
                Store.resume()
                Task { await AppServices.shared.sync?.syncNow() }
            case .background:
                AppServices.shared.scheduleRefresh()
                // Release locks on the shared database before suspension, or iOS kills the app (0xDEAD10CC).
                Store.suspend()
            default:
                break
            }
        }
        .backgroundTask(.appRefresh(AppServices.shared.refreshTaskID)) {
            await MainActor.run { AppServices.shared.scheduleRefresh() }
            Store.resume()
            await AppServices.shared.sync?.syncNow()
            Store.suspend()
        }
    }
}

/// Starts sync at launch and passes CloudKit pushes to it.
final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        // CKSyncEngine subscribes to the zone's changes; the pushes need this registration.
        application.registerForRemoteNotifications()
        Task { await AppServices.shared.sync?.start() }
        return true
    }

    func application(_ application: UIApplication, didReceiveRemoteNotification userInfo: [AnyHashable: Any]) async
        -> UIBackgroundFetchResult
    {
        guard let sync = AppServices.shared.sync else { return .noData }
        await sync.fetchChanges()
        return .newData
    }
}
