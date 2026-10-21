/// Mirrors `Item.kind` in `packages/model` (spec §7.1).
public enum ItemKind: String, Codable, Sendable, CaseIterable {
    case link
    case page
}
