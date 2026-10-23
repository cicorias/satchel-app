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
        let item = context.inputItems.first as? NSExtensionItem
        // Only Sendable values cross into the task: the message as JSON data, and the context in a box.
        let message = ExtensionMessageHandler.json(item?.userInfo?[SFExtensionMessageKey])
        Self.start(message, Request(context: context))
    }

    /// Starts the task outside `beginRequest`, so its closure captures only Sendable values. (Xcode 26.6's
    /// region-based isolation checker crashes on a task created next to the non-Sendable context.)
    private static func start(_ message: Data?, _ request: Request) {
        Task { await answer(message, request) }
    }

    private static func answer(_ message: Data?, _ request: Request) async {
        let reply: [String: Any]
        switch handler {
        case .success(let handler):
            Store.resume()
            reply = await handler.reply(toJSON: message)
            // Release the shared database's locks before this process is suspended (0xDEAD10CC).
            Store.suspend()
        case .failure(let error):
            log.error("store unavailable: \(error, privacy: .public)")
            reply = ["ok": false, "error": "Satchel's library couldn't be opened: \(error)", "code": "failed"]
        }
        if reply["ok"] as? Bool != true {
            log.notice("reply error=\(reply["error"] as? String ?? "", privacy: .public)")
        }
        request.complete(with: reply)
    }
}

/// The request's context, carried into the task that answers it. Only that task touches it after `beginRequest`.
private final class Request: @unchecked Sendable {
    private let context: NSExtensionContext

    init(context: NSExtensionContext) {
        self.context = context
    }

    func complete(with reply: [String: Any]) {
        let response = NSExtensionItem()
        response.userInfo = [SFExtensionMessageKey: reply]
        context.completeRequest(returningItems: [response])
    }
}
