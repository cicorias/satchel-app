import Foundation

/// The outcome of merging two copies of the same item (spec §7.3). The same shape, and the same JSON keys, as
/// `MergeResult` in `packages/model/src/merge.ts`, so the JavaScriptCore bridge (ADR-0020) can decode it directly.
public struct MergeResult: Codable, Sendable, Equatable {
    /// Whose Markdown body the merged item keeps.
    public enum BodySource: String, Codable, Sendable, CaseIterable {
        /// The first argument's body.
        case a
        /// The second argument's body.
        case b
        /// Neither side is a page capture, so there is no body.
        case none
    }

    public var item: Item
    public var body: BodySource
    /// Both sides carry a page body and one replaces the other. An interactive re-save asks "Replace saved copy?"
    /// before saving; sync applies the merge without asking.
    public var replacesBody: Bool

    public init(item: Item, body: BodySource, replacesBody: Bool) {
        self.item = item
        self.body = body
        self.replacesBody = replacesBody
    }
}

/// Merges two copies of one item: `merge(a, b)`. It must be pure and commutative, like `mergeItems` in
/// `packages/model`. `Store` calls it as `merge(stored, incoming)`, so `.a` means the stored body and `.b` the
/// incoming one.
public typealias ItemMerge = @Sendable (_ a: Item, _ b: Item) throws -> MergeResult
