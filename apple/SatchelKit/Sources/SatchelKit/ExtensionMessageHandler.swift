import Foundation

/// The messages the Safari Web Extension sends to its native handler (spec §9.2.3, ADR-0007), apart from the
/// extension target so they can be unit-tested. `SafariWebExtensionHandler` passes each message's JSON object in and
/// returns the reply's.
///
/// | `type` | Request | Reply |
/// |---|---|---|
/// | `ping` | — | `pong` (warms the process up before a save) |
/// | `save` | `item`, `body` (pages), `existingPage`: `ask` (default), `replace`, or `keep` | the saved `item` and `synced`, or `confirm: "replace"` |
/// | `tags` | `prefix`, `limit` | `tags`, most used first |
/// | `status` | `url` | `saved`, and the saved item's `kind` |
///
/// Every reply has `ok`; a failed one has `error` (for the user) and `code`.
public struct ExtensionMessageHandler: Sendable {
    /// A page's Markdown may be at most 10 MB of UTF-8 (spec §4.4).
    public static let maxBodyBytes = 10 * 1024 * 1024

    public let saver: ItemSaver

    public init(saver: ItemSaver) {
        self.saver = saver
    }

    /// What to do when a page is saved over a saved page (FR-6).
    public enum ExistingPage: String, Codable, Sendable {
        /// Don't save; reply `confirm: "replace"` so the popup can ask "Replace saved copy?".
        case ask
        case replace
        /// Keep the saved copy's body; still apply the new tags, note, and metadata.
        case keep
    }

    public struct Request: Codable, Sendable {
        public var type: String
        public var item: Item?
        public var body: String?
        public var existingPage: ExistingPage?
        public var prefix: String?
        public var limit: Int?
        public var url: String?
    }

    public struct Reply: Codable, Sendable, Equatable {
        public enum Code: String, Codable, Sendable {
            /// The message is malformed or the item is inconsistent.
            case invalid
            case tooLarge = "too-large"
            /// The local store couldn't be written.
            case failed
            case unknownType = "unknown-type"
        }

        public var ok: Bool
        public var pong: Bool?
        public var item: Item?
        /// The save reached CloudKit; `false` means it waits in the outbox for the app (`syncError` says why).
        public var synced: Bool?
        public var syncError: String?
        public var confirm: String?
        public var tags: [String]?
        public var saved: Bool?
        public var kind: ItemKind?
        public var error: String?
        public var code: Code?

        static func failure(_ code: Code, _ error: String) -> Reply {
            Reply(ok: false, error: error, code: code)
        }
    }

    /// The reply to a message given as a JSON object (`[String: Any]` from Safari).
    public func reply(toJSONObject message: Any?) async -> [String: Any] {
        let reply: Reply
        if let message, JSONSerialization.isValidJSONObject(message),
            let data = try? JSONSerialization.data(withJSONObject: message),
            let request = try? JSONDecoder().decode(Request.self, from: data)
        {
            reply = await self.reply(to: request)
        } else {
            reply = .failure(.invalid, "The message isn't valid.")
        }
        guard let data = try? JSONEncoder().encode(reply),
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return ["ok": false, "error": "The reply couldn't be encoded.", "code": "failed"] }
        return object
    }

    public func reply(to request: Request) async -> Reply {
        switch request.type {
        case "ping":
            return Reply(ok: true, pong: true)
        case "save":
            return await save(request)
        case "tags":
            do {
                let tags = try await saver.store.tags(prefix: request.prefix, limit: min(request.limit ?? 20, 100))
                return Reply(ok: true, tags: tags)
            } catch {
                return .failure(.failed, "Tags couldn't be read: \(error)")
            }
        case "status":
            return await status(request.url)
        default:
            return .failure(.unknownType, "Unknown message type “\(request.type)”.")
        }
    }

    private func save(_ request: Request) async -> Reply {
        guard var item = request.item else { return .failure(.invalid, "The save has no item.") }
        var body = request.body
        if let problem = validate(item, body: body) { return problem }
        do {
            if item.kind == .page, let stored = try await saver.store.item(id: item.id), stored.kind == .page {
                switch request.existingPage ?? .ask {
                case .ask:
                    if try saver.model.merge(stored, item).replacesBody { return Reply(ok: false, confirm: "replace") }
                case .replace:
                    break
                case .keep:
                    item.page = stored.page
                    item.capturedAt = stored.capturedAt
                    item.selection = stored.selection
                    body = nil
                }
            }
            let outcome = try await saver.save(item, body: body)
            switch outcome.cloud {
            case .saved:
                return Reply(ok: true, item: outcome.item, synced: true)
            case .queued(let failure):
                return Reply(ok: true, item: outcome.item, synced: false, syncError: failure.description)
            }
        } catch {
            return .failure(.failed, "Couldn't save: \(error)")
        }
    }

    /// Checks that the item is what `itemFromCapture` builds: a web URL whose ID matches, and a body exactly when
    /// it's a page, within the size limit.
    private func validate(_ item: Item, body: String?) -> Reply? {
        let normalized: String
        do {
            normalized = try saver.model.normalizedURL(pageURL: item.url, canonicalURL: item.canonicalURL)
        } catch {
            return .failure(.invalid, "Only web pages (http and https) can be saved.")
        }
        guard normalized == item.normalizedURL, (try? saver.model.itemID(forNormalizedURL: normalized)) == item.id
        else { return .failure(.invalid, "The item's ID doesn't match its URL.") }
        switch (item.kind, body) {
        case (.page, nil): return .failure(.invalid, "A page save has no Markdown.")
        case (.link, .some): return .failure(.invalid, "A link save can't have Markdown.")
        default: break
        }
        if let body, body.utf8.count > Self.maxBodyBytes {
            return .failure(.tooLarge, "This page is larger than 10 MB as Markdown. Save it as a link instead.")
        }
        return nil
    }

    private func status(_ url: String?) async -> Reply {
        guard let url else { return .failure(.invalid, "The status request has no URL.") }
        do {
            let id = try saver.model.itemID(forNormalizedURL: try saver.model.normalizedURL(pageURL: url))
            let item = try await saver.store.item(id: id)
            return Reply(ok: true, saved: item != nil, kind: item?.kind)
        } catch SatchelModelError.unsupportedURL(_) {
            return Reply(ok: true, saved: false)
        } catch {
            return .failure(.failed, "Status couldn't be read: \(error)")
        }
    }
}
