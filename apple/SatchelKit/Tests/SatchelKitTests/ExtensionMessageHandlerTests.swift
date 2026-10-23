import CloudKit
import Foundation
import Testing

@testable import SatchelKit

@Suite struct ExtensionMessageHandlerTests {
    typealias Reply = ExtensionMessageHandler.Reply

    let fixture: ItemSaverTests.Fixture
    let handler: ExtensionMessageHandler

    init() throws {
        fixture = try ItemSaverTests.Fixture()
        handler = ExtensionMessageHandler(saver: fixture.saver)
    }

    /// What `itemFromCapture` builds for `url`.
    func item(
        _ url: String, kind: ItemKind = .link, title: String = "Kayaking", tags: [String] = [],
        updatedAt: String = "2026-10-22T12:00:00.000Z"
    ) throws -> Item {
        let model = SatchelModelTests.model
        let normalized = try model.normalizedURL(pageURL: url)
        var item = Item(
            id: try model.itemID(forNormalizedURL: normalized), kind: kind, url: url, canonicalURL: url,
            normalizedURL: normalized, title: title, tags: tags, createdAt: updatedAt, updatedAt: updatedAt,
            metadataStatus: .complete, source: ItemSource(client: .safariIOS, version: "2026.10.0"))
        if kind == .page {
            item.capturedAt = updatedAt
            item.page = PageInfo(wordCount: 120, readingMinutes: 1, engine: "defuddle@0.19.4 + turndown@7.2.4")
        }
        return item
    }

    func save(_ item: Item, body: String? = nil, existingPage: ExtensionMessageHandler.ExistingPage? = nil) async
        -> Reply
    {
        await handler.reply(
            to: .init(type: "save", item: item, body: body, existingPage: existingPage))
    }

    @Test func answersPing() async throws {
        let reply = await handler.reply(toJSONObject: ["type": "ping"])
        #expect(reply["ok"] as? Bool == true)
        #expect(reply["pong"] as? Bool == true)
    }

    @Test func savesALinkFromJSON() async throws {
        let link = try item("https://www.example.com/kayak?utm_source=feed", tags: ["rivers"])
        let json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(link))
        let reply = await handler.reply(toJSONObject: ["type": "save", "item": json])

        #expect(reply["ok"] as? Bool == true)
        #expect(reply["synced"] as? Bool == true)
        #expect((reply["item"] as? [String: Any])?["id"] as? String == link.id)
        #expect(try await fixture.saver.store.item(id: link.id) == link)
        #expect(try await fixture.saver.store.outboxState(for: link.id) == .sent)
    }

    @Test func savesAPageWithItsBody() async throws {
        let page = try item("https://example.com/kayak", kind: .page)
        let reply = await save(page, body: "# Kayaking\n\nBody\n")
        #expect(reply.ok)
        #expect(try await fixture.saver.store.body(for: page.id) == "# Kayaking\n\nBody\n")
        let record = try #require(fixture.database.state.withLock { $0.records.values.first })
        #expect(record["body"] as? String == "# Kayaking\n\nBody\n")
    }

    @Test func aLinkUpgradesToAPageWithoutAsking() async throws {
        _ = await save(try item("https://example.com/kayak"))
        let reply = await save(
            try item("https://example.com/kayak", kind: .page, updatedAt: "2026-10-22T13:00:00.000Z"), body: "# K\n")
        #expect(reply.ok)
        #expect(reply.item?.kind == .page)
    }

    @Test func asksBeforeReplacingASavedPage() async throws {
        let first = try item("https://example.com/kayak", kind: .page, tags: ["old"])
        _ = await save(first, body: "# Old\n")
        let second = try item(
            "https://example.com/kayak", kind: .page, tags: ["new"], updatedAt: "2026-10-22T13:00:00.000Z")

        #expect(await save(second, body: "# New\n") == Reply(ok: false, confirm: "replace"))
        #expect(try await fixture.saver.store.body(for: first.id) == "# Old\n")

        let kept = await save(second, body: "# New\n", existingPage: .keep)
        #expect(kept.ok)
        #expect(try await fixture.saver.store.body(for: first.id) == "# Old\n")
        #expect(kept.item?.tags == ["old", "new"])
        #expect(kept.item?.capturedAt == first.capturedAt)

        let replaced = await save(second, body: "# New\n", existingPage: .replace)
        #expect(replaced.ok)
        #expect(try await fixture.saver.store.body(for: first.id) == "# New\n")
    }

    @Test func rejectsAPageOver10MB() async throws {
        let body = String(repeating: "a", count: ExtensionMessageHandler.maxBodyBytes + 1)
        let reply = await save(try item("https://example.com/huge", kind: .page), body: body)
        #expect(reply.code == .tooLarge)
        #expect(reply.error?.contains("Save it as a link") == true)
        #expect(try await fixture.saver.store.items().isEmpty)
    }

    @Test func rejectsInconsistentItems() async throws {
        var wrongID = try item("https://example.com/a")
        wrongID.id = "u_00000000000000000000000000000000"
        #expect(await save(wrongID).code == .invalid)
        #expect(await save(try item("https://example.com/a", kind: .page)).code == .invalid)
        #expect(await save(try item("https://example.com/a"), body: "# A\n").code == .invalid)
        #expect(await handler.reply(toJSONObject: ["type": "save", "item": ["id": 1]])["code"] as? String == "invalid")
        #expect(await handler.reply(toJSONObject: "nonsense")["code"] as? String == "invalid")
        #expect(try await fixture.saver.store.items().isEmpty)
    }

    @Test func reportsAQueuedSave() async throws {
        let fixture = try ItemSaverTests.Fixture(recordErrors: [CKError(.networkUnavailable)])
        let handler = ExtensionMessageHandler(saver: fixture.saver)
        let reply = await handler.reply(to: .init(type: "save", item: try item("https://example.com/a")))
        #expect(reply.ok)
        #expect(reply.synced == false)
        #expect(reply.syncError == "network unavailable")
    }

    @Test func listsTagsAndStatus() async throws {
        _ = await save(try item("https://example.com/a", tags: ["swift", "ios"]))
        _ = await save(try item("https://example.com/b", tags: ["swift"]))

        #expect(await handler.reply(to: .init(type: "tags")).tags == ["swift", "ios"])
        #expect(await handler.reply(to: .init(type: "tags", prefix: "I")).tags == ["ios"])
        let saved = await handler.reply(to: .init(type: "status", url: "https://www.example.com/a?utm_source=x"))
        #expect(saved == Reply(ok: true, saved: true, kind: .link))
        #expect(await handler.reply(to: .init(type: "status", url: "https://example.com/c")).saved == false)
        #expect(await handler.reply(to: .init(type: "status", url: "about:blank")).saved == false)
    }

    @Test func rejectsUnknownTypes() async throws {
        #expect(await handler.reply(to: .init(type: "launch")).code == .unknownType)
    }
}
