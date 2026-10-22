import Foundation

/// Converts between `Item`'s ISO 8601 strings and the `Date` values CloudKit's TIMESTAMP fields hold.
///
/// - Parsing accepts RFC 3339 date-times (`item.schema.json` says `format: date-time`) with or without fractional
///   seconds and with `Z` or a numeric offset: `2026-10-22T16:40:27.512Z`, `2026-10-22T16:40:27Z`,
///   `2026-10-22T18:40:27.512+02:00`. Date-only strings and lowercase `t`/`z` are rejected.
/// - Formatting always writes JavaScript's `Date.prototype.toISOString()` shape, UTC with exactly three fractional
///   digits (`2026-10-22T16:40:27.512Z`), which is what `packages/capture` and `packages/model` produce. CloudKit keeps
///   timestamps to the millisecond, so the instant is rounded to the nearest millisecond first.
///
/// A string in that shape round-trips exactly. Any other valid string comes back as the same instant in that shape:
/// `+02:00` becomes `Z`, a missing fraction becomes `.000`, and digits past the millisecond are rounded away.
/// `ItemRecordMapper` keeps the local string instead when it names the same millisecond (see `item(from:existing:)`).
public enum CloudKitTimestamp {
    /// The instant `string` names, or nil if it isn't an RFC 3339 date-time.
    public static func date(from string: String) -> Date? {
        if let date = try? Date.ISO8601FormatStyle(includingFractionalSeconds: true).parse(string) { return date }
        return try? Date.ISO8601FormatStyle().parse(string)
    }

    /// `date` as `YYYY-MM-DDTHH:mm:ss.sssZ`, rounded to the millisecond.
    public static func string(from date: Date) -> String {
        let milliseconds = milliseconds(of: date)
        let (seconds, fraction) = floorDivision(milliseconds, 1000)
        // Whole seconds are exact in a Double, so the formatter can't round them; the fraction is added by hand.
        let whole = Date(timeIntervalSince1970: TimeInterval(seconds)).formatted(Date.ISO8601FormatStyle())
        return "\(whole.dropLast()).\(threeDigits(fraction))Z"
    }

    /// Whether two dates fall on the same millisecond, the precision CloudKit stores.
    public static func sameMillisecond(_ a: Date, _ b: Date) -> Bool {
        milliseconds(of: a) == milliseconds(of: b)
    }

    static func milliseconds(of date: Date) -> Int64 {
        Int64((date.timeIntervalSince1970 * 1000).rounded())
    }

    private static func floorDivision(_ value: Int64, _ divisor: Int64) -> (quotient: Int64, remainder: Int64) {
        let remainder = ((value % divisor) + divisor) % divisor
        return ((value - remainder) / divisor, remainder)
    }

    private static func threeDigits(_ value: Int64) -> String {
        let digits = String(value)
        return String(repeating: "0", count: max(0, 3 - digits.count)) + digits
    }
}
