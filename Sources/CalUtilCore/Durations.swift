import Foundation

/// Durations written as `1w2d3h4m5s` (any subset, largest unit first), e.g. `90m`,
/// `1h30m`, `2d`. A bare `0` means zero.
public enum Durations {
    private static let units: [(symbol: Character, seconds: Int)] = [
        ("w", 7 * 86_400), ("d", 86_400), ("h", 3_600), ("m", 60), ("s", 1),
    ]

    /// Returns the duration in seconds.
    public static func parse(_ raw: String) throws -> Int {
        let text = raw.trimmingCharacters(in: .whitespaces).lowercased()
        if text == "0" { return 0 }
        let invalid = CalUtilError(
            "invalid duration '\(raw)': use a number and a unit, e.g. 15m, 2h, 1h30m, 3d or 1w")
        guard !text.isEmpty else { throw invalid }

        var total = 0
        var digits = ""
        var lastUnit = -1
        for ch in text {
            if ch.isASCII && ch.isNumber {
                digits.append(ch)
                continue
            }
            guard let unit = units.firstIndex(where: { $0.symbol == ch }),
                  unit > lastUnit,  // units in order, each at most once
                  let number = Int(digits)
            else { throw invalid }
            let (part, overflow1) = number.multipliedReportingOverflow(by: units[unit].seconds)
            let (sum, overflow2) = total.addingReportingOverflow(part)
            guard !overflow1, !overflow2 else { throw invalid }
            total = sum
            lastUnit = unit
            digits = ""
        }
        guard digits.isEmpty, lastUnit >= 0 else { throw invalid }
        return total
    }

    /// "1 day 2 hours", "15 minutes", "0 minutes".
    public static func describe(_ seconds: Int) -> String {
        if seconds == 0 { return "0 minutes" }
        let names = ["week", "day", "hour", "minute", "second"]
        var rest = seconds
        var parts: [String] = []
        for (index, unit) in units.enumerated() {
            let n = rest / unit.seconds
            rest %= unit.seconds
            if n > 0 { parts.append("\(n) \(names[index])\(n == 1 ? "" : "s")") }
        }
        return parts.joined(separator: " ")
    }

    /// RFC 5545 duration (without sign), e.g. "P1DT2H30M", "PT15M", "PT0S".
    public static func icalendar(_ seconds: Int) -> String {
        if seconds == 0 { return "PT0S" }
        let days = seconds / 86_400
        let h = seconds % 86_400 / 3_600
        let m = seconds % 3_600 / 60
        let s = seconds % 60
        var out = "P"
        if days > 0 { out += "\(days)D" }
        if h > 0 || m > 0 || s > 0 {
            out += "T"
            if h > 0 { out += "\(h)H" }
            if m > 0 { out += "\(m)M" }
            if s > 0 { out += "\(s)S" }
        }
        return out
    }
}
