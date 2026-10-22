import Foundation

/// Turns what the user typed into an FTS5 query (FR-7).
///
/// Each whitespace-separated word becomes a quoted string with a prefix star, so the input is never parsed as
/// FTS5 syntax (`OR`, `NEAR`, `col:`, `^`, parentheses, and quotes all match literally) and a partial word still
/// matches: `kay` finds "kayak". The words are ANDed. Words with no letters or digits are dropped, since the
/// tokenizer would index nothing for them.
enum SearchPattern {
    static func make(_ query: String?) -> String? {
        guard let query else { return nil }
        let words = query.split(whereSeparator: \.isWhitespace)
            .filter { $0.contains { $0.isLetter || $0.isNumber } }
        guard !words.isEmpty else { return nil }
        return words.map { "\"" + $0.replacingOccurrences(of: "\"", with: "\"\"") + "\"*" }.joined(separator: " ")
    }
}
