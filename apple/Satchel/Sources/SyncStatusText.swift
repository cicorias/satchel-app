import SatchelKit

extension SyncStatus {
    /// What to tell the user about sync: a sentence and an SF Symbol.
    var explanation: (text: String, symbol: String) {
        switch self {
        case .starting:
            ("Connecting to iCloud…", "icloud")
        case .syncing:
            ("Syncing with iCloud…", "arrow.triangle.2.circlepath.icloud")
        case .upToDate:
            ("Your library syncs with iCloud.", "checkmark.icloud")
        case .noAccount:
            ("Sign in to iCloud to sync. Saves are kept on this iPhone until then.", "icloud.slash")
        case .temporarilyUnavailable:
            ("iCloud isn't available right now. Saves will sync later.", "icloud.slash")
        case .otherAccount:
            (
                "This library belongs to a different iCloud account, so sync is paused.",
                "person.crop.circle.badge.exclamationmark"
            )
        case .failed(let reason):
            ("Sync stopped: \(reason)", "exclamationmark.icloud")
        }
    }

    /// Sync is working, or about to be.
    var isHealthy: Bool {
        switch self {
        case .starting, .syncing, .upToDate: true
        default: false
        }
    }
}
