import Foundation

/// The human-readable description used by the dry run and after saving.
public enum Summary {
    /// `listMatches` lists every match of the map search, so another can be picked (dry run).
    public static func render(_ event: EventSpec, localTimeZone: TimeZone = .current,
                              listMatches: Bool = false) -> String {
        table(fields(event, localTimeZone: localTimeZone, listMatches: listMatches))
    }

    /// Labelled rows, values that span lines kept indented under their label.
    static func table(_ rows: [(label: String, value: String)]) -> String {
        let width = rows.map(\.label.count).max() ?? 0
        return rows.flatMap { row in
            row.value.lines.enumerated().map { index, line in
                (index == 0 ? row.label : "").padded(to: width) + "  " + line
            }
        }.joined(separator: "\n")
    }

    /// The summary's fields in order, one per label (a value may span lines).
    static func fields(_ event: EventSpec, localTimeZone: TimeZone, listMatches: Bool) -> [(label: String, value: String)] {
        var rows: [(label: String, value: String)] = []
        let zone = event.timeZone
        let calendar = DateParsing.gregorian(zone)

        rows.append(("Title", event.title))
        if let location = event.location { rows.append(("Location", location)) }
        if let place = event.place {
            if listMatches && event.matches.count > 1 {
                for (index, match) in event.matches.enumerated() {
                    let chosen = match == place
                    let text = "\(index + 1) \(chosen ? "✓" : " ")  \(match.description)"
                        + (chosen ? "  (\(match.coordinates))" : "")
                    rows.append((index == 0 ? "Map" : "", text))
                }
                rows.append(("", "pick another with --map-match N, or leave the map out with --no-map"))
            } else {
                let text = place.name == nil && place.address == nil
                    ? place.coordinates : "\(place.description)  (\(place.coordinates))"
                rows.append(("Map", text))
            }
        }

        if event.isAllDay {
            // The end is the start of the day after the last one.
            let days = DateParsing.daysBetween(event.start, event.end, calendar: calendar)
            let lastDay = event.end.addingTimeInterval(-1)
            if days <= 1 {
                rows.append(("Date", "\(format(event.start, zone, time: false)) (all day)"))
            } else {
                rows.append(("Dates", "\(format(event.start, zone, time: false)) – \(format(lastDay, zone, time: false)) (all day, \(days) days)"))
            }
        } else {
            let length = Int(event.end.timeIntervalSince(event.start))
            rows.append(("Starts", format(event.start, zone)))
            rows.append(("Ends", "\(format(event.end, zone))  (\(Durations.describe(length)))"))
            rows.append(("Time zone", zoneLabel(zone, at: event.start)))
            let differs = localTimeZone.secondsFromGMT(for: event.start) != zone.secondsFromGMT(for: event.start)
                || localTimeZone.secondsFromGMT(for: event.end) != zone.secondsFromGMT(for: event.end)
            if differs {
                rows.append(("Your time", "\(format(event.start, localTimeZone)) – \(format(event.end, localTimeZone))  \(zoneLabel(localTimeZone, at: event.start))"))
            }
        }

        rows.append(("Calendar", event.calendarName ?? "(default calendar)"))

        if event.alarms.isEmpty {
            rows.append(("Alarms", "none"))
        } else {
            // All-day events float, so show their alarms in the Mac's zone.
            let alarmZone = event.isAllDay ? localTimeZone : zone
            let described = event.alarms.map { alarm in
                (what: alarm.label, fires: format(alarm.fireDate(eventStart: event.start), alarmZone))
            }
            let whatWidth = described.map(\.what.count).max() ?? 0
            for (index, alarm) in described.enumerated() {
                let text = alarm.what.padded(to: whatWidth) + "  " + alarm.fires
                rows.append((index == 0 ? (described.count == 1 ? "Alarm" : "Alarms") : "", text))
            }
        }

        if let url = event.url { rows.append(("URL", url.absoluteString)) }
        if let notes = event.notes { rows.append(("Notes", notes)) }
        if let template = event.templateName { rows.append(("Template", template)) }

        // Rows with an empty label continue the one before.
        var fields: [(label: String, value: String)] = []
        for row in rows {
            if row.label.isEmpty, !fields.isEmpty {
                fields[fields.count - 1].value += "\n" + row.value
            } else {
                fields.append(row)
            }
        }
        return fields
    }

    /// "Fri 6 Nov 2026 18:00", or without the time.
    public static func format(_ date: Date, _ zone: TimeZone, time: Bool = true) -> String {
        Formatters.shared.formatter(zone: zone, time: time).string(from: date)
    }

    /// DateFormatters are costly to create and `list` formats many dates, so keep one per
    /// time zone and style.
    private final class Formatters: @unchecked Sendable {
        static let shared = Formatters()
        private let lock = NSLock()
        private var cache: [String: DateFormatter] = [:]

        func formatter(zone: TimeZone, time: Bool) -> DateFormatter {
            let key = "\(zone.identifier)|\(zone.secondsFromGMT())|\(time)"
            lock.lock()
            defer { lock.unlock() }
            if let formatter = cache[key] { return formatter }
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_GB")
            formatter.calendar = DateParsing.gregorian(zone)
            formatter.timeZone = zone
            formatter.dateFormat = time ? "EEE d MMM yyyy HH:mm" : "EEE d MMM yyyy"
            cache[key] = formatter
            return formatter
        }
    }

    static func zoneLabel(_ zone: TimeZone, at date: Date) -> String {
        "\(zone.identifier) (\(offsetName(zone.secondsFromGMT(for: date))))"
    }
}
