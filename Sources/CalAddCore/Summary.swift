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
            let described = event.alarms.map { alarm -> (what: String, fires: String) in
                let fires = format(alarm.fireDate(eventStart: event.start), alarmZone)
                return switch alarm {
                case .beforeStart(0): ("at the start", fires)
                case .beforeStart(let seconds): ("\(Durations.describe(seconds)) before", fires)
                case .at: ("at", fires)
                }
            }
            let whatWidth = described.map(\.what.count).max() ?? 0
            for (index, alarm) in described.enumerated() {
                let text = alarm.what.padding(toLength: whatWidth, withPad: " ", startingAt: 0) + "  " + alarm.fires
                rows.append((index == 0 ? (described.count == 1 ? "Alarm" : "Alarms") : "", text))
            }
        }

        if let url = event.url { rows.append(("URL", url.absoluteString)) }
        if let notes = event.notes {
            for (index, line) in notes.components(separatedBy: .newlines).enumerated() {
                rows.append((index == 0 ? "Notes" : "", line))
            }
        }
        if let template = event.templateName { rows.append(("Template", template)) }

        let width = rows.map(\.label.count).max() ?? 0
        return rows.map { row in
            row.label.padding(toLength: width, withPad: " ", startingAt: 0) + "  " + row.value
        }.joined(separator: "\n")
    }

    static func format(_ date: Date, _ zone: TimeZone, time: Bool = true) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_GB")
        formatter.calendar = DateParsing.gregorian(zone)
        formatter.timeZone = zone
        formatter.dateFormat = time ? "EEE d MMM yyyy HH:mm" : "EEE d MMM yyyy"
        return formatter.string(from: date)
    }

    static func zoneLabel(_ zone: TimeZone, at date: Date) -> String {
        "\(zone.identifier) (\(offsetName(zone.secondsFromGMT(for: date))))"
    }
}
