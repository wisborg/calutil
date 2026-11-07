import Foundation

public enum Alarm: Hashable, Sendable {
    /// Fires this many seconds before the event starts (0 = at the start).
    case beforeStart(seconds: Int)
    /// Fires at a fixed moment.
    case at(Date)

    /// "1 week before", "at the start", or "at" for a fixed moment (followed by its time).
    public var label: String {
        switch self {
        case .beforeStart(0): "at the start"
        case .beforeStart(let seconds): "\(Durations.describe(seconds)) before"
        case .at: "at"
        }
    }

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
    /// What to look up on the map; done by the caller, which then sets `place`.
    public var map: MapRequest = .none
    /// The point on the map for the location (shown as a map in Calendar).
    public var place: Place?
    /// All of the search's matches, `place` among them, for the dry run to list.
    public var matches: [Place] = []
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
            start = try DateParsing.startOfDay(year: startInput.year, month: startInput.month, day: startInput.day, timeZone: timeZone)
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
            // An offset typed in --start decides the zone a bare --end time and HH:MM alarms are
            // read in, unless --timezone names one. Z means UTC. A number that is this Mac's own
            // offset at that moment (+11:00 in Sydney) keeps the Mac's named zone, so the event
            // follows its daylight-saving rules; any other gets that fixed offset.
            if zone.value == nil, let offset = startInput.utcOffset {
                if startText.trimmingCharacters(in: .whitespaces).uppercased().hasSuffix("Z") {
                    timeZone = TimeZone(secondsFromGMT: 0)!
                } else if localTimeZone.secondsFromGMT(for: start) != offset,
                          let fixed = TimeZone(secondsFromGMT: offset) {
                    timeZone = fixed
                }
            }
        }
        let calendar = DateParsing.gregorian(timeZone)

        // End
        if o.end != nil && o.duration != nil {
            throw CalUtilError("use either --end or --duration, not both", usage: true)
        }
        let end: Date
        if let endText = nonEmpty(o.end) {
            end = try resolveEnd(endText, start: start, isAllDay: isAllDay, calendar: calendar, now: now)
        } else {
            // A template's duration only fits the kind of event it describes: a timed "2h30m"
            // doesn't suit --all-day, nor an all-day "3d" --no-all-day.
            let otherKind = isAllDay != (t?.allDay ?? false)
            let templateDuration = o.end != nil || otherKind ? nil : t?.duration
            if o.duration == nil, otherKind, let t, let ignored = nonEmpty(t.duration) {
                let kind = isAllDay ? "an all-day event" : "a timed event"
                warnings.append("ignored the template's duration \(ignored): it is for \(t.allDay ?? false ? "all-day" : "timed") events, and this is \(kind) (give --duration or --end)")
            }
            let duration = pick(o.duration, templateDuration)
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
                end = DateParsing.startOfDay(days, after: start, calendar: calendar)
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

        // An all-day event starts at midnight, so one for today counts as ahead until the day
        // is over; a timed event is past once it has started.
        let startsInPast = isAllDay ? start < calendar.startOfDay(for: now) : start < now

        // For an event still ahead, alarms that can no longer go off are left out (e.g. a
        // template's "1w" for an event in two days), so what is shown is what gets saved.
        // A past event keeps its alarms: it is being recorded or shared, not reminded of.
        if !startsInPast {
            // Sorted by when they fire, so the past ones come first.
            let cut = alarms.firstIndex { $0.fireDate(eventStart: start) >= now } ?? alarms.count
            if cut > 0 {
                let names = alarms[..<cut].map { alarm in
                    if case .at(let date) = alarm { return "at \(Summary.format(date, timeZone))" }
                    return alarm.label
                }
                alarms.removeFirst(cut)
                let what = cut == 1 ? "an alarm that is" : "alarms that are"
                let hint = !alarms.isEmpty ? ""
                    : o.alarms != nil ? " (no alarms left; give an --alarm that is still ahead)"
                    : " (no alarms left; add one with --add-alarm)"
                warnings.append("left out \(what) already in the past: \(names.joined(separator: ", "))\(hint)")
            }
        }

        // URL
        var url: URL?
        let urlText = pick(o.url, t?.url)
        if let text = urlText.value {
            guard let parsed = URL(string: text), parsed.scheme != nil else {
                throw CalUtilError("invalid URL '\(text)'\(urlText.fromTemplate ? fromTemplate : ""): include the scheme, e.g. https://")
            }
            url = parsed
        }

        if startsInPast {
            warnings.append("the event starts in the past")
        }

        // Map: --map's coordinates or search text, else the location text.
        let location = pick(o.location, t?.location).value
        var map = MapRequest.none
        if !o.noMap {
            if let text = nonEmpty(o.map), let place = Places.parseCoordinates(text) {
                if o.mapMatch != nil {
                    throw CalUtilError("--map-match picks a search match; --map \(text) is coordinates", usage: true)
                }
                map = .place(place)
            } else if let text = nonEmpty(o.map) ?? location {
                map = .search(Places.query(for: text), pick: o.mapMatch)
            } else if o.mapMatch != nil {
                throw CalUtilError("--map-match needs a --location or --map to search for", usage: true)
            }
        }

        return EventSpec(
            title: title,
            location: location,
            notes: pick(o.notes, t?.notes).value,
            url: url,
            calendarName: pick(o.calendar, t?.calendar).value,
            timeZone: timeZone,
            isAllDay: isAllDay,
            start: start,
            end: end,
            alarms: alarms,
            templateName: t?.name,
            warnings: warnings,
            map: map)
    }

    static func resolveEnd(_ text: String, start: Date, isAllDay: Bool, calendar: Calendar, now: Date) throws -> Date {
        if isAllDay {
            let input = try DateParsing.parseDateTime(text, now: now, timeZone: calendar.timeZone)
            guard input.time == nil else {
                throw CalUtilError("for an all-day event, --end is the last day, e.g. --end 2026-11-08")
            }
            let lastDay = try DateParsing.startOfDay(year: input.year, month: input.month, day: input.day,
                                                     timeZone: calendar.timeZone)
            return DateParsing.startOfDay(1, after: lastDay, calendar: calendar)
        }
        guard let time = try? DateParsing.parseTime(text) else {
            let input = try DateParsing.parseDateTime(text, now: now, timeZone: calendar.timeZone)
            guard let time = input.time else {
                throw CalUtilError("--end needs a time, e.g. \"\(text) 21:00\" or just 21:00")
            }
            return try DateParsing.makeDate(input, time: time, defaultTimeZone: calendar.timeZone)
        }
        // A bare time: on the start day if it is later on the clock than the start, else on the
        // day after. Built on that day, so a time daylight saving skips is an error there too.
        let clock = calendar.dateComponents([.hour, .minute, .second], from: start)
        var dayStart = calendar.startOfDay(for: start)
        if (time.hour, time.minute, time.second) <= (clock.hour!, clock.minute!, clock.second!) {
            dayStart = DateParsing.startOfDay(1, after: dayStart, calendar: calendar)
        }
        let day = calendar.dateComponents([.year, .month, .day], from: dayStart)
        return try DateParsing.makeDate(year: day.year!, month: day.month!, day: day.day!,
                                        time: time, timeZone: calendar.timeZone)
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

/// The text as given, or nil when it is empty or only whitespace.
func nonEmpty(_ text: String?) -> String? {
    guard let text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
    return text
}

/// The text with surrounding whitespace removed, or nil when nothing is left. For values
/// read from calendars, which often carry stray spaces and line breaks.
public func trimmedNonEmpty(_ text: String?) -> String? {
    nonEmpty(text)?.trimmingCharacters(in: .whitespacesAndNewlines)
}

extension String {
    /// Lines split on \n, \r\n or \r, with \r\n counted as one break.
    var lines: [String] {
        replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: .newlines)
    }
}
