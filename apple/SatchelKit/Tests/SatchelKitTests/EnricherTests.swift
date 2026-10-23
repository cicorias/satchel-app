import Foundation
import Synchronization
import Testing

@testable import SatchelKit

/// Answers from a script per URL, and records the order of loads.
final class FakeLoader: LinkMetadataLoader {
    enum Answer {
        case metadata(LinkMetadata)
        case failure
        case hang
    }

    let answers: Mutex<[String: [Answer]]>
    let loads = Mutex<[String]>([])

    init(_ answers: [String: [Answer]]) {
        self.answers = Mutex(answers)
    }

    func metadata(for url: String) async throws -> LinkMetadata {
        loads.withLock { $0.append(url) }
        let answer = answers.withLock { answers -> Answer in
            guard var queue = answers[url], !queue.isEmpty else { return .failure }
            let first = queue.removeFirst()
            answers[url] = queue.isEmpty ? [first] : queue
            return first
        }
        switch answer {
        case .metadata(let metadata): return metadata
        case .failure: throw EnrichmentError.load("offline")
        case .hang:
            try await Task.sleep(for: .seconds(60))
            throw EnrichmentError.load("hung")
        }
    }
}

struct FakeNetwork: NetworkConditions {
    var allowed = true
    var allowsEnrichment: Bool { get async { allowed } }
}

/// A clock the test moves forward; sleeps advance it instead of waiting.
final class FakeClock: Sendable {
    let date = Mutex(Date(timeIntervalSince1970: 1_792_687_227))
    let slept = Mutex<[Duration]>([])

    func advance(_ seconds: TimeInterval) { date.withLock { $0 += seconds } }
}

@Suite struct EnricherTests {
    final class Fixture {
        let directory: TempDirectory
        let store: Store
        let clock = FakeClock()

        init() throws {
            directory = try TempDirectory()
            store = try Store(url: directory.database, merge: SatchelModelTests.model.itemMerge)
        }

        func enricher(_ loader: FakeLoader, network: FakeNetwork = .init(), policy: Enricher.Policy = .init())
            -> Enricher
        {
            let clock = self.clock
            return Enricher(
                store: store, loader: loader, network: network, policy: policy, now: { clock.date.withLock { $0 } },
                sleep: { duration in clock.slept.withLock { $0.append(duration) } })
        }

        /// A link shared from another app: pending, with the host + path title.
        @discardableResult
        func pending(_ slug: String, host: String = "example.com") async throws -> Item {
            var item = makeItem(slug, title: "\(host)/\(slug)", host: host, tags: ["mine"])
            item.metadataStatus = .pending
            item.note = "keep this"
            return try await store.save(item: item)
        }
    }

    static let metadata = LinkMetadata(
        title: "Harbour bridge reopens", description: "Crowds gathered.", siteName: "Example News",
        canonicalUrl: "https://example.com/other", imageUrl: "https://cdn.example.com/bridge.jpg", author: "Priya",
        faviconUrl: "https://example.com/icon.png", lang: "en-GB")

    @Test func fillsInAPendingLinkAndKeepsWhatTheUserAdded() async throws {
        let f = try Fixture()
        let item = try await f.pending("a")
        let loader = FakeLoader([item.url: [.metadata(Self.metadata)]])

        let report = await f.enricher(loader).run()
        #expect(report.enriched == [item.id])
        let stored = try #require(try await f.store.item(id: item.id))
        #expect(stored.metadataStatus == .complete)
        #expect(stored.title == "Harbour bridge reopens")
        #expect(stored.siteName == "Example News")
        #expect(stored.imageURL == "https://cdn.example.com/bridge.jpg")
        #expect(stored.description == "Crowds gathered.")
        #expect(stored.tags == ["mine"])
        #expect(stored.note == "keep this")
        // Identity never changes, even though the page names another canonical URL.
        #expect(stored.id == item.id)
        #expect(stored.canonicalURL == item.canonicalURL)
        #expect(try await f.store.outboxState(for: item.id) == .pending)
        // Nothing left to do.
        #expect(await f.enricher(loader).run().enriched.isEmpty)
    }

    @Test func retriesAfterADelayThenGivesUp() async throws {
        let f = try Fixture()
        let item = try await f.pending("a")
        let loader = FakeLoader([item.url: [.failure]])
        let enricher = f.enricher(loader)

        #expect(await enricher.run().retrying == [item.id])
        #expect(try await enricher.attempts(for: item.id)?.count == 1)
        // Not due yet: skipped without a load.
        #expect(await enricher.run().retrying.isEmpty)
        #expect(loader.loads.withLock { $0.count } == 1)

        f.clock.advance(5 * 60)
        #expect(await enricher.run().retrying == [item.id])
        f.clock.advance(60 * 60)
        #expect(await enricher.run().failed == [item.id])
        #expect(try await f.store.item(id: item.id)?.metadataStatus == .failed)
        #expect(try await enricher.attempts(for: item.id) == nil)
        #expect(loader.loads.withLock { $0.count } == 3)
        // Failed items aren't tried again.
        f.clock.advance(24 * 60 * 60)
        #expect(await enricher.run().failed.isEmpty)
    }

    @Test func succeedsOnALaterAttempt() async throws {
        let f = try Fixture()
        let item = try await f.pending("a")
        let enricher = f.enricher(FakeLoader([item.url: [.failure, .metadata(Self.metadata)]]))
        _ = await enricher.run()
        f.clock.advance(5 * 60)
        #expect(await enricher.run().enriched == [item.id])
        #expect(try await enricher.attempts(for: item.id) == nil)
    }

    @Test func spacesRequestsToTheSameHost() async throws {
        let f = try Fixture()
        try await f.pending("a")
        try await f.pending("b")
        try await f.pending("c", host: "other.example")
        let loader = FakeLoader([:])
        var policy = Enricher.Policy()
        policy.perHostInterval = .seconds(30)
        _ = await f.enricher(loader, policy: policy).run()

        #expect(loader.loads.withLock { $0.count } == 3)
        // One wait, before the second example.com request; the other host isn't held up.
        let slept = f.clock.slept.withLock { $0 }
        #expect(slept.count == 1)
        #expect(slept.first.map { $0 > .seconds(29) } == true)
    }

    @Test func timesOutAHungLoad() async throws {
        let f = try Fixture()
        let item = try await f.pending("a")
        var policy = Enricher.Policy()
        policy.timeout = .milliseconds(50)
        #expect(await f.enricher(FakeLoader([item.url: [.hang]]), policy: policy).run().retrying == [item.id])
    }

    @Test func respectsTheBatchLimit() async throws {
        let f = try Fixture()
        for slug in ["a", "b", "c"] { try await f.pending(slug, host: "\(slug).example") }
        let loader = FakeLoader([:])
        var policy = Enricher.Policy()
        policy.batchLimit = 2
        _ = await f.enricher(loader, policy: policy).run()
        #expect(loader.loads.withLock { $0.count } == 2)
    }

    @Test func waitsForTheNetwork() async throws {
        let f = try Fixture()
        try await f.pending("a")
        let loader = FakeLoader([:])
        #expect(await f.enricher(loader, network: FakeNetwork(allowed: false)).run().skipped)
        #expect(loader.loads.withLock { $0.isEmpty })
    }

    @Test func leavesCompleteItemsAlone() async throws {
        let f = try Fixture()
        try await f.store.save(item: makeItem("done"))
        let loader = FakeLoader([:])
        _ = await f.enricher(loader).run()
        #expect(loader.loads.withLock { $0.isEmpty })
    }
}

/// The real loader on a fixture page: proves the injection path (load in WKWebView, inject capture.iife.js, call
/// captureLink) without the network. Needs `packages/capture/dist/capture.iife.js` (`mise run verify:apple`).
@Suite struct WebMetadataLoaderTests {
    @MainActor
    @Test func readsAFixturePage() async throws {
        let repo = SatchelModelTests.repo
        let script = try String(
            contentsOf: repo.appending(path: "packages/capture/dist/capture.iife.js"), encoding: .utf8)
        let fixture = repo.appending(path: "fixtures/pages/news-og-twitter")
        let html = try String(contentsOf: fixture.appending(path: "input.html"), encoding: .utf8)
        let url = try String(contentsOf: fixture.appending(path: "url.txt"), encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let expected = try JSONDecoder().decode(
            LinkMetadata.self, from: Data(contentsOf: fixture.appending(path: "expected-metadata.json")))

        let metadata = try await WebMetadataLoader(captureScript: script).metadata(
            html: html, baseURL: try #require(URL(string: url)))
        #expect(metadata == expected)
    }

    @Test func keepsJSONLDThroughAScriptlessParse() {
        let html = """
            <head><script type="application/ld+json">{"a":"</textarea>"}</script>\
            <SCRIPT TYPE='application/ld+json'>{}</SCRIPT><script>alert(1)</script></head>
            """
        #expect(
            WebMetadataLoader.keepingJSONLD(html) == """
                <head><textarea data-satchel-ld hidden>{"a":"<\\/textarea>"}</textarea>\
                <textarea data-satchel-ld hidden>{}</textarea><script>alert(1)</script></head>
                """)
    }
}
