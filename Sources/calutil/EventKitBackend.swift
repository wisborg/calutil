import CalUtilCore
import CoreGraphics
import EventKit
import Foundation

enum EventKitBackend {
    /// Returns an event store with full Calendar access, asking for it the first time.
    static func authorizedStore() throws -> EKEventStore {
        let settingsHint = "Allow it in System Settings → Privacy & Security → Calendars → calutil, then try again."
        switch EKEventStore.authorizationStatus(for: .event) {
        case .fullAccess:
            return EKEventStore()
        case .notDetermined:
            final class Outcome: @unchecked Sendable {
                var granted = false
                var error: Error?
            }
            let outcome = Outcome()
            let done = DispatchSemaphore(value: 0)
            EKEventStore().requestFullAccessToEvents { granted, error in
                outcome.granted = granted
                outcome.error = error
                done.signal()
            }
            done.wait()
            guard outcome.granted else {
                let reason = outcome.error.map { " (\($0.localizedDescription))" } ?? ""
                throw CalUtilError("calutil was not given access to your calendars\(reason). \(settingsHint)")
            }
            // A fresh store sees the calendars that the new permission unlocked.
            return EKEventStore()
        case .writeOnly:
            throw CalUtilError("calutil only has \"add events only\" access, but needs full access to find calendars by name. \(settingsHint)")
        case .denied, .restricted:
            throw CalUtilError("calutil is not allowed to use your calendars. \(settingsHint)")
        @unknown default:
            throw CalUtilError("unexpected Calendar permission state. \(settingsHint)")
        }
    }

    /// Adds the event; returns the calendar it went into.
    static func save(_ spec: EventSpec) throws -> EKCalendar {
        let store = try authorizedStore()
        let calendar = try findCalendar(named: spec.calendarName, in: store)

        let event = EKEvent(eventStore: store)
        event.calendar = calendar
        event.title = spec.title
        event.location = spec.location
        event.notes = spec.notes
        event.url = spec.url
        event.isAllDay = spec.isAllDay
        event.startDate = spec.start
        if spec.isAllDay {
            event.timeZone = nil  // floating: the same date wherever you are
            event.endDate = spec.end.addingTimeInterval(-1)  // EventKit's all-day end is inclusive
        } else {
            event.timeZone = spec.timeZone
            event.endDate = spec.end
        }
        event.alarms = spec.alarms.map { alarm in
            switch alarm {
            case .beforeStart(let seconds): EKAlarm(relativeOffset: -TimeInterval(seconds))
            case .at(let date): EKAlarm(absoluteDate: date)
            }
        }
        if let place = spec.place {
            // Its title becomes the location text, and changing that text afterwards would
            // drop the map, so this comes last.
            let structured = EKStructuredLocation(title: spec.location ?? place.locationText)
            structured.geoLocation = CLLocation(latitude: place.latitude, longitude: place.longitude)
            event.structuredLocation = structured
        }

        do {
            try store.save(event, span: .thisEvent, commit: true)
        } catch {
            throw CalUtilError("Calendar refused the event: \(error.localizedDescription)")
        }
        return calendar
    }

    static func listCalendars(verbose: Bool) throws -> String {
        let store = try authorizedStore()
        let defaultID = store.defaultCalendarForNewEvents?.calendarIdentifier
        let calendars = store.calendars(for: .event).sorted { qualifiedName($0) < qualifiedName($1) }
        guard !calendars.isEmpty else { return "No calendars found." }
        if verbose {
            return calendars.map { describe($0, isDefault: $0.calendarIdentifier == defaultID, in: store) }
                .joined(separator: "\n\n")
        }
        let duplicated = Set(Dictionary(grouping: calendars, by: qualifiedName).filter { $1.count > 1 }.keys)
        let width = calendars.map { qualifiedName($0).count }.max() ?? 0
        var lines = calendars.map { calendar in
            var notes = flags(calendar, isDefault: calendar.calendarIdentifier == defaultID)
            let name = qualifiedName(calendar)
            if duplicated.contains(name) {
                if let color = hexColor(calendar) { notes.append(color) }
                notes.append("id \(calendar.calendarIdentifier)")
            }
            return notes.isEmpty ? name : name.padded(to: width) + "  (" + notes.joined(separator: ", ") + ")"
        }
        if !duplicated.isEmpty {
            lines.append("\nSome names are used more than once; pick one of those with --calendar <id>.")
            lines.append("calutil calendars --verbose shows what is in each calendar.")
        }
        return lines.joined(separator: "\n")
    }

    /// A block of details about one calendar, including its most recent and next events,
    /// so calendars with the same name can be told apart.
    static func describe(_ calendar: EKCalendar, isDefault: Bool, in store: EKEventStore) -> String {
        var flags = flags(calendar, isDefault: isDefault)
        if let color = hexColor(calendar) { flags.append(color) }

        let now = Date()
        let yearAgo = Calendar.current.date(byAdding: .year, value: -1, to: now)!
        let yearAhead = Calendar.current.date(byAdding: .year, value: 1, to: now)!
        // Recurring events count once per occurrence.
        let events = store.events(matching: store.predicateForEvents(withStart: yearAgo, end: yearAhead, calendars: [calendar]))
            .sorted { $0.startDate < $1.startDate }
        let past = events.filter { $0.startDate < now }
        let upcoming = events.filter { $0.startDate >= now }

        func eventLine(_ event: EKEvent) -> String {
            let zone = event.isAllDay ? TimeZone.current : (event.timeZone ?? TimeZone.current)
            let when = Summary.format(event.startDate, zone, time: !event.isAllDay)
            return "\(when)  \(trimmedNonEmpty(event.title) ?? "(no title)")"
        }
        func count(_ n: Int) -> String { n == 1 ? "1 event" : "\(n) events" }

        var rows: [(String, String)] = [
            ("id", calendar.calendarIdentifier),
            ("type", typeName(calendar.type)),
            ("past year", count(past.count)),
        ]
        if let last = past.last { rows.append(("last", eventLine(last))) }
        rows.append(("next year", count(upcoming.count)))
        if let next = upcoming.first { rows.append(("next", eventLine(next))) }

        let width = rows.map(\.0.count).max() ?? 0
        let header = qualifiedName(calendar) + (flags.isEmpty ? "" : "  (" + flags.joined(separator: ", ") + ")")
        return ([header] + rows.map { "  " + $0.0.padded(to: width) + "  " + $0.1 })
            .joined(separator: "\n")
    }

    static func typeName(_ type: EKCalendarType) -> String {
        switch type {
        case .local: "on this Mac"
        case .calDAV: "CalDAV (iCloud and similar)"
        case .exchange: "Exchange"
        case .subscription: "subscription"
        case .birthday: "birthdays"
        @unknown default: "other"
        }
    }

    /// "default", "read-only", "subscribed": the same in the plain and verbose listings.
    static func flags(_ calendar: EKCalendar, isDefault: Bool) -> [String] {
        var flags: [String] = []
        if isDefault { flags.append("default") }
        if !calendar.allowsContentModifications { flags.append("read-only") }
        if calendar.isSubscribed { flags.append("subscribed") }
        return flags
    }

    /// The calendar's colour as #RRGGBB, to help tell same-named calendars apart.
    static func hexColor(_ calendar: EKCalendar) -> String? {
        guard let srgb = CGColorSpace(name: CGColorSpace.sRGB),
              let components = calendar.cgColor?.converted(to: srgb, intent: .defaultIntent, options: nil)?.components,
              components.count >= 3
        else { return nil }
        let bytes = components.prefix(3).map { Int(($0 * 255).rounded()).clamped(to: 0...255) }
        return String(format: "colour #%02X%02X%02X", bytes[0], bytes[1], bytes[2])
    }

    // MARK: - Calendar lookup

    static func qualifiedName(_ calendar: EKCalendar) -> String {
        "\(calendar.source?.title ?? "?")/\(calendar.title)"
    }

    /// Finds a calendar by its identifier, its name, or "Account/Name".
    static func findCalendar(named name: String?, in store: EKEventStore) throws -> EKCalendar {
        guard let name else {
            guard let calendar = store.defaultCalendarForNewEvents else {
                throw CalUtilError("there is no default calendar; choose one with --calendar (see 'calutil calendars')")
            }
            return calendar
        }
        let all = store.calendars(for: .event)
        let matches = calendars(matching: name, in: all)
        if matches.count == 1, matches[0].calendarIdentifier == name {
            guard matches[0].allowsContentModifications else {
                throw CalUtilError("the calendar \(qualifiedName(matches[0])) is read-only")
            }
            return matches[0]
        }
        let writable = matches.filter(\.allowsContentModifications)
        if writable.count == 1 { return writable[0] }
        if writable.count > 1 {
            let byName = Dictionary(grouping: writable, by: qualifiedName)
            if byName.count > 1 {
                let names = byName.keys.sorted().map { "  \($0)" }.joined(separator: "\n")
                throw CalUtilError("more than one calendar is called '\(name)'; pick one with --calendar \"Account/Name\":\n\(names)")
            }
            let ids = writable.map { calendar in
                "  \(calendar.calendarIdentifier)" + (hexColor(calendar).map { "  (\($0))" } ?? "")
            }.joined(separator: "\n")
            throw CalUtilError("more than one calendar is called '\(qualifiedName(writable[0]))'; pick one with --calendar <id>:\n\(ids)")
        }
        if !matches.isEmpty {
            throw CalUtilError("the calendar '\(name)' is read-only")
        }
        let available = all.filter(\.allowsContentModifications).map { "  \(qualifiedName($0))" }.sorted().joined(separator: "\n")
        throw CalUtilError("no calendar called '\(name)'. Calendars you can add to:\n\(available)")
    }

    /// Calendars to read from: every calendar matching each name (read-only ones too).
    static func calendarsToRead(_ names: [String], in store: EKEventStore) throws -> [EKCalendar] {
        let all = store.calendars(for: .event)
        var chosen: [EKCalendar] = []
        for name in names {
            let matches = calendars(matching: name, in: all)
            guard !matches.isEmpty else {
                let available = Set(all.map(\.title)).sorted().map { "  \($0)" }.joined(separator: "\n")
                throw CalUtilError("no calendar called '\(name)'. Your calendars:\n\(available)")
            }
            for calendar in matches where !chosen.contains(where: { $0.calendarIdentifier == calendar.calendarIdentifier }) {
                chosen.append(calendar)
            }
        }
        return chosen
    }

    /// An id match, else exact name or "Account/Name" matches, else case-insensitive ones.
    static func calendars(matching name: String, in all: [EKCalendar]) -> [EKCalendar] {
        if let calendar = all.first(where: { $0.calendarIdentifier == name }) { return [calendar] }
        let exact = all.filter { $0.title == name || qualifiedName($0) == name }
        if !exact.isEmpty { return exact }
        return all.filter {
            $0.title.caseInsensitiveCompare(name) == .orderedSame
                || qualifiedName($0).caseInsensitiveCompare(name) == .orderedSame
        }
    }

    // MARK: - Listing events

    static func listEvents(_ options: ListOptions) throws -> String {
        let local = TimeZone.current
        let now = Date()
        // Check the input before asking for Calendar access.
        let zone = try options.timezone.map(DateParsing.timeZone(named:)) ?? local
        let calendar = DateParsing.gregorian(zone)
        let day = try DateParsing.parseDay(options.day ?? "today", now: now, timeZone: zone)
        let first = try DateParsing.startOfDay(year: day.year, month: day.month, day: day.day, timeZone: zone)
        let end = DateParsing.startOfDay(options.days, after: first, calendar: calendar)

        let store = try authorizedStore()
        let calendars = options.calendars.isEmpty ? nil : try calendarsToRead(options.calendars, in: store)
        // A day's margin each side: all-day events are fetched by the Mac's zone, not `zone`.
        let predicate = store.predicateForEvents(withStart: first.addingTimeInterval(-86_400),
                                                 end: end.addingTimeInterval(86_400), calendars: calendars)
        let events = EventList.prepare(store.events(matching: predicate).map(listed), local: local, zone: zone,
                                       from: first, to: end)
        let listing = EventList.render(events, from: first, days: options.days, timeZone: zone, now: now,
                                       verbose: options.verbose)
        return [EventList.zoneNote(zone, local: local, at: first), listing].compactMap { $0 }.joined(separator: "\n\n")
    }

    static func searchEvents(_ options: SearchOptions) throws -> String {
        let local = TimeZone.current
        let now = Date()
        // Check the input before asking for Calendar access.
        let zone = try options.timezone.map(DateParsing.timeZone(named:)) ?? local
        let calendar = DateParsing.gregorian(zone)
        let range = try EventSearch.range(options, now: now, timeZone: zone)

        let store = try authorizedStore()
        let calendars = options.calendars.isEmpty ? nil : try calendarsToRead(options.calendars, in: store)
        // An event that spans two windows comes back from both; keep it once.
        var seen: Set<String> = []
        var events: [ListedEvent] = []
        // A day's margin each side: all-day events are fetched by the Mac's zone, not `zone`.
        let windows = EventSearch.windows(from: range.first.addingTimeInterval(-86_400),
                                          to: range.end.addingTimeInterval(86_400), calendar: calendar)
        for window in windows {
            let predicate = store.predicateForEvents(withStart: window.start, end: window.end, calendars: calendars)
            for event in store.events(matching: predicate) {
                let key = "\(event.eventIdentifier ?? UUID().uuidString)|\(event.startDate.timeIntervalSince1970)"
                if seen.insert(key).inserted { events.append(listed(event)) }
            }
        }
        events = EventList.prepare(events, local: local, zone: zone, from: range.first, to: range.end)
        let found = EventSearch.render(events, options: options, first: range.first, end: range.end,
                                       days: range.days, timeZone: zone, now: now)
        return [EventList.zoneNote(zone, local: local, at: range.first), found].compactMap { $0 }.joined(separator: "\n\n")
    }

    static func listed(_ event: EKEvent) -> ListedEvent {
        ListedEvent(
            title: trimmedNonEmpty(event.title) ?? "(no title)",
            calendar: event.calendar?.title ?? "?",
            calendarFullName: event.calendar.map(qualifiedName) ?? "?",
            start: event.startDate,
            end: event.endDate,
            isAllDay: event.isAllDay,
            timeZone: event.timeZone,
            location: trimmedNonEmpty(event.location),
            place: event.structuredLocation?.geoLocation.map {
                Place(latitude: $0.coordinate.latitude, longitude: $0.coordinate.longitude)
            },
            notes: trimmedNonEmpty(event.notes),
            url: event.url,
            alarms: (event.alarms ?? []).map { alarm in
                if let date = alarm.absoluteDate { return .at(date) }
                return .beforeStart(seconds: Int(-alarm.relativeOffset))
            },
            isRecurring: event.hasRecurrenceRules,
            identifier: event.eventIdentifier)
    }

}

private extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self { min(max(self, range.lowerBound), range.upperBound) }
}
