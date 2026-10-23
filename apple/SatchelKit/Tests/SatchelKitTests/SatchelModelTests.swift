import Foundation
import Testing

@testable import SatchelKit

/// The JavaScriptCore bridge (ADR-0020) against the shared vectors that `packages/model/test/vectors.test.ts` writes.
/// Needs `packages/model/dist/model.jsc.iife.js`; `mise run verify:apple` builds it first.
@Suite struct SatchelModelTests {
    static let repo = ContractFixtures.directory.deletingLastPathComponent().deletingLastPathComponent()
    static let model: SatchelModel = {
        let url = repo.appending(path: "packages/model/dist/model.jsc.iife.js")
        guard let source = try? String(contentsOf: url, encoding: .utf8) else {
            fatalError("missing \(url.path()); run `pnpm --filter @satchel/model build` (mise run verify:apple does)")
        }
        return SatchelModel(source: source)
    }()

    struct NormalizationVector: Decodable, Sendable, CustomTestStringConvertible {
        let pageUrl: String
        let canonicalUrl: String?
        let normalizedUrl: String?
        let id: String?
        let error: String?
        var testDescription: String { pageUrl + (canonicalUrl.map { " ← \($0)" } ?? "") }
    }

    struct MergeVector: Decodable, Sendable, CustomTestStringConvertible {
        let name: String
        let a: Item
        let b: Item
        let result: MergeResult
        var testDescription: String { name }
    }

    static func vectors<T: Decodable>(_ name: String) throws -> [T] {
        try JSONDecoder().decode(
            [T].self, from: Data(contentsOf: ContractFixtures.directory.appending(path: "vectors/\(name)")))
    }

    @Test(arguments: try vectors("normalization.json") as [NormalizationVector])
    func normalizesAndDerivesIDs(vector: NormalizationVector) throws {
        if vector.error != nil {
            #expect(throws: SatchelModelError.self) {
                try Self.model.normalizedURL(pageURL: vector.pageUrl, canonicalURL: vector.canonicalUrl)
            }
        } else {
            let normalized = try Self.model.normalizedURL(pageURL: vector.pageUrl, canonicalURL: vector.canonicalUrl)
            #expect(normalized == vector.normalizedUrl)
            #expect(try Self.model.itemID(forNormalizedURL: normalized) == vector.id)
        }
    }

    @Test(arguments: try vectors("merge.json") as [MergeVector])
    func mergesLikeTheTypeScriptModel(vector: MergeVector) throws {
        #expect(try Self.model.merge(vector.a, vector.b) == vector.result)
    }

    @Test(arguments: try vectors("merge.json") as [MergeVector])
    func mergeIsCommutative(vector: MergeVector) throws {
        let ab = try Self.model.merge(vector.a, vector.b)
        let ba = try Self.model.merge(vector.b, vector.a)
        #expect(ab.item == ba.item)
        #expect(ab.replacesBody == ba.replacesBody)
    }

    @Test func rejectsNonHTTPURLsWithATypedError() {
        #expect {
            try Self.model.normalizedURL(pageURL: "ftp://example.com/file")
        } throws: { error in
            guard case .unsupportedURL = error as? SatchelModelError else { return false }
            return true
        }
    }

    @Test func fixtureItemsDeriveTheirOwnIDs() throws {
        for (name, data) in try ContractFixtures.all() {
            let item = try JSONDecoder().decode(Item.self, from: data)
            let normalized = try Self.model.normalizedURL(pageURL: item.url, canonicalURL: item.canonicalURL)
            #expect(normalized == item.normalizedURL, "\(name)")
            #expect(try Self.model.itemID(forNormalizedURL: normalized) == item.id, "\(name)")
        }
    }

    @Test func storeMergesThroughTheBridge() async throws {
        let dir = FileManager.default.temporaryDirectory.appending(path: "satchel-model-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = try Store(url: dir.appending(path: "store.sqlite"), merge: Self.model.itemMerge)
        let vector = try #require(
            (try Self.vectors("merge.json") as [MergeVector]).first { $0.name == "link upgraded to a page" })

        try await store.save(item: vector.a)
        let merged = try await store.save(item: vector.b, body: "# Hello\n")
        #expect(merged == vector.result.item)
        #expect(try await store.item(id: vector.a.id)?.kind == .page)
        #expect(try await store.body(for: vector.a.id) == "# Hello\n")
    }

    @Test func exportsMarkdownFiles() throws {
        var link = makeItem("hello", title: "Hello: World", tags: ["swift"])
        link.description = "A first post."
        let file = try Self.model.markdownFile(for: link, body: nil)
        #expect(file.hasPrefix("---\nid: u_hello\ntype: link\ntitle: \"Hello: World\"\n"))
        #expect(file.contains("tags: [swift]\nsource: ios-share\n---\n\n# Hello: World\n\nA first post.\n"))

        let page = makeItem("hello", kind: .page, title: "Hello")
        #expect(
            try Self.model.markdownFile(for: page, body: "# Hello\n\nBody.\n").hasSuffix("---\n\n# Hello\n\nBody.\n"))
    }

    @Test func reportsABrokenScript() {
        let broken = SatchelModel(source: "this is not javascript")
        #expect(throws: SatchelModelError.self) { try broken.itemID(forNormalizedURL: "https://example.com/") }
    }

    @Test func isSafeToCallConcurrently() async throws {
        let ids = try await withThrowingTaskGroup(of: String.self) { group in
            for i in 0..<64 {
                group.addTask { try Self.model.itemID(forNormalizedURL: "https://example.com/\(i % 4)") }
            }
            return try await group.reduce(into: Set<String>()) { $0.insert($1) }
        }
        #expect(ids.count == 4)
    }
}
