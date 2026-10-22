import Foundation

/// Any JSON value. Holds the fields of an `Item` that this version doesn't know, so they survive a round trip
/// (spec §7.1).
public enum JSONValue: Sendable, Equatable, Hashable, Codable {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])

    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([JSONValue].self) {
            self = .array(value)
        } else {
            self = .object(try container.decode([String: JSONValue].self))
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .null: try container.encodeNil()
        case .bool(let value): try container.encode(value)
        case .number(let value): try container.encode(value)
        case .string(let value): try container.encode(value)
        case .array(let value): try container.encode(value)
        case .object(let value): try container.encode(value)
        }
    }
}

/// A coding key for any string, used to read and write the keys a type doesn't declare.
struct AnyCodingKey: CodingKey {
    var stringValue: String
    var intValue: Int? { nil }
    init(_ string: String) { stringValue = string }
    init?(stringValue: String) { self.stringValue = stringValue }
    init?(intValue: Int) { nil }
}

extension KeyedDecodingContainer where Key == AnyCodingKey {
    /// Every key not in `known`, decoded as raw JSON.
    func unknownFields(excluding known: Set<String>) throws -> [String: JSONValue] {
        var extra: [String: JSONValue] = [:]
        for key in allKeys where !known.contains(key.stringValue) {
            extra[key.stringValue] = try decode(JSONValue.self, forKey: key)
        }
        return extra
    }
}

extension KeyedEncodingContainer where Key == AnyCodingKey {
    mutating func encodeUnknownFields(_ extra: [String: JSONValue]) throws {
        for (key, value) in extra.sorted(by: { $0.key < $1.key }) {
            try encode(value, forKey: AnyCodingKey(key))
        }
    }
}
