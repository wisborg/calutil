import Foundation

/// Renders an event as an RFC 5545 iCalendar file.
public enum ICS {
    public static func render(_ event: EventSpec, uid: String = UUID().uuidString + "@calutil",
                              now: Date = Date()) -> String {
        var lines = [
            "BEGIN:VCALENDAR",
            "VERSION:2.0",
            "PRODID:-//calutil//calutil \(Help.version)//EN",
            "CALSCALE:GREGORIAN",
        ]
        let zone = event.timeZone
        let utc = isUTC(zone)
        if !event.isAllDay && !utc {
            lines += vtimezone(zone, from: event.start.addingTimeInterval(-366 * 86_400),
                               to: event.end.addingTimeInterval(366 * 86_400))
        }

        lines += ["BEGIN:VEVENT", "UID:\(uid)", "DTSTAMP:\(utcStamp(now))"]
        if event.isAllDay {
            lines.append("DTSTART;VALUE=DATE:\(stamp(event.start, zone, time: false))")
            lines.append("DTEND;VALUE=DATE:\(stamp(event.end, zone, time: false))")
        } else if utc {
            lines.append("DTSTART:\(utcStamp(event.start))")
            lines.append("DTEND:\(utcStamp(event.end))")
        } else {
            let tzid = parameter(zone.identifier)
            lines.append("DTSTART;TZID=\(tzid):\(stamp(event.start, zone))")
            lines.append("DTEND;TZID=\(tzid):\(stamp(event.end, zone))")
        }
        lines.append("SUMMARY:\(escape(event.title))")
        if let location = event.location { lines.append("LOCATION:\(escape(location))") }
        if let place = event.place {
            // GEO is the standard property; Calendar shows its map from Apple's own one.
            let lat = String(format: "%.6f", place.latitude), lon = String(format: "%.6f", place.longitude)
            lines.append("GEO:\(lat);\(lon)")
            var structured = "X-APPLE-STRUCTURED-LOCATION;VALUE=URI"
            if let address = place.address { structured += ";X-ADDRESS=\(parameter(address))" }
            let title = Places.query(for: event.location ?? place.locationText)
            structured += ";X-TITLE=\(parameter(title)):geo:\(lat),\(lon)"
            lines.append(structured)
        }
        if let notes = event.notes { lines.append("DESCRIPTION:\(escape(notes))") }
        if let url = event.url { lines.append("URL:\(url.absoluteString)") }

        for alarm in event.alarms {
            lines += ["BEGIN:VALARM", "ACTION:DISPLAY", "DESCRIPTION:\(escape(event.title))"]
            switch alarm {
            case .beforeStart(let seconds):
                lines.append("TRIGGER:\(seconds == 0 ? "" : "-")\(Durations.icalendar(seconds))")
            case .at(let date):
                lines.append("TRIGGER;VALUE=DATE-TIME:\(utcStamp(date))")
            }
            lines.append("END:VALARM")
        }
        lines += ["END:VEVENT", "END:VCALENDAR"]
        return lines.map(fold).joined(separator: "\r\n") + "\r\n"
    }

    /// A VTIMEZONE describing `zone` over the given range, built from the system's
    /// time zone rules so the file is self-contained.
    static func vtimezone(_ zone: TimeZone, from rangeStart: Date, to rangeEnd: Date) -> [String] {
        func component(at date: Date, offsetFrom: Int, offsetTo: Int, isDST: Bool) -> [String] {
            let kind = isDST ? "DAYLIGHT" : "STANDARD"
            // DTSTART is the wall-clock time just before the change, i.e. in the old offset.
            let local = stamp(date.addingTimeInterval(TimeInterval(offsetFrom)), TimeZone(secondsFromGMT: 0)!)
            return [
                "BEGIN:\(kind)",
                "DTSTART:\(local)",
                "TZOFFSETFROM:\(offset(offsetFrom))",
                "TZOFFSETTO:\(offset(offsetTo))",
                "TZNAME:\(escape(offsetName(offsetTo)))",
                "END:\(kind)",
            ]
        }

        var lines = ["BEGIN:VTIMEZONE", "TZID:\(zone.identifier)"]
        let initial = zone.secondsFromGMT(for: rangeStart)
        lines += component(at: rangeStart, offsetFrom: initial, offsetTo: initial,
                           isDST: zone.isDaylightSavingTime(for: rangeStart))
        var cursor = rangeStart
        while let change = zone.nextDaylightSavingTimeTransition(after: cursor), change < rangeEnd {
            lines += component(at: change,
                               offsetFrom: zone.secondsFromGMT(for: change.addingTimeInterval(-1)),
                               offsetTo: zone.secondsFromGMT(for: change),
                               isDST: zone.isDaylightSavingTime(for: change))
            cursor = change
        }
        lines.append("END:VTIMEZONE")
        return lines
    }

    // MARK: - Formatting

    static func escape(_ text: String) -> String {
        var out = ""
        for ch in text {
            switch ch {
            case "\\": out += "\\\\"
            case ";": out += "\\;"
            case ",": out += "\\,"
            case "\n", "\r\n", "\r": out += "\\n"
            default: out.append(ch)
            }
        }
        return out
    }

    /// Splits lines longer than 75 octets (RFC 5545 §3.1), never inside a UTF-8 sequence.
    static func fold(_ line: String) -> String {
        var out = String.UnicodeScalarView()
        var octets = 0
        for scalar in line.unicodeScalars {
            let width = UTF8.width(scalar)
            if octets + width > 75 {
                out.append(contentsOf: "\r\n ".unicodeScalars)
                octets = 1
            }
            out.append(scalar)
            octets += width
        }
        return String(out)
    }

    /// A parameter value, quoted when needed. Parameter values can't hold double quotes or
    /// line breaks (RFC 5545 §3.1), so those become single quotes and spaces.
    static func parameter(_ value: String) -> String {
        let value = value.replacingOccurrences(of: "\"", with: "'").lines.joined(separator: " ")
        return value.contains(where: { ":;,".contains($0) }) ? "\"\(value)\"" : value
    }

    static func stamp(_ date: Date, _ zone: TimeZone, time: Bool = true) -> String {
        let c = DateParsing.gregorian(zone).dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        let day = String(format: "%04d%02d%02d", c.year!, c.month!, c.day!)
        return time ? day + String(format: "T%02d%02d%02d", c.hour!, c.minute!, c.second!) : day
    }

    static func utcStamp(_ date: Date) -> String {
        stamp(date, TimeZone(secondsFromGMT: 0)!) + "Z"
    }

    static func offset(_ seconds: Int) -> String {
        let sign = seconds < 0 ? "-" : "+"
        let a = abs(seconds)
        var text = String(format: "%@%02d%02d", sign, a / 3_600, a % 3_600 / 60)
        if a % 60 != 0 { text += String(format: "%02d", a % 60) }
        return text
    }

    static func isUTC(_ zone: TimeZone) -> Bool {
        ["GMT", "UTC", "Etc/UTC", "Etc/GMT", "UCT", "Etc/UCT", "Zulu", "Etc/Zulu", "Universal", "Etc/Universal"]
            .contains(zone.identifier)
    }
}

/// "UTC+11", "UTC-5:30", "UTC".
func offsetName(_ seconds: Int) -> String {
    if seconds == 0 { return "UTC" }
    let a = abs(seconds)
    let minutes = a % 3_600 / 60
    return "UTC\(seconds < 0 ? "-" : "+")\(a / 3_600)" + (minutes == 0 ? "" : String(format: ":%02d", minutes))
}
