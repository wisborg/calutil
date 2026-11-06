import Foundation

public enum Alarm: Hashable, Sendable {
    /// Fires this many seconds before the event starts (0 = at the start).
    case beforeStart(seconds: Int)
    /// Fires at a fixed moment.
    case at(Date)

    public func fireDate(eventStart: Date) -> Date {
        switch self {
        case .beforeStart(let seconds): eventStart.addingTimeInterval(-TimeInterval(seconds))
        case .at(let date): date
        }
    }
}

/// A fully resolved event, ready to print, export or save.
public struct EventSpec: Equatable, Sendable {
    public var title: String
    public var location: String?
    public var notes: String?
    public var url: URL?
    /// Calendar to save into; nil means the default calendar.
    public var calendarName: String?
    /// The event's time zone. For all-day events this is the Mac's own zone (all-day
    /// events float: they are on that date wherever you are).
    public var timeZone: TimeZone
    public var isAllDay: Bool
    public var start: Date
    /// Exclusive end. For all-day events: midnight after the last day.
    public var end: Date
    /// Sorted by when they fire.
    public var alarms: [Alarm]
    public var templateName: String?
    /// Things worth telling the user that don't stop the event being created.
    public var warnings: [String]
}

public enum Resolver {
    /// Combines the command line with a template (command line wins) and applies defaults.
    public static func resolve(options o: AddOptions, template t: Template?, now: Date = Date(),
                               localTimeZone: TimeZone = .current) throws -> EventSpec {
        var warnings: [String] = []
        let fromTemplate = t.map { " (from template '\($0.name)')" } ?? ""

        /// A command-line value (even an empty one, which clears) beats the template's.
        func pick(_ cli: String?, _ template: String?) -> (value: String?, fromTemplate: Bool) {
            if let cli { return (nonEmpty(cli), false) }
            return (nonEmpty(template), true)
        }
        func inTemplate<T>(_ isTemplate: Bool, _ body: () throws -> T) throws -> T {
            do { return try body() } catch let error as CalUtilError where isTemplate {
                throw CalUtilError(error.message + fromTemplate)
            }
        }

        guard let title = pick(o.title, t?.title).value else {
            throw CalUtilError("missing --title", usage: true)
        }
        let isAllDay = o.allDay ?? t?.allDay ?? false

        // Time zone
        var timeZone = localTimeZone
        let zone = pick(o.timezone, t?.timezone)
        if let name = zone.value {
            guard let parsed = TimeZone(identifier: name) else {
                throw CalUtilError("unknown time zone '\(name)'\(zone.fromTemplate ? fromTemplate : ""): use a name such as Australia/Sydney or Europe/Copenhagen")
            }
            if isAllDay {
                if !zone.fromTemplate { warnings.append("--timezone is ignored for all-day events") }
            } else {
                timeZone = parsed
            }
        }
        let calendar = DateParsing.gregorian(timeZone)

        // Start
        guard let startText = nonEmpty(o.start) else {
            throw CalUtilError("missing --start, e.g. --start 2026-11-06T18:00", usage: true)
        }
        let startInput = try DateParsing.parseDateTime(startText, now: now, timeZone: timeZone)
        let startIsDate = DateParsing.looksLikeDate(startText)
        let start: Date
        if isAllDay {
            guard startInput.time == nil else {
                let dayOnly = startIsDate ? String(startText.prefix(10)) : String(startText.split(separator: " ")[0])
                throw CalUtilError("an all-day event takes a day without a time, e.g. --start \(dayOnly)")
            }
            start = try DateParsing.makeDate(startInput, time: TimeOfDay(hour: 0, minute: 0), defaultTimeZone: timeZone)
        } else {
            var time = startInput.time
            if time == nil, let templateTime = nonEmpty(t?.time) {
                time = try inTemplate(true) { try DateParsing.parseTime(templateTime) }
            }
            guard let time else {
                let example = startIsDate ? "\(startText)T18:00" : "\"\(startText) 18:00\""
                throw CalUtilError("--start needs a time, e.g. \(example) (or add --all-day)")
            }
            start = try DateParsing.makeDate(startInput, time: time, defaultTimeZone: timeZone)
        }

        // End
        if o.end != nil && o.duration != nil {
            throw CalUtilError("use either --end or --duration, not both", usage: true)
        }
        let end: Date
        if let endText = nonEmpty(o.end) {
            end = try resolveEnd(endText, start: start, isAllDay: isAllDay, calendar: calendar, now: now)
        } else {
            let duration = pick(o.duration, o.end != nil ? nil : t?.duration)
            let seconds = try inTemplate(duration.fromTemplate) {
                try duration.value.map(Durations.parse)
            }
            if isAllDay {
                let days: Int
                if let seconds {
                    guard seconds > 0, seconds % 86_400 == 0 else {
                        throw CalUtilError("an all-day event lasts whole days, e.g. --duration 1d or 3d\(duration.fromTemplate ? fromTemplate : "")")
                    }
                    days = seconds / 86_400
                } else {
                    days = 1
                }
                end = calendar.date(byAdding: .day, value: days, to: start)!
            } else {
                end = start.addingTimeInterval(TimeInterval(seconds ?? 3_600))
            }
        }
        guard end > start else {
            throw CalUtilError("the event must end after it starts")
        }

        // Alarms
        var alarmTexts: [(text: String, fromTemplate: Bool)] = []
        if !o.noAlarms {
            if let alarms = o.alarms {
                alarmTexts += alarms.map { ($0, false) }
            } else {
                alarmTexts += (t?.alarms ?? []).map { ($0, true) }
            }
        }
        alarmTexts += o.addAlarms.map { ($0, false) }
        var alarms: [Alarm] = []
        for (text, isTemplate) in alarmTexts {
            let alarm = try inTemplate(isTemplate) {
                try parseAlarm(text, start: start, timeZone: timeZone)
            }
            if !alarms.contains(alarm) { alarms.append(alarm) }
        }
        alarms.sort { $0.fireDate(eventStart: start) < $1.fireDate(eventStart: start) }

        // URL
        var url: URL?
        let urlText = pick(o.url, t?.url)
        if let text = urlText.value {
            guard let parsed = URL(string: text), parsed.scheme != nil else {
                throw CalUtilError("invalid URL '\(text)'\(urlText.fromTemplate ? fromTemplate : ""): include the scheme, e.g. https://")
            }
            url = parsed
        }

        if start < now {
            warnings.append("the event starts in the past")
        }
        // Alarms that can no longer go off are left out (e.g. a template's "1w" for an
        // event in two days), so what is shown is what gets saved.
        let pastAlarms = alarms.filter { $0.fireDate(eventStart: start) < now }
        if !pastAlarms.isEmpty {
            alarms.removeAll { $0.fireDate(eventStart: start) < now }
            let names = pastAlarms.map { alarm -> String in
                switch alarm {
                case .beforeStart(0): "at the start"
                case .beforeStart(let seconds): "\(Durations.describe(seconds)) before"
                case .at(let date): "at \(Summary.format(date, timeZone))"
                }
            }
            let what = pastAlarms.count == 1 ? "an alarm that is" : "alarms that are"
            warnings.append("left out \(what) already in the past: \(names.joined(separator: ", "))"
                + (alarms.isEmpty && start >= now ? " (no alarms left; add one with --add-alarm)" : ""))
        }

        return EventSpec(
            title: title,
            location: pick(o.location, t?.location).value,
            notes: pick(o.notes, t?.notes).value,
            url: url,
            calendarName: pick(o.calendar, t?.calendar).value,
            timeZone: timeZone,
            isAllDay: isAllDay,
            start: start,
            end: end,
            alarms: alarms,
            templateName: t?.name,
            warnings: warnings)
    }

    static func resolveEnd(_ text: String, start: Date, isAllDay: Bool, calendar: Calendar, now: Date) throws -> Date {
        if isAllDay {
            let input = try DateParsing.parseDateTime(text, now: now, timeZone: calendar.timeZone)
            guard input.time == nil else {
                throw CalUtilError("for an all-day event, --end is the last day, e.g. --end 2026-11-08")
            }
            let lastDay = try DateParsing.makeDate(input, time: TimeOfDay(hour: 0, minute: 0),
                                                   defaultTimeZone: calendar.timeZone)
            return calendar.date(byAdding: .day, value: 1, to: lastDay)!
        }
        guard let time = try? DateParsing.parseTime(text) else {
            let input = try DateParsing.parseDateTime(text, now: now, timeZone: calendar.timeZone)
            guard let time = input.time else {
                throw CalUtilError("--end needs a time, e.g. \"\(text) 21:00\" or just 21:00")
            }
            return try DateParsing.makeDate(input, time: time, defaultTimeZone: calendar.timeZone)
        }
        // A bare time: on the start day, or the day after if that is not after the start.
        let day = calendar.dateComponents([.year, .month, .day], from: start)
        var end = try DateParsing.makeDate(year: day.year!, month: day.month!, day: day.day!,
                                           time: time, timeZone: calendar.timeZone)
        if end <= start { end = calendar.date(byAdding: .day, value: 1, to: end)! }
        return end
    }

    static func parseAlarm(_ raw: String, start: Date, timeZone: TimeZone) throws -> Alarm {
        let text = raw.trimmingCharacters(in: .whitespaces)
        let invalid = CalUtilError(
            "invalid alarm '\(raw)': use a time before the start (15m, 2h, 1d, 1h30m), a time on the event day (09:00), or a date and time (2026-11-05T09:00)")
        if DateParsing.looksLikeDate(text) {
            let input = try DateParsing.parseDateTime(text)
            guard let time = input.time else {
                throw CalUtilError("alarm '\(raw)' needs a time, e.g. \(text)T09:00")
            }
            return .at(try DateParsing.makeDate(input, time: time, defaultTimeZone: timeZone))
        }
        if text.contains(":") {
            guard let time = try? DateParsing.parseTime(text) else { throw invalid }
            let day = DateParsing.gregorian(timeZone).dateComponents([.year, .month, .day], from: start)
            return .at(try DateParsing.makeDate(year: day.year!, month: day.month!, day: day.day!,
                                                time: time, timeZone: timeZone))
        }
        guard let seconds = try? Durations.parse(text) else { throw invalid }
        return .beforeStart(seconds: seconds)
    }
}

func nonEmpty(_ text: String?) -> String? {
    guard let text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
    return text
}
