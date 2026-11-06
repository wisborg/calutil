import Foundation

public struct TimeOfDay: Equatable, Sendable {
    public var hour: Int
    public var minute: Int
    public var second: Int

    public init(hour: Int, minute: Int, second: Int = 0) {
        self.hour = hour
        self.minute = minute
        self.second = second
    }
}

/// A date as typed on the command line, before a time zone is applied.
public struct DateTimeInput: Equatable, Sendable {
    public var year: Int
    public var month: Int
    public var day: Int
    /// Nil for a date without a time (`2026-11-06`).
    public var time: TimeOfDay?
    /// Seconds east of UTC, when the text carried `Z` or an offset like `+11:00`.
    public var utcOffset: Int?
}

public enum DateParsing {
    /// Accepts `2026-11-06`, `2026-11-06T18:00`, `2026-11-06 18:00:30`,
    /// optionally followed by `Z`, `+11:00`, `+1100` or `+11`.
    public static func parseDateTime(_ raw: String) throws -> DateTimeInput {
        let invalid = CalUtilError(
            "invalid date '\(raw)': use YYYY-MM-DD or YYYY-MM-DDTHH:MM, e.g. 2026-11-06T18:00")
        let chars = Array(raw.trimmingCharacters(in: .whitespaces))
        guard chars.count >= 10 else { throw invalid }
        let (year, month, day) = try parseDate(String(chars[0..<10]), original: raw)
        if chars.count == 10 {
            return DateTimeInput(year: year, month: month, day: day, time: nil, utcOffset: nil)
        }

        guard ["T", "t", " "].contains(chars[10]), chars.count > 11 else { throw invalid }
        var timePart = String(chars[11...])
        var offset: Int?
        if timePart.hasSuffix("Z") || timePart.hasSuffix("z") {
            offset = 0
            timePart.removeLast()
        } else if let sign = timePart.lastIndex(where: { $0 == "+" || $0 == "-" }) {
            offset = try parseOffset(String(timePart[sign...]), original: raw)
            timePart = String(timePart[..<sign])
        }
        let time: TimeOfDay
        do { time = try parseTime(timePart) } catch { throw invalid }
        return DateTimeInput(year: year, month: month, day: day, time: time, utcOffset: offset)
    }

    /// Like `parseDateTime(_:)`, but also accepts a day word, optionally with a time:
    /// `today`, `tomorrow 18:00`, `friday 19:30` (see `parseDay`).
    public static func parseDateTime(_ raw: String, now: Date, timeZone: TimeZone) throws -> DateTimeInput {
        let text = raw.trimmingCharacters(in: .whitespaces)
        if looksLikeDate(text) { return try parseDateTime(text) }
        let parts = text.split(separator: " ", maxSplits: 1).map(String.init)
        guard let word = parts.first else { throw invalidDay(raw) }
        let (year, month, day) = try parseDay(word, now: now, timeZone: timeZone)
        let time = try parts.count == 2 ? parseTime(parts[1]) : nil
        return DateTimeInput(year: year, month: month, day: day, time: time, utcOffset: nil)
    }

    /// A calendar day: `today`, `tomorrow`, `yesterday`, a weekday (`friday`, `fri`: the
    /// next one, today included), or `YYYY-MM-DD`.
    public static func parseDay(_ raw: String, now: Date, timeZone: TimeZone) throws -> (year: Int, month: Int, day: Int) {
        let text = raw.trimmingCharacters(in: .whitespaces).lowercased()
        let calendar = gregorian(timeZone)
        func day(_ offset: Int) -> (Int, Int, Int) {
            let date = calendar.date(byAdding: .day, value: offset, to: now)!
            let c = calendar.dateComponents([.year, .month, .day], from: date)
            return (c.year!, c.month!, c.day!)
        }
        switch text {
        case "today": return day(0)
        case "tomorrow": return day(1)
        case "yesterday": return day(-1)
        default: break
        }
        let weekdays = ["sunday", "monday", "tuesday", "wednesday", "thursday", "friday", "saturday"]
        if text.count >= 3, let index = weekdays.firstIndex(where: { $0.hasPrefix(text) }) {
            let today = calendar.component(.weekday, from: now)  // 1 = Sunday
            return day((index + 1 - today + 7) % 7)
        }
        guard looksLikeDate(text), let input = try? parseDateTime(text), input.time == nil else {
            throw invalidDay(raw)
        }
        return (input.year, input.month, input.day)
    }

    private static func invalidDay(_ raw: String) -> CalUtilError {
        CalUtilError("invalid day '\(raw)': use today, tomorrow, yesterday, a weekday such as friday, or YYYY-MM-DD")
    }

    /// Accepts `18:00`, `9:30`, `18:00:30`.
    public static func parseTime(_ raw: String) throws -> TimeOfDay {
        let invalid = CalUtilError("invalid time '\(raw)': use HH:MM, e.g. 19:30")
        let parts = raw.trimmingCharacters(in: .whitespaces)
            .split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count == 2 || parts.count == 3,
              (1...2).contains(parts[0].count),
              parts.dropFirst().allSatisfy({ $0.count == 2 }),
              parts.allSatisfy({ allDigits($0) })
        else { throw invalid }
        let numbers = parts.map { Int($0)! }
        let time = TimeOfDay(hour: numbers[0], minute: numbers[1], second: numbers.count == 3 ? numbers[2] : 0)
        guard (0..<24).contains(time.hour), (0..<60).contains(time.minute), (0..<60).contains(time.second)
        else { throw invalid }
        return time
    }

    /// True when the text starts like a date (`YYYY-`), as opposed to a duration or a time.
    public static func looksLikeDate(_ text: String) -> Bool {
        let chars = Array(text.trimmingCharacters(in: .whitespaces))
        return chars.count >= 5 && allDigits(chars[0..<4]) && chars[4] == "-"
    }

    /// Builds a `Date`, rejecting dates that don't exist (2026-02-30) and wall-clock
    /// times skipped by a daylight-saving change.
    public static func makeDate(year: Int, month: Int, day: Int, time: TimeOfDay, timeZone: TimeZone) throws -> Date {
        let calendar = gregorian(timeZone)
        let wanted = DateComponents(year: year, month: month, day: day,
                                    hour: time.hour, minute: time.minute, second: time.second)
        let text = String(format: "%04d-%02d-%02d %02d:%02d", year, month, day, time.hour, time.minute)
        guard let date = calendar.date(from: wanted) else {
            throw CalUtilError("invalid date \(text)")
        }
        let got = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        guard got.year == year, got.month == month, got.day == day else {
            throw CalUtilError("there is no such date: \(String(format: "%04d-%02d-%02d", year, month, day))")
        }
        guard got.hour == time.hour, got.minute == time.minute, got.second == time.second else {
            throw CalUtilError("\(text) does not exist in \(timeZone.identifier) (the clocks skip it for daylight saving time)")
        }
        return date
    }

    /// The first moment of a day. Usually midnight, but in zones where daylight saving
    /// skips midnight (America/Santiago, America/Havana) it is 01:00, so this goes via noon.
    public static func startOfDay(year: Int, month: Int, day: Int, timeZone: TimeZone) throws -> Date {
        let noon = try makeDate(year: year, month: month, day: day, time: TimeOfDay(hour: 12, minute: 0), timeZone: timeZone)
        return gregorian(timeZone).startOfDay(for: noon)
    }

    /// The start of the day `days` days after the one `dayStart` is in. Adding days keeps the
    /// clock time, which is wrong next to a day that starts at 01:00, so snap to the start.
    public static func startOfDay(_ days: Int, after dayStart: Date, calendar: Calendar) -> Date {
        calendar.startOfDay(for: calendar.date(byAdding: .day, value: days, to: dayStart)!)
    }

    public static func makeDate(_ input: DateTimeInput, time: TimeOfDay, defaultTimeZone: TimeZone) throws -> Date {
        let zone = input.utcOffset.flatMap { TimeZone(secondsFromGMT: $0) } ?? defaultTimeZone
        return try makeDate(year: input.year, month: input.month, day: input.day, time: time, timeZone: zone)
    }

    public static func gregorian(_ timeZone: TimeZone) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return calendar
    }

    // MARK: - Helpers

    private static func parseDate(_ text: String, original: String) throws -> (Int, Int, Int) {
        let invalid = CalUtilError(
            "invalid date '\(original)': use YYYY-MM-DD or YYYY-MM-DDTHH:MM, e.g. 2026-11-06T18:00")
        let parts = text.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 3, parts[0].count == 4, parts[1].count == 2, parts[2].count == 2,
              parts.allSatisfy({ allDigits($0) })
        else { throw invalid }
        let (y, m, d) = (Int(parts[0])!, Int(parts[1])!, Int(parts[2])!)
        guard (1...12).contains(m), (1...31).contains(d) else { throw invalid }
        return (y, m, d)
    }

    private static func parseOffset(_ text: String, original: String) throws -> Int {
        let invalid = CalUtilError("invalid UTC offset in '\(original)': use e.g. +11:00, -05:00 or Z")
        let sign = text.first == "-" ? -1 : 1
        let digits = text.dropFirst().replacingOccurrences(of: ":", with: "")
        guard allDigits(digits), digits.count == 2 || digits.count == 4 else { throw invalid }
        let hours = Int(digits.prefix(2))!
        let minutes = digits.count == 4 ? Int(digits.suffix(2))! : 0
        guard hours <= 14, minutes < 60 else { throw invalid }
        return sign * (hours * 3_600 + minutes * 60)
    }

    private static func allDigits<S: Sequence>(_ s: S) -> Bool where S.Element == Character {
        var any = false
        for ch in s {
            guard ch.isASCII && ch.isNumber else { return false }
            any = true
        }
        return any
    }
}
