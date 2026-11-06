import CalAddCore
import EventKit
import Foundation

enum EventKitBackend {
    /// Returns an event store with full Calendar access, asking for it the first time.
    static func authorizedStore() throws -> EKEventStore {
        let settingsHint = "Allow it in System Settings → Privacy & Security → Calendars → cal-add, then try again."
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
                throw CalAddError("cal-add was not given access to your calendars\(reason). \(settingsHint)")
            }
            // A fresh store sees the calendars that the new permission unlocked.
            return EKEventStore()
        case .writeOnly:
            throw CalAddError("cal-add only has \"add events only\" access, but needs full access to find calendars by name. \(settingsHint)")
        case .denied, .restricted:
            throw CalAddError("cal-add is not allowed to use your calendars. \(settingsHint)")
        @unknown default:
            throw CalAddError("unexpected Calendar permission state. \(settingsHint)")
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

        do {
            try store.save(event, span: .thisEvent, commit: true)
        } catch {
            throw CalAddError("Calendar refused the event: \(error.localizedDescription)")
        }
        return calendar
    }

    static func listCalendars() throws -> String {
        let store = try authorizedStore()
        let defaultID = store.defaultCalendarForNewEvents?.calendarIdentifier
        let calendars = store.calendars(for: .event).sorted { qualifiedName($0) < qualifiedName($1) }
        guard !calendars.isEmpty else { return "No calendars found." }
        let width = calendars.map { qualifiedName($0).count }.max() ?? 0
        return calendars.map { calendar in
            var notes: [String] = []
            if calendar.calendarIdentifier == defaultID { notes.append("default") }
            if !calendar.allowsContentModifications { notes.append("read-only") }
            let name = qualifiedName(calendar)
            return notes.isEmpty ? name : name.padding(toLength: width, withPad: " ", startingAt: 0) + "  (" + notes.joined(separator: ", ") + ")"
        }.joined(separator: "\n")
    }

    // MARK: - Calendar lookup

    static func qualifiedName(_ calendar: EKCalendar) -> String {
        "\(calendar.source?.title ?? "?")/\(calendar.title)"
    }

    /// Finds a calendar by its name, or by "Account/Name" when names are shared.
    static func findCalendar(named name: String?, in store: EKEventStore) throws -> EKCalendar {
        guard let name else {
            guard let calendar = store.defaultCalendarForNewEvents else {
                throw CalAddError("there is no default calendar; choose one with --calendar (see --list-calendars)")
            }
            return calendar
        }
        let all = store.calendars(for: .event)
        var matches = all.filter { $0.title == name || qualifiedName($0) == name }
        if matches.isEmpty {
            matches = all.filter {
                $0.title.caseInsensitiveCompare(name) == .orderedSame
                    || qualifiedName($0).caseInsensitiveCompare(name) == .orderedSame
            }
        }
        let writable = matches.filter(\.allowsContentModifications)
        if writable.count == 1 { return writable[0] }
        if writable.count > 1 {
            let names = writable.map { "  \(qualifiedName($0))" }.joined(separator: "\n")
            throw CalAddError("more than one calendar is called '\(name)'; pick one with --calendar \"Account/Name\":\n\(names)")
        }
        if !matches.isEmpty {
            throw CalAddError("the calendar '\(name)' is read-only")
        }
        let available = all.filter(\.allowsContentModifications).map { "  \(qualifiedName($0))" }.sorted().joined(separator: "\n")
        throw CalAddError("no calendar called '\(name)'. Calendars you can add to:\n\(available)")
    }
}
