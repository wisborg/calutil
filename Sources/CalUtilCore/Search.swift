import Foundation

/// `calutil search [TEXT...] [--title T] [--location L] [--notes N] [--from DAY] [--to DAY]
/// [--calendar NAME]... [--verbose]`
public struct SearchOptions: Equatable, Sendable {
    /// Words to find in the title, location or notes.
    public var text: String?
    public var title: String?
    public var location: String?
    public var notes: String?
    /// First day; nil means today.
    public var from: String?
    /// Last day; nil means a year after the first.
    public var to: String?
    /// Empty means all calendars.
    public var calendars: [String] = []
    public var verbose = false

    public init() {}

    public static func parse(_ arguments: [String]) throws -> SearchOptions {
        var options = SearchOptions()
        var scanner = ArgumentScanner(arguments, command: "search")
        var words: [String] = []
        while try scanner.next() {
            switch scanner.name {
            case "--title": options.title = trimmedNonEmpty(try scanner.single())
            case "--location": options.location = trimmedNonEmpty(try scanner.single())
            case "--notes": options.notes = trimmedNonEmpty(try scanner.single())
            case "--from": options.from = try scanner.single()
            case "--to": options.to = try scanner.single()
            case "--calendar": options.calendars.append(try scanner.value())
            case "-v", "--verbose": try scanner.flag(); options.verbose = true
            default:
                if scanner.isOption { throw scanner.unexpected() }
                words.append(scanner.argument)
            }
        }
        options.text = trimmedNonEmpty(words.joined(separator: " "))
        guard options.text != nil || options.title != nil || options.location != nil || options.notes != nil else {
            throw CalUtilError("give something to search for, e.g. calutil search dvorak (see calutil help search)", usage: true)
        }
        return options
    }
}

public enum EventSearch {
    /// The longest range searched, to keep a typo like --from 1026 from taking forever.
    public static let maxYears = 100
    /// EventKit returns at most four years of events per fetch; ask for less at a time.
    static let windowYears = 3

    /// Lowercased, without accents, with typographic quotes made plain and runs of
    /// whitespace (line breaks too) made one space, so "dvorak's" finds "Dvořák’s".
    public static func normalize(_ text: String) -> String {
        var text = text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
        for (fancy, plain) in [("’", "'"), ("‘", "'"), ("ʼ", "'"), ("“", "\""), ("”", "\"")] {
            text = text.replacingOccurrences(of: fancy, with: plain)
        }
        return text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    /// True when every word of each condition appears in its field(s).
    public static func matches(_ event: ListedEvent, _ options: SearchOptions) -> Bool {
        func has(_ query: String?, in fields: [String?]) -> Bool {
            guard let query else { return true }
            let haystack = fields.compactMap { $0 }.map(normalize).joined(separator: "\n")
            return normalize(query).split(separator: " ").allSatisfy { haystack.contains($0) }
        }
        return has(options.text, in: [event.title, event.location, event.notes])
            && has(options.title, in: [event.title])
            && has(options.location, in: [event.location])
            && has(options.notes, in: [event.notes])
    }

    /// The days to search: the start of the first and the start of the day after the last.
    public static func range(_ options: SearchOptions, now: Date, timeZone: TimeZone) throws
        -> (first: Date, end: Date, days: Int) {
        let calendar = DateParsing.gregorian(timeZone)
        func start(of text: String) throws -> Date {
            let day = try DateParsing.parseDay(text, now: now, timeZone: timeZone)
            return try DateParsing.startOfDay(year: day.year, month: day.month, day: day.day, timeZone: timeZone)
        }
        let first = try start(of: options.from ?? "today")
        let end: Date
        if let to = options.to {
            let last = try start(of: to)
            guard last >= first else {
                let hint = options.from == nil ? "; give --from too to search back in time" : ""
                throw CalUtilError("--to \(to) is before the first day searched (\(Summary.format(first, timeZone, time: false)))\(hint)")
            }
            end = DateParsing.startOfDay(1, after: last, calendar: calendar)
        } else {
            end = calendar.startOfDay(for: calendar.date(byAdding: .year, value: 1, to: first)!)
        }
        guard end <= calendar.date(byAdding: .year, value: maxYears, to: first)! else {
            throw CalUtilError("search at most \(maxYears) years at a time")
        }
        return (first, end, DateParsing.daysBetween(first, end, calendar: calendar))
    }

    /// The range cut into pieces EventKit can fetch in one go.
    public static func windows(from first: Date, to end: Date, calendar: Calendar) -> [(start: Date, end: Date)] {
        var windows: [(Date, Date)] = []
        var start = first
        while start < end {
            let next = min(calendar.date(byAdding: .year, value: windowYears, to: start)!, end)
            windows.append((start, next))
            start = next
        }
        return windows
    }

    /// "'dvorak', location 'opera house'"
    public static func describe(_ options: SearchOptions) -> String {
        var parts: [String] = []
        if let text = options.text { parts.append("'\(text)'") }
        if let title = options.title { parts.append("title '\(title)'") }
        if let location = options.location { parts.append("location '\(location)'") }
        if let notes = options.notes { parts.append("notes '\(notes)'") }
        return parts.joined(separator: ", ")
    }

    /// The matching events grouped by day, as `list` shows them, and a line saying how many.
    public static func render(_ events: [ListedEvent], options: SearchOptions, first: Date, end: Date,
                              days: Int, timeZone: TimeZone, now: Date) -> String {
        let found = events.filter { matches($0, options) }
        let calendar = DateParsing.gregorian(timeZone)
        let lastDay = DateParsing.startOfDay(days - 1, after: first, calendar: calendar)
        let span = "from \(Summary.format(first, timeZone, time: false)) to \(Summary.format(lastDay, timeZone, time: false))"
        guard !found.isEmpty else {
            return "No events matching \(describe(options)) \(span)."
        }
        let listing = EventList.render(found, from: first, days: days, timeZone: timeZone, now: now,
                                       verbose: options.verbose)
        let count = found.count == 1 ? "1 event" : "\(found.count) events"
        return listing + "\n\n\(count) matching \(describe(options)) \(span)."
    }
}
