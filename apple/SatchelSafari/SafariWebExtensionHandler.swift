import Foundation
import SafariServices
import os

/// Native side of the Safari Web Extension (spec §9.2.3, ADR-0007).
/// Phase 3 handles `save`, `begin`/`chunk`/`commit`, `status`, and `tags`; for now it echoes.
final class SafariWebExtensionHandler: NSObject, NSExtensionRequestHandling {
    private let log = Logger(subsystem: Bundle.main.bundleIdentifier ?? "satchel", category: "safari")

    func beginRequest(with context: NSExtensionContext) {
        let request = context.inputItems.first as? NSExtensionItem
        let message = request?.userInfo?[SFExtensionMessageKey]
        log.debug("received native message")

        let response = NSExtensionItem()
        response.userInfo = [SFExtensionMessageKey: ["echo": message ?? NSNull()]]
        context.completeRequest(returningItems: [response])
    }
}
