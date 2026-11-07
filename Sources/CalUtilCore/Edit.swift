import Foundation

/// Which event `edit` and `delete` work on: an id, or a search that must find exactly one.
public struct EventSelection: Equatable, Sendable {
    /// The event id `list --verbose` and `search --verbose` show.
    public var id: String?
    /// The search's words and fields (`--match`, `--match-title`, ...), `--from`/`--to`,
    /// and `--match-calendar`.
    public var search = SearchOptions()
    /// The day of the occurrence, for a repeating event; with a search, the day searched.
    public var on: String?

    public init() {}

    public var isSearch: Bool {
        search.text != nil || search.title != nil || search.location != nil || search.notes != nil
    }

    /// Takes the scanner's option if it is a selection option.
    mutating func take(_ scanner: inout ArgumentScanner) throws -> Bool {
        switch scanner.name {
        case "--id": id = trimmedNonEmpty(try scanner.single())
        case "--on": on = try scanner.single()
        case "--match": search.text = trimmedNonEmpty(try scanner.single())
        case "--match-title": search.title = trimmedNonEmpty(try scanner.single())
        case "--match-location": search.location = trimmedNonEmpty(try scanner.single())
        case "--match-notes": search.notes = trimmedNonEmpty(try scanner.single())
        case "--match-calendar": search.calendars.append(try scanner.value())
        case "--from": search.from = try scanner.single()
        case "--to": search.to = try scanner.single()
        default: return false
        }
        return true
    }

    func check(_ command: String) throws {
        if id != nil && isSearch {
            throw CalUtilError("use either --id or --match…, not both", usage: true)
        }
        if id == nil && !isSearch {
            throw CalUtilError("say which event: --id ID (see calutil search --verbose) or --match TEXT (see calutil help \(command))", usage: true)
        }
        if id != nil && (search.from != nil || search.to != nil || !search.calendars.isEmpty) {
            throw CalUtilError("--from, --to and --match-calendar narrow a --match search; with --id use --on DAY for one occurrence", usage: true)
        }
        if on != nil && (search.from != nil || search.to != nil) {
            throw CalUtilError("use either --on or --from/--to, not both", usage: true)
        }
    }

    /// The search to run: with --on, just that day.
    public var searchOptions: SearchOptions {
        var options = search
        if let on { options.from = on; options.to = on }
        return options
    }
}

/// `calutil edit SELECTION [changes] [--future] [--save]`
public struct EditOptions: Equatable, Sendable {
    public var selection = EventSelection()
    /// The new values, given as for `add` (only those given change).
    public var changes = AddOptions()
    /// Also change the later occurrences of a repeating event.
    public var future = false
    /// With --timezone: keep the moment the event happens, not its clock time.
    public var keepTime = false
    public var save = false

    public init() {}

    public static func parse(_ arguments: [String]) throws -> EditOptions {
        var options = EditOptions()
        var scanner = ArgumentScanner(arguments, command: "edit", aliases: ["--tz": "--timezone"])
        while try scanner.next() {
            switch scanner.name {
            case "--save": try scanner.flag(); options.save = true
            case "--dry-run": try scanner.flag(); options.save = false
            case "--future": try scanner.flag(); options.future = true
            case "--keep-time": try scanner.flag(); options.keepTime = true
            default:
                if try options.selection.take(&scanner) { continue }
                if try options.changes.takeField(&scanner) { continue }
                throw scanner.unexpected()
            }
        }
        try options.selection.check("edit")
        try options.changes.checkFields()
        if options.keepTime {
            guard options.changes.timezone != nil else {
                throw CalUtilError("--keep-time goes with --timezone: it keeps the moment while the zone changes", usage: true)
            }
            guard options.changes.start == nil else {
                throw CalUtilError("--keep-time keeps the start, so it can't be combined with --start", usage: true)
            }
        }
        guard options.changes.hasFields else {
            throw CalUtilError("nothing to change: give the new values, e.g. --title, --start or --location (see calutil help edit)", usage: true)
        }
        return options
    }
}

/// `calutil delete SELECTION [--future] [--yes]`
public struct DeleteOptions: Equatable, Sendable {
    public var selection = EventSelection()
    public var future = false
    public var confirmed = false

    public init() {}

    public static func parse(_ arguments: [String]) throws -> DeleteOptions {
        var options = DeleteOptions()
        var scanner = ArgumentScanner(arguments, command: "delete")
        while try scanner.next() {
            switch scanner.name {
            case "--yes": try scanner.flag(); options.confirmed = true
            case "--dry-run": try scanner.flag(); options.confirmed = false
            case "--future": try scanner.flag(); options.future = true
            default:
                if try options.selection.take(&scanner) { continue }
                throw scanner.unexpected()
            }
        }
        try options.selection.check("delete")
        return options
    }
}

extension AddOptions {
    /// True when any of the event's settings was given.
    var hasFields: Bool {
        title != nil || location != nil || notes != nil || url != nil || calendar != nil || timezone != nil
            || start != nil || end != nil || duration != nil || allDay != nil || alarms != nil
            || !addAlarms.isEmpty || noAlarms || map != nil || mapMatch != nil || noMap
    }
}

public enum Editor {
    /// The event with the changes made. Only what is given changes: moving the start keeps the
    /// length, a new location is looked up on the map (by the caller, from `map`), and the
    /// existing alarms are kept unless replaced.
    /// `keepTime` (--keep-time): a new --timezone keeps the moment rather than the clock time.
    public static func apply(_ o: AddOptions, to current: EventSpec, now: Date = Date(),
                             localTimeZone: TimeZone = .current, keepTime: Bool = false) throws -> EventSpec {
        var event = current
        event.warnings = []
        event.map = .none
        event.matches = []

        if let title = o.title {
            guard nonEmpty(title) != nil else { throw CalUtilError("an event needs a title") }
            event.title = title
        }
        if let location = o.location { event.location = nonEmpty(location) }
        if let notes = o.notes { event.notes = nonEmpty(notes) }
        if let text = o.url {
            if let text = nonEmpty(text) {
                guard let url = URL(string: text), url.scheme != nil else {
                    throw CalUtilError("invalid URL '\(text)': include the scheme, e.g. https://")
                }
                event.url = url
            } else {
                event.url = nil
            }
        }
        if let calendar = o.calendar {
            guard nonEmpty(calendar) != nil else { throw CalUtilError("--calendar needs a calendar's name") }
            event.calendarName = calendar
        }

        try applyTimes(o, current: current, to: &event, now: now, localTimeZone: localTimeZone, keepTime: keepTime)
        try applyAlarms(o, to: &event, now: now)
        try applyMap(o, current: current, to: &event)
        return event
    }

    private static func applyTimes(_ o: AddOptions, current: EventSpec, to event: inout EventSpec,
                                   now: Date, localTimeZone: TimeZone, keepTime: Bool) throws {
        let isAllDay = o.allDay ?? current.isAllDay
        if keepTime && isAllDay {
            throw CalUtilError("--keep-time is for timed events; an all-day event has no time to keep")
        }
        var zone = current.isAllDay ? localTimeZone : current.timeZone
        if let name = o.timezone {
            guard let text = nonEmpty(name), let parsed = TimeZone(identifier: text) else {
                throw CalUtilError("unknown time zone '\(name)': use a name such as Australia/Sydney or Europe/Copenhagen")
            }
            if isAllDay { event.warnings.append("--timezone is ignored for all-day events") } else { zone = parsed }
        }
        let oldCalendar = DateParsing.gregorian(current.timeZone)

        let start: Date
        let end: Date
        if isAllDay {
            zone = localTimeZone  // all-day events float
            if let text = nonEmpty(o.start) {
                let input = try DateParsing.parseDateTime(text, now: now, timeZone: zone)
                guard input.time == nil else {
                    throw CalUtilError("an all-day event takes a day without a time, e.g. --start \(String(text.prefix(10)))")
                }
                start = try DateParsing.startOfDay(year: input.year, month: input.month, day: input.day, timeZone: zone)
            } else {
                let day = oldCalendar.dateComponents([.year, .month, .day], from: current.start)
                start = try DateParsing.startOfDay(year: day.year!, month: day.month!, day: day.day!, timeZone: zone)
            }
            let calendar = DateParsing.gregorian(zone)
            if let text = nonEmpty(o.end) {
                end = try Resolver.resolveEnd(text, start: start, isAllDay: true, calendar: calendar, now: now)
            } else {
                let days: Int
                if let text = nonEmpty(o.duration) {
                    let seconds = try Durations.parse(text)
                    guard seconds > 0, seconds % 86_400 == 0 else {
                        throw CalUtilError("an all-day event lasts whole days, e.g. --duration 1d or 3d")
                    }
                    days = seconds / 86_400
                } else if current.isAllDay {
                    days = DateParsing.daysBetween(current.start, current.end, calendar: oldCalendar)
                } else {
                    // The days the timed event touched.
                    days = DateParsing.daysBetween(current.start, current.end.addingTimeInterval(-1), calendar: oldCalendar) + 1
                }
                end = DateParsing.startOfDay(max(days, 1), after: start, calendar: calendar)
            }
        } else {
            if let text = nonEmpty(o.start) {
                let input = try DateParsing.parseDateTime(text, now: now, timeZone: zone)
                // A day alone moves the event to that day at the same time.
                let time = try input.time ?? {
                    guard !current.isAllDay else {
                        let example = DateParsing.looksLikeDate(text) ? "\(text)T18:00" : "\"\(text) 18:00\""
                        throw CalUtilError("give --start a time to turn an all-day event into a timed one, e.g. --start \(example)")
                    }
                    let c = oldCalendar.dateComponents([.hour, .minute, .second], from: current.start)
                    return TimeOfDay(hour: c.hour!, minute: c.minute!, second: c.second!)
                }()
                start = try DateParsing.makeDate(input, time: time, defaultTimeZone: zone)
                if o.timezone == nil, let typed = Resolver.typedZone(text, input, start: start, localTimeZone: localTimeZone) {
                    zone = typed
                }
            } else if current.isAllDay {
                throw CalUtilError("give --start with a time to turn an all-day event into a timed one, e.g. --start \(isoDay(current.start, oldCalendar))T18:00")
            } else if keepTime {
                // The same moment, shown in the new zone: 00:00 GMT becomes 13:00 in Auckland.
                start = current.start
            } else if zone.identifier != current.timeZone.identifier || zone.secondsFromGMT() != current.timeZone.secondsFromGMT() {
                // A new zone keeps the clock time: 19:00 stays 19:00, now in the new zone.
                let c = oldCalendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: current.start)
                start = try DateParsing.makeDate(year: c.year!, month: c.month!, day: c.day!,
                                                 time: TimeOfDay(hour: c.hour!, minute: c.minute!, second: c.second!), timeZone: zone)
            } else {
                start = current.start
            }
            let calendar = DateParsing.gregorian(zone)
            if let text = nonEmpty(o.end) {
                end = try Resolver.resolveEnd(text, start: start, isAllDay: false, calendar: calendar, now: now)
            } else if let text = nonEmpty(o.duration) {
                end = start.addingTimeInterval(TimeInterval(try Durations.parse(text)))
            } else if current.isAllDay {
                end = start.addingTimeInterval(3_600)
            } else {
                end = start.addingTimeInterval(current.end.timeIntervalSince(current.start))
            }
        }
        guard end > start else { throw CalUtilError("the event must end after it starts") }
        event.isAllDay = isAllDay
        event.timeZone = zone
        event.start = start
        event.end = end
    }

    private static func isoDay(_ date: Date, _ calendar: Calendar) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year!, c.month!, c.day!)
    }

    private static func applyAlarms(_ o: AddOptions, to event: inout EventSpec, now: Date) throws {
        var alarms = o.noAlarms ? [] : event.alarms
        var added: [Alarm] = []
        for text in (o.alarms ?? []) + o.addAlarms {
            let alarm = try Resolver.parseAlarm(text, start: event.start, timeZone: event.timeZone)
            if !added.contains(alarm) { added.append(alarm) }
        }
        if o.alarms != nil { alarms = [] }
        // As for add: a new alarm that can no longer go off, for an event still ahead, is left out.
        let calendar = DateParsing.gregorian(event.timeZone)
        let ahead = event.isAllDay ? event.start >= calendar.startOfDay(for: now) : event.start >= now
        let past = ahead ? added.filter { $0.fireDate(eventStart: event.start) < now } : []
        if !past.isEmpty {
            let names = past.map { alarm in
                if case .at(let date) = alarm { return "at \(Summary.format(date, event.timeZone))" }
                return alarm.label
            }
            event.warnings.append("left out \(past.count == 1 ? "an alarm that is" : "alarms that are") already in the past: \(names.joined(separator: ", "))")
        }
        for alarm in added where !past.contains(alarm) && !alarms.contains(alarm) { alarms.append(alarm) }
        alarms.sort { $0.fireDate(eventStart: event.start) < $1.fireDate(eventStart: event.start) }
        event.alarms = alarms
    }

    private static func applyMap(_ o: AddOptions, current: EventSpec, to event: inout EventSpec) throws {
        if o.noMap || o.map == "" {
            event.place = nil
        } else if let text = nonEmpty(o.map) {
            if let place = Places.parseCoordinates(text) {
                if o.mapMatch != nil {
                    throw CalUtilError("--map-match picks a search match; --map \(text) is coordinates", usage: true)
                }
                event.map = .place(place)
            } else {
                event.map = .search(Places.query(for: text), pick: o.mapMatch)
            }
        } else if o.location != nil {
            // A new location gets a new map point (none when the location is cleared).
            event.place = nil
            if let location = event.location {
                event.map = .search(Places.query(for: location), pick: o.mapMatch)
            } else if o.mapMatch != nil {
                throw CalUtilError("--map-match needs a location or --map to search for", usage: true)
            }
        } else if o.mapMatch != nil {
            throw CalUtilError("--map-match picks from a search: give a new --location or --map too", usage: true)
        }
    }

    /// The fields that differ, as `-` old and `+` new lines under each label.
    public static func differences(from old: EventSpec, to new: EventSpec, localTimeZone: TimeZone = .current,
                                   listMatches: Bool = false) -> String? {
        var skip: Set<String> = ["Your time", "Template"]
        // The same alarms for the same start go off at the same moments, even if a new zone
        // shows those moments differently.
        if old.alarms == new.alarms && old.start == new.start { skip.formUnion(["Alarm", "Alarms"]) }
        let before = Summary.fields(old, localTimeZone: localTimeZone, listMatches: false).filter { !skip.contains($0.label) }
        let after = Summary.fields(new, localTimeZone: localTimeZone, listMatches: listMatches).filter { !skip.contains($0.label) }
        func value(_ label: String, in fields: [(label: String, value: String)]) -> String? {
            fields.first { $0.label == label }?.value
        }
        var labels = after.map(\.label)
        for (index, field) in before.enumerated() where !labels.contains(field.label) {
            // Keep a field that is gone near where it was.
            let at = before[..<index].compactMap { labels.firstIndex(of: $0.label) }.last.map { $0 + 1 } ?? 0
            labels.insert(field.label, at: min(at, labels.count))
        }
        var rows: [(label: String, value: String)] = []
        for label in labels {
            let was = value(label, in: before), now = value(label, in: after)
            guard was != now else { continue }
            let minus = (was ?? "(none)").lines.map { "- " + $0 }
            let plus = (now ?? "(none)").lines.map { "+ " + $0 }
            rows.append((label, (minus + plus).joined(separator: "\n")))
        }
        return rows.isEmpty ? nil : Summary.table(rows)
    }

    /// "“Dentist” on Tue 1 Dec 2026 09:00 in iCloud/Home"
    public static func describe(_ event: EventSpec) -> String {
        let when = Summary.format(event.start, event.timeZone, time: !event.isAllDay)
        return "“\(event.title)” on \(when)" + (event.calendarName.map { " in \($0)" } ?? "")
    }
}
