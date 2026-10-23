import Foundation
import SafariServices
import SatchelKit
import os

/// Native side of the Safari Web Extension (spec §9.2.3, ADR-0007). The messages are handled by SatchelKit's
/// `ExtensionMessageHandler`; this only unwraps them and sends the reply. `ping` lets the popup warm this process up
/// before a save: a cold first message took 69 ms on an iPhone and ~1.4 s on the simulator (ADR-0007 addenda).
final class SafariWebExtensionHandler: NSObject, NSExtensionRequestHandling {
    /// Opened on the first message and kept while the process lives.
    private static let handler = Result { ExtensionMessageHandler(saver: try ItemSaver.standard()) }
    private static let log = Logger(subsystem: Bundle.main.bundleIdentifier ?? "satchel", category: "safari")

    func beginRequest(with context: NSExtensionContext) {
        let request = context.inputItems.first as? NSExtensionItem
        let message = request?.userInfo?[SFExtensionMessageKey]
        let pending = Pending(context: context, message: message)
        Task { await Self.answer(pending) }
    }

    private static func answer(_ pending: Pending) async {
        let reply: [String: Any]
        switch handler {
        case .success(let handler):
            Store.resume()
            reply = await handler.reply(toJSONObject: pending.message)
            // Release the shared database's locks before this process is suspended (0xDEAD10CC).
            Store.suspend()
        case .failure(let error):
            log.error("store unavailable: \(error, privacy: .public)")
            reply = ["ok": false, "error": "Satchel's library couldn't be opened: \(error)", "code": "failed"]
        }
        if reply["ok"] as? Bool != true {
            log.notice("reply error=\(reply["error"] as? String ?? "", privacy: .public)")
        }
        let response = NSExtensionItem()
        response.userInfo = [SFExtensionMessageKey: reply]
        pending.context.completeRequest(returningItems: [response])
    }
}

/// The request's context and message, carried into the task that answers it. Safari hands them over on one thread
/// and only this task touches them afterwards.
private struct Pending: @unchecked Sendable {
    let context: NSExtensionContext
    let message: Any?
}
