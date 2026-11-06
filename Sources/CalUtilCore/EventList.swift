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
    public var notes: String?
    public var url: URL?
    /// `.beforeStart` with a negative value means after the start.
    public var alarms: [Alarm]
    public var isRecurring: Bool
    public var identifier: String?

    public init(title: String, calendar: String, calendarFullName: String, start: Date, end: Date,
                isAllDay: Bool = false, timeZone: TimeZone? = nil, location: String? = nil,
                notes: String? = nil, url: URL? = nil, alarms: [Alarm] = [], isRecurring: Bool = false,
                identifier: String? = nil) {
        self.title = title
        self.calendar = calendar
        self.calendarFullName = calendarFullName
        self.start = start
        self.end = end
        self.isAllDay = isAllDay
        self.timeZone = timeZone
        self.location = location
        self.notes = notes
        self.url = url
        self.alarms = alarms
        self.isRecurring = isRecurring
        self.identifier = identifier
    }
}

/// Renders `calutil list` output: events grouped by day, in the local time zone.
public enum EventList {
    static let maxTitleWidth = 40

    public static func render(_ events: [ListedEvent], from firstDay: Date, days: Int,
                              timeZone zone: TimeZone, now: Date, verbose: Bool) -> String {
        let calendar = DateParsing.gregorian(zone)
        let today = calendar.startOfDay(for: now)

        var sections: [(day: Date, dayEnd: Date, events: [ListedEvent])] = []
        for offset in 0..<days {
            let day = calendar.date(byAdding: .day, value: offset, to: firstDay)!
            let dayEnd = calendar.date(byAdding: .day, value: 1, to: day)!
            let onDay = events
                .filter { $0.start < dayEnd && max($0.end, $0.start.addingTimeInterval(1)) > day }
                .sorted { a, b in
                    if a.isAllDay != b.isAllDay { return a.isAllDay }
                    if a.start != b.start { return a.start < b.start }
                    return a.title.localizedCaseInsensitiveCompare(b.title) == .orderedAscending
                }
            if !onDay.isEmpty || days == 1 { sections.append((day, dayEnd, onDay)) }
        }

        guard !sections.isEmpty else {
            let lastDay = calendar.date(byAdding: .day, value: days - 1, to: firstDay)!
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
            let distance = calendar.dateComponents([.day], from: today, to: section.day).day ?? 99
            if let word = [-1: "yesterday", 0: "today", 1: "tomorrow"][distance] { header += " (\(word))" }
            var lines = [header]
            if section.events.isEmpty { lines.append("  No events.") }

            for event in section.events {
                var extras: [String] = []
                if !event.isAllDay, let own = event.timeZone,
                   own.secondsFromGMT(for: event.start) != zone.secondsFromGMT(for: event.start) {
                    extras.append("(\(clock(event.start, own)) \(own.identifier))")
                }
                if !event.alarms.isEmpty {
                    extras.append("⏰ " + event.alarms.map { describe($0, event: event, zone: zone) }.joined(separator: ", "))
                }
                let columns = [
                    pad(timeRange(event, day: section.day, dayEnd: section.dayEnd, zone: zone), timeWidth),
                    pad(event.title, titleWidth),
                    extras.isEmpty ? event.calendar : pad(event.calendar, calendarWidth),
                ] + extras
                lines.append("  " + columns.joined(separator: "  ").trimmingTrailingSpaces())

                if verbose {
                    let indent = String(repeating: " ", count: 2 + timeWidth + 2)
                    var details: [(String, String)] = []
                    if let location = event.location { details.append(("where", location)) }
                    if let url = event.url { details.append(("url", url.absoluteString)) }
                    if event.isRecurring { details.append(("repeats", "yes")) }
                    details.append(("calendar", event.calendarFullName))
                    if let id = event.identifier { details.append(("id", id)) }
                    if let notes = event.notes {
                        for (index, line) in notes.components(separatedBy: .newlines).enumerated() {
                            details.append((index == 0 ? "notes" : "", line))
                        }
                    }
                    let labelWidth = details.map(\.0.count).max() ?? 0
                    lines += details.map { indent + pad($0.0, labelWidth) + "  " + $0.1 }
                }
            }
            blocks.append(lines.joined(separator: "\n"))
        }
        return blocks.joined(separator: "\n\n")
    }

    /// "18:00–21:00", "all day", "22:00–…" (continues), "…–01:30" (started earlier).
    static func timeRange(_ event: ListedEvent, day: Date, dayEnd: Date, zone: TimeZone) -> String {
        if event.isAllDay { return "all day" }
        if event.start == event.end { return clock(event.start, zone) }
        let from = event.start < day ? "…" : clock(event.start, zone)
        let to = event.end > dayEnd ? "…" : clock(event.end, zone)
        return "\(from)–\(to)"
    }

    /// Compact alarm text: "1d", "2h30m", "at start", "15m after", "at 09:00".
    static func describe(_ alarm: Alarm, event: ListedEvent, zone: TimeZone) -> String {
        switch alarm {
        case .beforeStart(0): return "at start"
        case .beforeStart(let seconds) where seconds > 0: return Durations.compact(seconds)
        case .beforeStart(let seconds): return Durations.compact(-seconds) + " after"
        case .at(let date):
            let calendar = DateParsing.gregorian(zone)
            return calendar.isDate(date, inSameDayAs: event.start)
                ? "at \(clock(date, zone))"
                : "at \(Summary.format(date, zone))"
        }
    }

    static func clock(_ date: Date, _ zone: TimeZone) -> String {
        let c = DateParsing.gregorian(zone).dateComponents([.hour, .minute], from: date)
        return String(format: "%02d:%02d", c.hour!, c.minute!)
    }

    static func pad(_ text: String, _ width: Int) -> String {
        text.count >= width ? text : text.padding(toLength: width, withPad: " ", startingAt: 0)
    }
}

extension String {
    func trimmingTrailingSpaces() -> String {
        var text = self
        while text.hasSuffix(" ") { text.removeLast() }
        return text
    }
}
