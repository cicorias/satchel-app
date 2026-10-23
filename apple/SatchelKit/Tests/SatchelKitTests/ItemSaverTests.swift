import CloudKit
import Foundation
import Testing

@testable import SatchelKit

@Suite struct ItemSaverTests {
    final class Fixture {
        let directory = FileManager.default.temporaryDirectory.appending(path: "item-saver-\(UUID().uuidString)")
        let database: FakeDatabase
        let saver: ItemSaver

        init(recordErrors: [any Error] = []) throws {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let environment = AppEnvironment(
                appGroup: "group.example", iCloudContainer: "iCloud.example", cloudKitZone: "Library",
                version: "2026.10.0", build: "1")
            let mapper = ItemRecordMapper(environment: environment, assetDirectory: directory.appending(path: "assets"))
            database = FakeDatabase(zones: [mapper.zoneID], recordErrors: recordErrors)
            let model = SatchelModelTests.model
            saver = ItemSaver(
                store: try Store(url: directory.appending(path: "store.sqlite"), merge: model.itemMerge), model: model,
                cloud: OneShotSaver(database: database, mapper: mapper), environment: environment)
        }

        deinit { try? FileManager.default.removeItem(at: directory) }
    }

    static let now = Date(timeIntervalSince1970: 1_792_687_227.512)

    @Test func savesAPendingLinkAndMarksItSent() async throws {
        let fixture = try Fixture()
        let outcome = try await fixture.saver.saveLink(
            url: "https://www.example.com/articles/hello-world/?utm_source=newsletter#comments", client: .iosShare,
            now: Self.now)

        #expect(outcome.cloud == .saved)
        #expect(outcome.item.id == "u_445740458d1bf9f96939cbc420e6973c")
        #expect(outcome.item.normalizedURL == "https://example.com/articles/hello-world")
        #expect(outcome.item.metadataStatus == .pending)
        #expect(outcome.item.kind == .link)
        #expect(outcome.item.title == "www.example.com/articles/hello-world/")
        #expect(outcome.item.createdAt == "2026-10-22T16:40:27.512Z")
        #expect(outcome.item.source == ItemSource(client: .iosShare, version: "2026.10.0"))
        #expect(try await fixture.saver.store.outboxState(for: outcome.item.id) == .sent)
        #expect(fixture.database.state.withLock { $0.records.count } == 1)
    }

    @Test func queuesTheSaveWhenCloudKitFails() async throws {
        let fixture = try Fixture(recordErrors: [CKError(.notAuthenticated)])
        let outcome = try await fixture.saver.saveLink(url: "https://example.org/a", client: .iosShare, now: Self.now)

        #expect(outcome.cloud == .queued(.notAuthenticated))
        #expect(try await fixture.saver.store.outboxState(for: outcome.item.id) == .failed)
        #expect(try await fixture.saver.store.item(id: outcome.item.id) == outcome.item)
    }

    @Test func resharingTheSameURLMergesIntoOneItem() async throws {
        let fixture = try Fixture()
        let first = try await fixture.saver.saveLink(
            url: "https://example.com/a?utm_source=x", tags: ["swift"], client: .iosShare, now: Self.now)
        let second = try await fixture.saver.saveLink(
            url: "https://www.example.com/a/", tags: ["ios"], note: "  read later  ", client: .iosShare,
            now: Self.now.addingTimeInterval(60))

        #expect(second.item.id == first.item.id)
        #expect(second.item.tags == ["swift", "ios"])
        #expect(second.item.note == "read later")
        #expect(second.item.createdAt == first.item.createdAt)
        #expect(try await fixture.saver.store.items().count == 1)
    }

    @Test func usesTheSharedTitle() async throws {
        let fixture = try Fixture()
        let outcome = try await fixture.saver.saveLink(
            url: "https://example.com/", title: "  Example Domain ", client: .iosShare, now: Self.now)
        #expect(outcome.item.title == "Example Domain")
        #expect(ItemSaver.fallbackTitle(for: "https://example.com/") == "example.com")
    }

    @Test func rejectsANonHTTPURL() async throws {
        let fixture = try Fixture()
        await #expect(throws: SatchelModelError.self) {
            try await fixture.saver.saveLink(url: "file:///etc/hosts", client: .iosShare)
        }
        #expect(try await fixture.saver.store.items().isEmpty)
    }
}
