import SatchelKit
import SwiftUI

@main
struct SatchelApp: App {
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            LibraryView()
        }
        .onChange(of: scenePhase) { _, phase in
            // Release locks on the shared database before suspension, or iOS kills the app (0xDEAD10CC).
            if phase == .background { Store.suspend() } else if phase == .active { Store.resume() }
        }
    }
}
