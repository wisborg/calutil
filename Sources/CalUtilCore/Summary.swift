import Foundation

/// The human-readable description used by the dry run and after saving.
public enum Summary {
    public static func render(_ event: EventSpec, localTimeZone: TimeZone = .current) -> String {
        var rows: [(label: String, value: String)] = []
        let zone = event.timeZone
        let calendar = DateParsing.gregorian(zone)

        rows.append(("Title", event.title))
        if let location = event.location { rows.append(("Location", location)) }

        if event.isAllDay {
            let days = calendar.dateComponents([.day], from: event.start, to: event.end).day ?? 1
            let lastDay = calendar.date(byAdding: .day, value: -1, to: event.end)!
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
        if let notes = event.notes {
            for (index, line) in notes.lines.enumerated() {
                rows.append((index == 0 ? "Notes" : "", line))
            }
        }
        if let template = event.templateName { rows.append(("Template", template)) }

        let width = rows.map(\.label.count).max() ?? 0
        return rows.map { row in
            row.label.padded(to: width) + "  " + row.value
        }.joined(separator: "\n")
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
