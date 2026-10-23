import Foundation

/// Tags typed into a save sheet: separated by commas or periods, then lowercased, trimmed, and deduplicated in order,
/// the same rule as the extension popup (`normalizeTags` after splitting in `popup/main.ts`).
public enum TagInput {
    public static let separators = CharacterSet(charactersIn: ",.")

    public static func tags(from text: String) -> [String] {
        var seen = Set<String>()
        return text.components(separatedBy: separators)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .filter { !$0.isEmpty && seen.insert($0).inserted }
    }

    /// The tag being typed: the text after the last separator, trimmed and lowercased.
    public static func fragment(of text: String) -> String {
        let last = text.components(separatedBy: separators).last ?? ""
        return last.trimmingCharacters(in: .whitespaces).lowercased()
    }

    /// `text` with the tag being typed replaced by `tag`, ready for the next one.
    public static func completing(_ text: String, with tag: String) -> String {
        guard let range = text.rangeOfCharacter(from: separators, options: .backwards) else { return tag + ", " }
        return text[..<range.upperBound].trimmingCharacters(in: .whitespaces) + " " + tag + ", "
    }

    /// Up to `limit` known tags that start with the tag being typed and aren't entered yet.
    public static func suggestions(for text: String, from known: [String], limit: Int = 8) -> [String] {
        let fragment = fragment(of: text)
        let entered = Set(tags(from: text).dropLast(fragment.isEmpty ? 0 : 1))
        return Array(known.filter { $0.hasPrefix(fragment) && !entered.contains($0) && $0 != fragment }.prefix(limit))
    }
}

/// What the Share Extension's preprocessing script (`SatchelShare/preprocessing.js`) returns from Safari: the page's
/// link item, and its page item with Markdown when page capture worked (spec §9.2.2). Both items are built in the page
/// by `itemFromCapture`, with no tags or note yet.
public struct SafariShareCapture: Decodable, Sendable, Equatable {
    public struct Captured: Decodable, Sendable, Equatable {
        public var item: Item
        public var body: String?
    }

    public var url: String
    public var title: String?
    public var link: Captured?
    public var linkError: String?
    public var page: Captured?
    /// Why there's no page capture, for the sheet.
    public var pageError: String?

    /// The key the script's result dictionary carries the capture's JSON under.
    public static let resultKey = "satchel"

    /// Decodes the script's results (`NSExtensionJavaScriptPreprocessingResultsKey`).
    public static func decode(results: [String: Any]) -> SafariShareCapture? {
        guard let json = results[resultKey] as? String else { return nil }
        return try? JSONDecoder().decode(SafariShareCapture.self, from: Data(json.utf8))
    }
}

extension Item {
    /// The item with tags (merged after any it has) and a note typed into a save sheet.
    public func adding(tags: [String], note: String?) -> Item {
        var item = self
        var seen = Set(item.tags)
        item.tags += tags.filter { seen.insert($0).inserted }
        if let note = note?.trimmingCharacters(in: .whitespacesAndNewlines), !note.isEmpty { item.note = note }
        return item
    }
}
