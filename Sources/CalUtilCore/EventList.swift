import Foundation

/// An event as read from a calendar, independent of EventKit.
public struct ListedEvent: Equatable, Sendable {
    public var title: String
    /// Calendar name as shown in the list.
    public var calendar: String
    /// "Account/Name", for --verbose.
    public var calendarFullName: String
    public var start: Date
    /// For all-day events, any moment on the last day (EventKit gives 23:59:59).
    public var end: Date
    public var isAllDay: Bool
    /// The event's own zone; nil for floating events.
    public var timeZone: TimeZone?
    public var location: String?
    /// Where the location is on the map, when the event has that.
    public var place: Place?
    public var notes: String?
    public var url: URL?
    /// `.beforeStart` with a negative value means after the start.
    public var alarms: [Alarm]
    public var isRecurring: Bool
    public var identifier: String?

    public init(title: String, calendar: String, calendarFullName: String, start: Date, end: Date,
                isAllDay: Bool = false, timeZone: TimeZone? = nil, location: String? = nil,
                place: Place? = nil, notes: String? = nil, url: URL? = nil, alarms: [Alarm] = [], isRecurring: Bool = false,
                identifier: String? = nil) {
        self.title = title
        self.calendar = calendar
        self.calendarFullName = calendarFullName
        self.start = start
        self.end = end
        self.isAllDay = isAllDay
        self.timeZone = timeZone
        self.location = location
        self.place = place
        self.notes = notes
        self.url = url
        self.alarms = alarms
        self.isRecurring = isRecurring
        self.identifier = identifier
    }
}

/// Renders `calutil list` output: events grouped by day, in the local time zone.
public enum EventList {
    /// Longer titles are cut short with "…" (and shown in full with --verbose).
    static let maxTitleWidth = 40

    public static func render(_ events: [ListedEvent], from firstDay: Date, days: Int,
                              timeZone zone: TimeZone, now: Date, verbose: Bool) -> String {
        let calendar = DateParsing.gregorian(zone)
        // A title must fit on its row.
        let events = events.map { event in
            var event = event
            event.title = event.title.lines
                .map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }.joined(separator: " ")
            return event
        }

        // One pass over the days: events sorted by start once, and a running list of the ones
        // that have started and not yet ended.
        let byStart = events.sorted { a, b in
            if a.start != b.start { return a.start < b.start }
            return a.title.localizedCaseInsensitiveCompare(b.title) == .orderedAscending
        }
        var next = 0
        var active: [ListedEvent] = []
        var sections: [(day: Date, dayEnd: Date, events: [ListedEvent])] = []
        for offset in 0..<days {
            let day = DateParsing.startOfDay(offset, after: firstDay, calendar: calendar)
            let dayEnd = DateParsing.startOfDay(1, after: day, calendar: calendar)
            while next < byStart.count, byStart[next].start < dayEnd {
                active.append(byStart[next])
                next += 1
            }
            // A zero-length event still belongs to the day it is on.
            active.removeAll { max($0.end, $0.start.addingTimeInterval(1)) <= day }
            let onDay = active.filter(\.isAllDay) + active.filter { !$0.isAllDay }
            if !onDay.isEmpty || days == 1 { sections.append((day, dayEnd, onDay)) }
        }

        guard !sections.isEmpty else {
            let lastDay = DateParsing.startOfDay(days - 1, after: firstDay, calendar: calendar)
            return "No events from \(Summary.format(firstDay, zone, time: false)) to \(Summary.format(lastDay, zone, time: false))."
        }

        // One set of column widths for the whole listing.
        let shown = sections.flatMap(\.events)
        let titleWidth = min(shown.map(\.title.count).max() ?? 0, maxTitleWidth)
        let calendarWidth = shown.map(\.calendar.count).max() ?? 0
        let timeWidth = 11  // "22:00–23:30"

        var blocks: [String] = []
        for section in sections {
            var header = Summary.format(section.day, zone, time: false)
            let distance = DateParsing.daysBetween(now, section.day, calendar: calendar)
            if let word = [-1: "yesterday", 0: "today", 1: "tomorrow"][distance] { header += " (\(word))" }
            var lines = [header]
            if section.events.isEmpty { lines.append("  No events.") }

            for event in section.events {
                var extras: [String] = []
                if !event.isAllDay, let own = event.timeZone,
                   own.secondsFromGMT(for: event.start) != zone.secondsFromGMT(for: event.start) {
                    extras.append("(\(clock(event.start, DateParsing.gregorian(own))) \(own.identifier))")
                }
                if !event.alarms.isEmpty {
                    extras.append("⏰ " + event.alarms.map { describe($0, event: event, calendar: calendar) }.joined(separator: ", "))
                }
                let columns = [
                    timeRange(event, day: section.day, dayEnd: section.dayEnd, calendar: calendar).padded(to: timeWidth),
                    shorten(event.title, to: titleWidth).padded(to: titleWidth),
                    extras.isEmpty ? event.calendar : event.calendar.padded(to: calendarWidth),
                ] + extras
                lines.append("  " + columns.joined(separator: "  ").trimmingTrailingSpaces())

                if verbose {
                    let indent = String(repeating: " ", count: 2 + timeWidth + 2)
                    var details: [(String, String)] = []
                    if event.title.count > titleWidth { details.append(("title", event.title)) }
                    if !event.isAllDay {
                        details.append(("zone", event.timeZone?.identifier ?? "none (floating: same clock time in any zone)"))
                    }
                    if let location = event.location { details.append(("where", location)) }
                    if let place = event.place { details.append(("map", place.coordinates)) }
                    if let url = event.url { details.append(("url", url.absoluteString)) }
                    if event.isRecurring { details.append(("repeats", "yes")) }
                    details.append(("calendar", event.calendarFullName))
                    if let id = event.identifier { details.append(("id", id)) }
                    if let notes = event.notes { details.append(("notes", notes)) }
                    let labelWidth = details.map(\.0.count).max() ?? 0
                    // Values can span lines (notes, and locations from Maps); keep them indented.
                    for (label, value) in details {
                        for (index, line) in value.lines.enumerated() {
                            lines.append(indent + (index == 0 ? label : "").padded(to: labelWidth) + "  " + line)
                        }
                    }
                }
            }
            blocks.append(lines.joined(separator: "\n"))
        }
        return blocks.joined(separator: "\n\n")
    }

    /// "18:00–21:00", "all day", "22:00–…" (continues), "…–01:30" (started earlier).
    static func timeRange(_ event: ListedEvent, day: Date, dayEnd: Date, calendar: Calendar) -> String {
        if event.isAllDay { return "all day" }
        if event.start == event.end { return clock(event.start, calendar) }
        let from = event.start < day ? "…" : clock(event.start, calendar)
        let to = event.end > dayEnd ? "…" : clock(event.end, calendar)
        return "\(from)–\(to)"
    }

    /// Compact alarm text: "1d", "2h30m", "at start", "15m after", "at 09:00".
    static func describe(_ alarm: Alarm, event: ListedEvent, calendar: Calendar) -> String {
        switch alarm {
        case .beforeStart(0): return "at start"
        case .beforeStart(let seconds) where seconds > 0: return Durations.compact(seconds)
        case .beforeStart(let seconds): return Durations.compact(-seconds) + " after"
        case .at(let date):
            return calendar.isDate(date, inSameDayAs: event.start)
                ? "at \(clock(date, calendar))"
                : "at \(Summary.format(date, calendar.timeZone))"
        }
    }

    static func clock(_ date: Date, _ calendar: Calendar) -> String {
        let c = calendar.dateComponents([.hour, .minute], from: date)
        return String(format: "%02d:%02d", c.hour!, c.minute!)
    }

    static func shorten(_ text: String, to width: Int) -> String {
        text.count <= width ? text : String(text.prefix(width - 1)) + "…"
    }
}

extension String {
    /// The text with spaces added to make it `width` characters (never cut short).
    public func padded(to width: Int) -> String {
        count >= width ? self : padding(toLength: width, withPad: " ", startingAt: 0)
    }

    func trimmingTrailingSpaces() -> String {
        var text = self
        while text.hasSuffix(" ") { text.removeLast() }
        return text
    }
}
