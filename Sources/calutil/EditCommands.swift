import CalUtilCore
import EventKit
import Foundation

/// `calutil edit` and `calutil delete`.
extension EventKitBackend {
    @MainActor
    static func edit(_ options: EditOptions) throws {
        let now = Date()
        let zone = TimeZone.current
        let (store, event) = try findOne(options.selection, now: now, zone: zone)
        let span = try span(for: event, future: options.future)
        try checkWritable(event)

        let current = spec(of: event)
        var changed = try Editor.apply(options.changes, to: current, now: now, localTimeZone: zone)
        var target: EKCalendar?
        if options.changes.calendar != nil {
            let calendar = try findCalendar(named: changed.calendarName, in: store)
            target = calendar
            changed.calendarName = qualifiedName(calendar)
        }
        try MapSearch.resolve(&changed)
        for warning in changed.warnings { printError("warning: \(warning)") }

        print("Editing \(Editor.describe(current))\(scope(event, span))")
        guard let differences = Editor.differences(from: current, to: changed, localTimeZone: zone,
                                                   listMatches: !options.save) else {
            print("\nNothing to change: it already looks like that.")
            return
        }
        print("\n" + differences)
        guard options.save else {
            printError("\nDry run: nothing was changed. Add --save to change it in Calendar.")
            return
        }

        write(changed, over: current, to: event, calendar: target)
        do {
            try store.save(event, span: span, commit: true)
        } catch {
            throw CalUtilError("Calendar refused the change: \(error.localizedDescription)")
        }
        print("\nChanged in \(qualifiedName(event.calendar)).")
    }

    @MainActor
    static func delete(_ options: DeleteOptions) throws {
        let (store, event) = try findOne(options.selection, now: Date(), zone: .current)
        let span = try span(for: event, future: options.future)
        try checkWritable(event)

        let current = spec(of: event)
        print("Deleting\(scope(event, span)):\n")
        print(Summary.render(current))
        guard options.confirmed else {
            let what = span == .futureEvents ? "this and the later occurrences" : event.hasRecurrenceRules ? "this occurrence" : "it"
            printError("\nDry run: nothing was deleted. Add --yes to delete \(what).")
            return
        }
        do {
            try store.remove(event, span: span, commit: true)
        } catch {
            throw CalUtilError("Calendar refused to delete it: \(error.localizedDescription)")
        }
        print("\nDeleted from \(current.calendarName ?? "Calendar").")
    }

    // MARK: - Finding the event

    /// The one event the selection means, or an error saying why there isn't one.
    static func findOne(_ selection: EventSelection, now: Date, zone: TimeZone) throws -> (EKEventStore, EKEvent) {
        let calendar = DateParsing.gregorian(zone)
        if let id = selection.id {
            // Check the input before asking for Calendar access.
            let day = try selection.on.map { text -> Date in
                let d = try DateParsing.parseDay(text, now: now, timeZone: zone)
                return try DateParsing.startOfDay(year: d.year, month: d.month, day: d.day, timeZone: zone)
            }
            let store = try authorizedStore()
            guard let event = store.event(withIdentifier: id) else {
                throw CalUtilError("no event with id \(id) (calutil search --verbose shows ids)")
            }
            guard let day else {
                if event.hasRecurrenceRules {
                    throw CalUtilError("“\(event.title ?? "")” repeats: pick the occurrence with --on DAY (and add --future to change the later ones too)")
                }
                return (store, event)
            }
            let predicate = store.predicateForEvents(withStart: day, end: DateParsing.startOfDay(1, after: day, calendar: calendar),
                                                     calendars: [event.calendar])
            guard let occurrence = store.events(matching: predicate).first(where: { $0.eventIdentifier == id }) else {
                throw CalUtilError("“\(event.title ?? "")” isn't on \(Summary.format(day, zone, time: false))")
            }
            return (store, occurrence)
        }

        let search = selection.searchOptions
        let range = try EventSearch.range(search, now: now, timeZone: zone)
        let store = try authorizedStore()
        let calendars = search.calendars.isEmpty ? nil : try calendarsToRead(search.calendars, in: store)
        var seen: Set<String> = []
        var found: [(event: EKEvent, listed: ListedEvent)] = []
        for window in EventSearch.windows(from: range.first, to: range.end, calendar: calendar) {
            let predicate = store.predicateForEvents(withStart: window.start, end: window.end, calendars: calendars)
            for event in store.events(matching: predicate) {
                let key = "\(event.eventIdentifier ?? UUID().uuidString)|\(event.startDate.timeIntervalSince1970)"
                guard seen.insert(key).inserted else { continue }
                let listed = listed(event)
                if EventSearch.matches(listed, search) { found.append((event, listed)) }
            }
        }
        let lastDay = DateParsing.startOfDay(range.days - 1, after: range.first, calendar: calendar)
        let span = "from \(Summary.format(range.first, zone, time: false)) to \(Summary.format(lastDay, zone, time: false))"
        switch found.count {
        case 0:
            throw CalUtilError("no events matching \(EventSearch.describe(search)) \(span)")
        case 1:
            return (store, found[0].event)
        default:
            let listing = found.count <= 20
                ? ":\n\n" + EventList.render(found.map(\.listed), from: range.first, days: range.days, timeZone: zone,
                                              now: now, verbose: false) + "\n\n"
                : ". "
            throw CalUtilError("\(found.count) events match \(EventSearch.describe(search)) \(span)\(listing)Narrow it down with more words, --on DAY or --match-calendar, or use --id (calutil search --verbose shows ids).")
        }
    }

    static func span(for event: EKEvent, future: Bool) throws -> EKSpan {
        guard future else { return .thisEvent }
        guard event.hasRecurrenceRules else {
            throw CalUtilError("--future is for repeating events; “\(event.title ?? "")” doesn't repeat", usage: true)
        }
        return .futureEvents
    }

    static func scope(_ event: EKEvent, _ span: EKSpan) -> String {
        guard event.hasRecurrenceRules else { return "" }
        return span == .futureEvents ? " (this and later occurrences)" : " (this occurrence only)"
    }

    static func checkWritable(_ event: EKEvent) throws {
        guard event.calendar.allowsContentModifications else {
            throw CalUtilError("“\(event.title ?? "")” is in \(qualifiedName(event.calendar)), which can't be changed")
        }
    }

    // MARK: - Reading and writing

    /// The event as `add` would describe it.
    static func spec(of event: EKEvent) -> EventSpec {
        let local = TimeZone.current
        let zone = event.isAllDay ? local : (event.timeZone ?? local)
        let calendar = DateParsing.gregorian(zone)
        // EventKit's all-day end is the last moment of the last day; calutil's is the next day's start.
        let end = event.isAllDay
            ? DateParsing.startOfDay(1, after: calendar.startOfDay(for: event.endDate), calendar: calendar)
            : event.endDate!
        let alarms: [Alarm] = (event.alarms ?? []).map { alarm in
            if let date = alarm.absoluteDate { return .at(date) }
            return .beforeStart(seconds: Int(-alarm.relativeOffset))
        }.sorted { $0.fireDate(eventStart: event.startDate) < $1.fireDate(eventStart: event.startDate) }
        return EventSpec(
            title: event.title ?? "",
            location: trimmedNonEmpty(event.location),
            notes: trimmedNonEmpty(event.notes),
            url: event.url,
            calendarName: event.calendar.map(qualifiedName),
            timeZone: zone,
            isAllDay: event.isAllDay,
            start: event.startDate,
            end: end,
            alarms: alarms,
            place: event.structuredLocation?.geoLocation.map {
                Place(latitude: $0.coordinate.latitude, longitude: $0.coordinate.longitude)
            })
    }

    /// Writes only what changed, so untouched fields (a floating time, Calendar's own map
    /// details) stay exactly as they were.
    static func write(_ new: EventSpec, over old: EventSpec, to event: EKEvent, calendar: EKCalendar?) {
        if new.title != old.title { event.title = new.title }
        if new.notes != old.notes { event.notes = new.notes }
        if new.url != old.url { event.url = new.url }
        if let calendar, calendar.calendarIdentifier != event.calendar.calendarIdentifier { event.calendar = calendar }
        if new.isAllDay != old.isAllDay || new.start != old.start || new.end != old.end
            || new.timeZone.identifier != old.timeZone.identifier {
            event.isAllDay = new.isAllDay
            if new.isAllDay {
                event.timeZone = nil  // floating: the same date wherever you are
            } else if old.isAllDay || new.timeZone.identifier != old.timeZone.identifier {
                event.timeZone = new.timeZone
            }
            event.startDate = new.start
            event.endDate = new.isAllDay ? new.end.addingTimeInterval(-1) : new.end
        }
        if new.alarms != old.alarms {
            event.alarms = new.alarms.map { alarm in
                switch alarm {
                case .beforeStart(let seconds): EKAlarm(relativeOffset: -TimeInterval(seconds))
                case .at(let date): EKAlarm(absoluteDate: date)
                }
            }
        }
        if new.location != old.location || new.place != old.place {
            if let place = new.place {
                // Its title becomes the location text, so this sets both.
                let structured = EKStructuredLocation(title: new.location ?? place.locationText)
                structured.geoLocation = CLLocation(latitude: place.latitude, longitude: place.longitude)
                event.structuredLocation = structured
            } else {
                event.structuredLocation = nil
                event.location = new.location
            }
        }
    }
}
