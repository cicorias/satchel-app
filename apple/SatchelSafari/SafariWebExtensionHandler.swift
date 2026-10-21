import Foundation
import SafariServices
import os

/// Native side of the Safari Web Extension (spec §9.2.3, ADR-0007).
/// Phase 3 adds `save`, `status`, and `tags`. `ping` exists so the extension can warm up this process
/// before a save: the first native message after a cold start costs ~1.4 s (ADR-0007 addendum).
final class SafariWebExtensionHandler: NSObject, NSExtensionRequestHandling {
    private let log = Logger(subsystem: Bundle.main.bundleIdentifier ?? "satchel", category: "safari")

    func beginRequest(with context: NSExtensionContext) {
        let request = context.inputItems.first as? NSExtensionItem
        let message = request?.userInfo?[SFExtensionMessageKey] as? [String: Any]
        let type = message?["type"] as? String ?? "unknown"

        let reply: [String: Any]
        switch type {
        case "ping":
            reply = ["ok": true, "pong": true]
        default:
            log.notice("unhandled native message type=\(type, privacy: .public)")
            reply = ["ok": false, "error": "unknown message type"]
        }

        let response = NSExtensionItem()
        response.userInfo = [SFExtensionMessageKey: reply]
        context.completeRequest(returningItems: [response])
    }
}
