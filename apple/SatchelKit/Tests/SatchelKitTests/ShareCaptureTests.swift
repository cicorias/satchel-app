import Foundation
import Testing

@testable import SatchelKit

@Suite struct TagInputTests {
    @Test func splitsOnCommasAndPeriods() {
        #expect(TagInput.tags(from: " Great, tools. Reading,, great ") == ["great", "tools", "reading"])
        #expect(TagInput.tags(from: "great tools") == ["great tools"])
        #expect(TagInput.tags(from: " , . ").isEmpty)
    }

    @Test func completesTheTagBeingTyped() {
        #expect(TagInput.fragment(of: "swift, IO") == "io")
        #expect(TagInput.completing("swift, io", with: "ios") == "swift, ios, ")
        #expect(TagInput.completing("sw", with: "swift") == "swift, ")
        #expect(TagInput.completing("a. b", with: "books") == "a. books, ")
    }

    @Test func suggestsKnownTagsNotYetEntered() {
        let known = ["swift", "safari", "ios", "reading"]
        #expect(TagInput.suggestions(for: "", from: known) == known)
        #expect(TagInput.suggestions(for: "s", from: known) == ["swift", "safari"])
        #expect(TagInput.suggestions(for: "swift, s", from: known) == ["safari"])
        #expect(TagInput.suggestions(for: "swift, ", from: known) == ["safari", "ios", "reading"])
        #expect(TagInput.suggestions(for: "swift", from: known).isEmpty)
    }
}

@Suite struct SafariShareCaptureTests {
    @Test func decodesThePreprocessingResult() throws {
        let link = makeItem("a", title: "Kayaking")
        var page = makeItem("a", kind: .page, title: "Kayaking")
        page.capturedAt = page.createdAt
        let json = String(
            decoding: try JSONSerialization.data(withJSONObject: [
                "url": link.url, "title": "Kayaking",
                "link": ["item": try JSONSerialization.jsonObject(with: JSONEncoder().encode(link))],
                "page": [
                    "item": try JSONSerialization.jsonObject(with: JSONEncoder().encode(page)), "body": "# Kayaking\n",
                ],
            ]), as: UTF8.self)

        let capture = try #require(SafariShareCapture.decode(results: ["satchel": json]))
        #expect(capture.url == link.url)
        #expect(capture.link?.item == link)
        #expect(capture.link?.body == nil)
        #expect(capture.page?.item == page)
        #expect(capture.page?.body == "# Kayaking\n")
        #expect(capture.pageError == nil)
    }

    @Test func keepsWhyThereIsNoPage() throws {
        let json = #"{"url":"https://example.com/","pageError":"too large"}"#
        let capture = try #require(SafariShareCapture.decode(results: ["satchel": json]))
        #expect(capture.page == nil)
        #expect(capture.pageError == "too large")
        #expect(SafariShareCapture.decode(results: ["other": json]) == nil)
        #expect(SafariShareCapture.decode(results: ["satchel": "{"]) == nil)
    }

    @Test func addsTagsAndANote() {
        let item = makeItem("a", tags: ["swift"]).adding(tags: ["ios", "swift"], note: "  later  ")
        #expect(item.tags == ["swift", "ios"])
        #expect(item.note == "later")
        #expect(makeItem("a").adding(tags: [], note: "   ").note == nil)
    }
}
