import Foundation
import Testing
@testable import CalUtilCore

let sydney = TimeZone(identifier: "Australia/Sydney")!
let copenhagen = TimeZone(identifier: "Europe/Copenhagen")!
/// A fixed "now" before the test events.
let now = ISO8601DateFormatter().date(from: "2026-11-01T00:00:00Z")!

func options(_ args: String...) throws -> AddOptions { try AddOptions.parse(args) }

func resolve(_ args: [String], template: Template? = nil, local: TimeZone = copenhagen) throws -> EventSpec {
    try Resolver.resolve(options: AddOptions.parse(args), template: template, now: now, localTimeZone: local)
}

func utc(_ text: String) -> Date { ISO8601DateFormatter().date(from: text)! }

let concert = Template(name: "concert", notes: "Bring tickets", calendar: "Personal",
                       time: "19:30", duration: "3h", alarms: ["1d", "2h"])

@Suite struct DurationTests {
    @Test func parses() throws {
        #expect(try Durations.parse("15m") == 900)
        #expect(try Durations.parse("1h30m") == 5_400)
        #expect(try Durations.parse("2D") == 172_800)
        #expect(try Durations.parse("1w") == 604_800)
        #expect(try Durations.parse("0") == 0)
        #expect(try Durations.parse("1d2h3m4s") == 93_784)
    }

    @Test(arguments: ["", "90", "h", "1x", "30m1h", "1h1h", "1.5h", "-1h", "99999999999999999w"])
    func rejects(_ text: String) {
        #expect(throws: CalUtilError.self) { try Durations.parse(text) }
    }

    @Test func formats() {
        #expect(Durations.describe(86_400 + 7_200) == "1 day 2 hours")
        #expect(Durations.describe(60) == "1 minute")
        #expect(Durations.icalendar(5_400) == "PT1H30M")
        #expect(Durations.icalendar(86_400) == "P1D")
        #expect(Durations.icalendar(93_784) == "P1DT2H3M4S")
        #expect(Durations.icalendar(0) == "PT0S")
    }
}

@Suite struct DateParsingTests {
    @Test func dateTimeForms() throws {
        let a = try DateParsing.parseDateTime("2026-11-06T18:00")
        #expect(a == DateTimeInput(year: 2026, month: 11, day: 6, time: TimeOfDay(hour: 18, minute: 0), utcOffset: nil))
        #expect(try DateParsing.parseDateTime("2026-11-06 18:00:30").time == TimeOfDay(hour: 18, minute: 0, second: 30))
        #expect(try DateParsing.parseDateTime("2026-11-06").time == nil)
        #expect(try DateParsing.parseDateTime("2026-11-06T07:00Z").utcOffset == 0)
        #expect(try DateParsing.parseDateTime("2026-11-06T18:00+11:00").utcOffset == 39_600)
        #expect(try DateParsing.parseDateTime("2026-11-06T18:00-0530").utcOffset == -19_800)
    }

    @Test(arguments: ["06-11-2026", "2026-13-01", "2026-11-06T25:00", "2026-11-06T18", "2026-11-06X18:00", "tomorrow"])
    func rejects(_ text: String) {
        #expect(throws: CalUtilError.self) { try DateParsing.parseDateTime(text) }
    }

    @Test func impossibleDates() {
        #expect(throws: CalUtilError.self) {
            try DateParsing.makeDate(year: 2026, month: 2, day: 30, time: TimeOfDay(hour: 12, minute: 0), timeZone: copenhagen)
        }
        // 02:30 doesn't exist in Copenhagen on 2026-03-29 (clocks jump 02:00 → 03:00).
        #expect(throws: CalUtilError.self) {
            try DateParsing.makeDate(year: 2026, month: 3, day: 29, time: TimeOfDay(hour: 2, minute: 30), timeZone: copenhagen)
        }
    }
}

@Suite struct OptionTests {
    @Test func defaultsToDryRun() throws {
        #expect(try options("--title", "x").action == .dryRun)
        #expect(try options("--save").action == .save)
        #expect(try options("--open").action == .openICS)
        #expect(try options("--ics").action == .printICS)
    }

    @Test func equalsForm() throws {
        let o = try options("--title=Beethoven's 9th", "--alarm=1d", "--alarm", "2h", "--add-alarm", "15m")
        #expect(o.title == "Beethoven's 9th")
        #expect(o.alarms == ["1d", "2h"])
        #expect(o.addAlarms == ["15m"])
    }

    @Test func usageErrors() {
        #expect(throws: CalUtilError.self) { try options("Beethoven") }           // positional
        #expect(throws: CalUtilError.self) { try options("--titel", "x") }        // typo
        #expect(throws: CalUtilError.self) { try options("--title") }             // missing value
        #expect(throws: CalUtilError.self) { try options("--title", "--start") }  // value looks like option
        #expect(throws: CalUtilError.self) { try options("--title", "a", "--title", "b") }
        #expect(throws: CalUtilError.self) { try options("--save", "--open") }
        #expect(throws: CalUtilError.self) { try options("--save=yes") }
        #expect(throws: CalUtilError.self) { try options("--no-alarms", "--alarm", "1h") }
        #expect(throws: CalUtilError.self) { try options("--verbose", "--title", "x") }
    }
}

@Suite struct InvocationTests {
    func parse(_ args: String...) throws -> Invocation { try Invocation.parse(args) }

    @Test func commands() throws {
        #expect(try parse() == .help(nil))
        #expect(try parse("--help") == .help(nil))
        #expect(try parse("help", "add") == .help("add"))
        #expect(try parse("add", "--title", "x", "-h") == .help("add"))
        #expect(try parse("version") == .version)
        #expect(try parse("calendars") == .calendars(verbose: false))
        #expect(try parse("calendars", "-v") == .calendars(verbose: true))
        #expect(try parse("templates", "--templates", "/x.json") == .templates(path: "/x.json", json: false))
        #expect(try parse("templates", "--json") == .templates(path: nil, json: true))
        guard case .add(let add) = try parse("add", "--title", "x", "--save") else {
            Issue.record("expected add"); return
        }
        #expect(add.title == "x" && add.action == .save)
    }

    @Test func errors() {
        #expect(throws: CalUtilError.self) { try parse("--title", "x") }      // no command
        #expect(throws: CalUtilError.self) { try parse("ad") }                // unknown command
        #expect(throws: CalUtilError.self) { try parse("help", "nope") }
        #expect(throws: CalUtilError.self) { try parse("calendars", "--save") }
        #expect(throws: CalUtilError.self) { try parse("calendars", "Home") }
        #expect(throws: CalUtilError.self) { try parse("calendars", "--verbose=yes") }
    }
}

@Suite struct ResolverTests {
    @Test func basicTimedEvent() throws {
        let e = try resolve(["--title", "Dentist", "--start", "2026-11-10T09:30", "--duration", "45m"])
        #expect(e.start == utc("2026-11-10T08:30:00Z"))
        #expect(e.end == utc("2026-11-10T09:15:00Z"))
        #expect(e.timeZone == copenhagen)
        #expect(e.alarms.isEmpty)
        #expect(e.calendarName == nil)
    }

    @Test func defaultDurationIsOneHour() throws {
        let e = try resolve(["--title", "x", "--start", "2026-11-10T09:00"])
        #expect(e.end.timeIntervalSince(e.start) == 3_600)
    }

    @Test func templateWithTimeZone() throws {
        let e = try resolve(["--template", "concert", "--title", "Beethoven's 9th", "--location", "Sydney Opera House",
                             "--start", "2026-11-06T18:00", "--timezone", "Australia/Sydney"], template: concert)
        #expect(e.start == utc("2026-11-06T07:00:00Z"))  // Sydney is UTC+11 in November
        #expect(e.end == utc("2026-11-06T10:00:00Z"))
        #expect(e.timeZone == sydney)
        #expect(e.alarms == [.beforeStart(seconds: 86_400), .beforeStart(seconds: 7_200)])
        #expect(e.notes == "Bring tickets")
        #expect(e.calendarName == "Personal")
        #expect(e.templateName == "concert")
    }

    @Test func templateTimeFillsDateOnlyStart() throws {
        let e = try resolve(["--title", "x", "--start", "2026-11-20"], template: concert)
        #expect(e.start == utc("2026-11-20T18:30:00Z"))
        #expect(!e.isAllDay)
    }

    @Test func dateOnlyStartWithoutTimeIsAnError() {
        #expect(throws: CalUtilError.self) { try resolve(["--title", "x", "--start", "2026-11-20"]) }
    }

    @Test func alarmOverrides() throws {
        let base = ["--title", "x", "--start", "2026-11-20T19:00"]
        #expect(try resolve(base + ["--alarm", "30m"], template: concert).alarms == [.beforeStart(seconds: 1_800)])
        #expect(try resolve(base + ["--no-alarms"], template: concert).alarms.isEmpty)
        // Added, de-duplicated, sorted earliest first.
        #expect(try resolve(base + ["--add-alarm", "15m", "--add-alarm", "2h"], template: concert).alarms
            == [.beforeStart(seconds: 86_400), .beforeStart(seconds: 7_200), .beforeStart(seconds: 900)])
        #expect(try resolve(base + ["--no-alarms", "--add-alarm", "0"], template: concert).alarms
            == [.beforeStart(seconds: 0)])
    }

    @Test func absoluteAlarms() throws {
        let e = try resolve(["--title", "x", "--start", "2026-11-20T19:00", "--alarm", "09:00", "--alarm", "2026-11-19T20:00"])
        #expect(e.alarms == [.at(utc("2026-11-19T19:00:00Z")), .at(utc("2026-11-20T08:00:00Z"))])
    }

    @Test func badTemplateValuesNameTheTemplate() {
        let broken = Template(name: "broken", duration: "three hours")
        #expect {
            try resolve(["--title", "x", "--start", "2026-11-20T19:00"], template: broken)
        } throws: { error in
            (error as? CalUtilError)?.message.contains("template 'broken'") == true
        }
    }

    @Test func commandLineBeatsTemplate() throws {
        let e = try resolve(["--title", "x", "--start", "2026-11-20T19:00", "--duration", "1h",
                             "--calendar", "Work", "--notes", ""], template: concert)
        #expect(e.end.timeIntervalSince(e.start) == 3_600)
        #expect(e.calendarName == "Work")
        #expect(e.notes == nil)  // "" clears the template's notes
    }

    @Test func endAsTimeRollsOverMidnight() throws {
        let e = try resolve(["--title", "x", "--start", "2026-11-20T22:00", "--end", "01:30"])
        #expect(e.end == utc("2026-11-21T00:30:00Z"))
        let f = try resolve(["--title", "x", "--start", "2026-11-20T19:00", "--end", "21:15"])
        #expect(f.end == utc("2026-11-20T20:15:00Z"))
    }

    @Test func endBeatsTemplateDuration() throws {
        let e = try resolve(["--title", "x", "--start", "2026-11-20T19:00", "--end", "20:00"], template: concert)
        #expect(e.end.timeIntervalSince(e.start) == 3_600)
    }

    @Test func allDay() throws {
        let e = try resolve(["--title", "Holiday", "--start", "2026-12-24", "--end", "2026-12-26", "--all-day"])
        #expect(e.isAllDay)
        #expect(e.start == utc("2026-12-23T23:00:00Z"))
        #expect(e.end == utc("2026-12-26T23:00:00Z"))
        let one = try resolve(["--title", "x", "--start", "2026-12-24", "--all-day"])
        #expect(one.end.timeIntervalSince(one.start) == 86_400)
        #expect(throws: CalUtilError.self) { try resolve(["--title", "x", "--start", "2026-12-24T10:00", "--all-day"]) }
        #expect(throws: CalUtilError.self) { try resolve(["--title", "x", "--start", "2026-12-24", "--all-day", "--duration", "5h"]) }
    }

    @Test func otherErrors() {
        #expect(throws: CalUtilError.self) { try resolve(["--start", "2026-11-20T19:00"]) }
        #expect(throws: CalUtilError.self) { try resolve(["--title", "x"]) }
        #expect(throws: CalUtilError.self) { try resolve(["--title", "x", "--start", "2026-11-20T19:00", "--timezone", "Mars/Olympus"]) }
        #expect(throws: CalUtilError.self) { try resolve(["--title", "x", "--start", "2026-11-20T19:00", "--end", "2026-11-20T18:00"]) }
        #expect(throws: CalUtilError.self) { try resolve(["--title", "x", "--start", "2026-11-20T19:00", "--url", "example.com"]) }
        #expect(throws: CalUtilError.self) { try resolve(["--title", "x", "--start", "2026-11-20T19:00", "--alarm", "soon"]) }
    }

    @Test func pastAlarmsAreLeftOut() throws {
        // now = 1 Nov 01:00; the event is on 3 Nov 19:00, so "1w" is past but "1d" is not.
        let e = try resolve(["--title", "x", "--start", "2026-11-03T19:00",
                             "--alarm", "1w", "--alarm", "1d", "--alarm", "2026-10-30T09:00"])
        #expect(e.alarms == [.beforeStart(seconds: 86_400)])
        #expect(e.warnings == ["left out alarms that are already in the past: 1 week before, at Fri 30 Oct 2026 09:00"])
        let none = try resolve(["--title", "x", "--start", "2026-11-03T19:00", "--alarm", "1w"])
        #expect(none.alarms.isEmpty)
        #expect(none.warnings == ["left out an alarm that is already in the past: 1 week before (no alarms left; give an --alarm that is still ahead)"])
        // Template alarms point to --add-alarm instead. The event is an hour away.
        let soon = try resolve(["--title", "x", "--start", "2026-11-01T02:00"], template: concert)
        #expect(soon.alarms.isEmpty)
        #expect(soon.warnings == ["left out alarms that are already in the past: 1 day before, 2 hours before (no alarms left; add one with --add-alarm)"])
    }

    @Test func pastEventKeepsItsAlarms() throws {
        let e = try resolve(["--title", "x", "--start", "2026-10-01T19:00"], template: concert)
        #expect(e.alarms == [.beforeStart(seconds: 86_400), .beforeStart(seconds: 7_200)])
        #expect(e.warnings == ["the event starts in the past"])
    }

    @Test func pastAlarmsOnAllDayEvents() throws {
        // Mon 2 Nov, all day: "1d" fired at Sun 1 Nov 00:00, an hour ago; 09:00 on the day is ahead.
        let e = try resolve(["--title", "x", "--start", "2026-11-02", "--all-day", "--alarm", "1d", "--alarm", "09:00"])
        #expect(e.alarms == [.at(utc("2026-11-02T08:00:00Z"))])
        #expect(e.warnings == ["left out an alarm that is already in the past: 1 day before"])
    }

    @Test func alarmLabels() {
        #expect(Alarm.beforeStart(seconds: 0).label == "at the start")
        #expect(Alarm.beforeStart(seconds: 5_400).label == "1 hour 30 minutes before")
        #expect(Alarm.at(now).label == "at")
    }

    @Test func warnsAboutThePast() throws {
        let e = try resolve(["--title", "x", "--start", "2026-10-01T19:00"])
        #expect(e.warnings == ["the event starts in the past"])
    }
}

@Suite struct TemplateFileTests {
    @Test func parsesJSON5() throws {
        let text = """
        {
          // a comment
          concert: { "time": "19:30", "duration": "3h", "alarms": ["1d", "2h"], "allDay": false, },
          birthday: { "allDay": true, "alarms": "09:00" },
        }
        """
        let templates = try TemplateStore.parse(Data(text.utf8), source: "test")
        #expect(templates["concert"]?.alarms == ["1d", "2h"])
        #expect(templates["concert"]?.allDay == false)
        #expect(templates["birthday"]?.alarms == ["09:00"])
    }

    @Test(arguments: [
        #"{"a": {"alarm": "1d"}}"#,        // unknown key (typo)
        #"{"a": {"duration": 3}}"#,        // wrong type
        #"{"a": {"allDay": 1}}"#,          // number, not boolean
        #"{"a": {"alarms": [1, 2]}}"#,
        #"["not", "an", "object"]"#,
        #"{"a": "#,
    ])
    func rejects(_ text: String) {
        #expect(throws: CalUtilError.self) { try TemplateStore.parse(Data(text.utf8), source: "test") }
    }

    @Test func strictJSONRoundTrips() throws {
        let templates = ["concert": concert, "birthday": Template(name: "birthday", url: "https://x.example/a", allDay: true, alarms: [])]
        let json = TemplateStore.json(templates)
        // Strict JSON: parses without JSON5 leniency, and back into the same templates.
        let strict = try JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: [String: Any]]
        #expect(strict?["concert"]?["duration"] as? String == "3h")
        #expect(strict?["birthday"]?["allDay"] as? Bool == true)
        #expect(json.contains("\"https://x.example/a\""))  // slashes not escaped
        #expect(try TemplateStore.parse(Data(json.utf8), source: "test") == templates)
    }

    @Test func defaultPath() {
        #expect(TemplateStore.defaultPath(environment: ["CALUTIL_TEMPLATES": "/x/t.json"]) == "/x/t.json")
        #expect(TemplateStore.defaultPath(environment: ["XDG_CONFIG_HOME": "/cfg"]) == "/cfg/calutil/templates.json")
        #expect(TemplateStore.defaultPath(environment: [:]).hasSuffix("/.config/calutil/templates.json"))
    }
}

@Suite struct ICSTests {
    func render(_ args: [String], template: Template? = nil) throws -> String {
        ICS.render(try resolve(args, template: template), uid: "test-uid", now: now)
    }

    @Test func timedEventWithTimeZone() throws {
        let text = try render(["--template", "concert", "--title", "Beethoven's 9th", "--location", "Sydney Opera House, Bennelong Point",
                               "--start", "2026-11-06T18:00", "--timezone", "Australia/Sydney"], template: concert)
        let lines = text.components(separatedBy: "\r\n")
        #expect(text.hasSuffix("END:VCALENDAR\r\n"))
        #expect(!text.replacingOccurrences(of: "\r\n", with: "").contains("\n"))  // CRLF only
        #expect(lines.contains("DTSTART;TZID=Australia/Sydney:20261106T180000"))
        #expect(lines.contains("DTEND;TZID=Australia/Sydney:20261106T210000"))
        #expect(lines.contains("SUMMARY:Beethoven's 9th"))
        #expect(lines.contains("LOCATION:Sydney Opera House\\, Bennelong Point"))
        #expect(lines.contains("TRIGGER:-P1D"))
        #expect(lines.contains("TRIGGER:-PT2H"))
        #expect(lines.contains("UID:test-uid"))
        #expect(lines.contains("DTSTAMP:20261101T000000Z"))
        // Sydney's daylight-saving changes around the event are described.
        #expect(lines.contains("BEGIN:VTIMEZONE"))
        #expect(lines.contains("TZOFFSETFROM:+1000"))
        #expect(lines.contains("TZOFFSETTO:+1100"))
        #expect(lines.contains("DTSTART:20261004T020000"))  // first Sunday of October, 02:00
    }

    @Test func allDayEvent() throws {
        let text = try render(["--title", "Holiday", "--start", "2026-12-24", "--end", "2026-12-26", "--all-day"])
        #expect(text.contains("DTSTART;VALUE=DATE:20261224\r\n"))
        #expect(text.contains("DTEND;VALUE=DATE:20261227\r\n"))
        #expect(!text.contains("VTIMEZONE"))
    }

    @Test func utcAndAbsoluteAlarm() throws {
        let text = try render(["--title", "x", "--start", "2026-11-20T19:00", "--timezone", "UTC",
                               "--alarm", "2026-11-20T09:00", "--add-alarm", "0"])
        #expect(text.contains("DTSTART:20261120T190000Z\r\n"))
        #expect(text.contains("TRIGGER;VALUE=DATE-TIME:20261120T090000Z\r\n"))
        #expect(text.contains("TRIGGER:PT0S\r\n"))
        #expect(!text.contains("VTIMEZONE"))
    }

    @Test func escapesAndFolds() {
        #expect(ICS.escape("a;b,c\\d\ne") == "a\\;b\\,c\\\\d\\ne")
        let long = "DESCRIPTION:" + String(repeating: "æ", count: 100)
        let folded = ICS.fold(long)
        for line in folded.components(separatedBy: "\r\n") {
            #expect(line.utf8.count <= 75)
        }
        #expect(folded.replacingOccurrences(of: "\r\n ", with: "") == long)
    }
}

@Suite struct SummaryTests {
    @Test func showsLocalTimeForForeignZones() throws {
        let e = try resolve(["--template", "concert", "--title", "Beethoven's 9th", "--start", "2026-11-06T18:00",
                             "--timezone", "Australia/Sydney"], template: concert)
        let text = Summary.render(e, localTimeZone: copenhagen)
        #expect(text.contains("Fri 6 Nov 2026 18:00"))
        #expect(text.contains("Australia/Sydney (UTC+11)"))
        #expect(text.contains("Fri 6 Nov 2026 08:00 – Fri 6 Nov 2026 11:00  Europe/Copenhagen (UTC+1)"))
        #expect(text.contains("1 day before    Thu 5 Nov 2026 18:00"))
        #expect(text.contains("2 hours before  Fri 6 Nov 2026 16:00"))
    }

    @Test func multiLineValuesStayIndented() throws {
        let e = try resolve(["--title", "x", "--start", "2026-11-06T18:00", "--no-alarms",
                             "--location", "Sydney Opera House\nBennelong Point, Sydney NSW 2000, Australia",
                             "--notes", "Row K\r\nSeats 12–13"], local: copenhagen)
        let text = Summary.render(e, localTimeZone: copenhagen)
        #expect(text.contains("""
            Location   Sydney Opera House
                       Bennelong Point, Sydney NSW 2000, Australia
            """))
        #expect(text.contains("""
            Notes      Row K
                       Seats 12–13
            """))
    }
}

// `now` is Sun 1 Nov 2026, 01:00 in Copenhagen.
@Suite struct DayWordTests {
    func day(_ text: String) throws -> String {
        let d = try DateParsing.parseDay(text, now: now, timeZone: copenhagen)
        return String(format: "%04d-%02d-%02d", d.year, d.month, d.day)
    }

    @Test func words() throws {
        #expect(try day("today") == "2026-11-01")
        #expect(try day("Tomorrow") == "2026-11-02")
        #expect(try day("yesterday") == "2026-10-31")
        #expect(try day("sunday") == "2026-11-01")  // today counts
        #expect(try day("mon") == "2026-11-02")
        #expect(try day("thurs") == "2026-11-05")
        #expect(try day("saturday") == "2026-11-07")
        #expect(try day("2026-12-24") == "2026-12-24")
    }

    @Test(arguments: ["", "mo", "someday", "2026-12-24T10:00", "next friday"])
    func rejects(_ text: String) {
        #expect(throws: CalUtilError.self) { try DateParsing.parseDay(text, now: now, timeZone: copenhagen) }
    }

    @Test func dayWordsInAdd() throws {
        let e = try resolve(["--title", "x", "--start", "tomorrow 18:00", "--end", "friday 09:00"])
        #expect(e.start == utc("2026-11-02T17:00:00Z"))
        #expect(e.end == utc("2026-11-06T08:00:00Z"))
        let allDay = try resolve(["--title", "x", "--start", "fri", "--all-day"])
        #expect(allDay.start == utc("2026-11-05T23:00:00Z"))
        let templated = try resolve(["--title", "x", "--start", "tomorrow"], template: concert)
        #expect(templated.start == utc("2026-11-02T18:30:00Z"))
        #expect(throws: CalUtilError.self) { try resolve(["--title", "x", "--start", "tomorrow"]) }
    }

    @Test func compactDurations() {
        #expect(Durations.compact(86_400 + 7_200) == "1d2h")
        #expect(Durations.compact(900) == "15m")
        #expect(Durations.compact(604_800) == "1w")
    }
}

@Suite struct ListTests {
    @Test func parsing() throws {
        #expect(try Invocation.parse(["list"]) == .list(ListOptions()))
        guard case .list(let o) = try Invocation.parse(["list", "friday", "--days", "7", "--calendar", "Home", "--calendar", "Family", "-v"]) else {
            Issue.record("expected list"); return
        }
        #expect(o.day == "friday" && o.days == 7 && o.calendars == ["Home", "Family"] && o.verbose)
        #expect(try Invocation.parse(["list", "-h"]) == .help("list"))
        #expect(throws: CalUtilError.self) { try ListOptions.parse(["today", "tomorrow"]) }
        #expect(throws: CalUtilError.self) { try ListOptions.parse(["--days", "0"]) }
        #expect(throws: CalUtilError.self) { try ListOptions.parse(["--days", "a week"]) }
        #expect(throws: CalUtilError.self) { try ListOptions.parse(["--save"]) }
    }

    let monday = utc("2026-11-01T23:00:00Z")  // Mon 2 Nov 00:00 in Copenhagen

    func event(_ title: String, _ start: String, _ end: String, calendar: String = "Home",
               allDay: Bool = false, zone: TimeZone? = copenhagen, alarms: [Alarm] = []) -> ListedEvent {
        ListedEvent(title: title, calendar: calendar, calendarFullName: "iCloud/\(calendar)",
                    start: utc(start), end: utc(end), isAllDay: allDay, timeZone: allDay ? nil : zone,
                    alarms: alarms, identifier: "id-\(title)")
    }

    func render(_ events: [ListedEvent], days: Int = 1, verbose: Bool = false) -> String {
        EventList.render(events, from: monday, days: days, timeZone: copenhagen, now: now, verbose: verbose)
    }

    @Test func oneDay() {
        let text = render([
            event("Dinner", "2026-11-02T18:00:00Z", "2026-11-02T20:00:00Z", calendar: "Family", alarms: [.beforeStart(seconds: 86_400)]),
            event("Standup", "2026-11-02T08:00:00Z", "2026-11-02T08:15:00Z", calendar: "Work"),
            event("Holiday", "2026-11-01T23:00:00Z", "2026-11-02T22:59:59Z", allDay: true),
            event("Concert", "2026-11-02T07:00:00Z", "2026-11-02T10:00:00Z", zone: sydney, alarms: [.beforeStart(seconds: 7_200), .at(utc("2026-11-02T06:00:00Z"))]),
        ])
        #expect(text == """
        Mon 2 Nov 2026 (tomorrow)
          all day      Holiday  Home
          08:00–11:00  Concert  Home    (18:00 Australia/Sydney)  ⏰ 2h, at 07:00
          09:00–09:15  Standup  Work
          19:00–21:00  Dinner   Family  ⏰ 1d
        """)
    }

    @Test func emptyAndMultiDay() {
        #expect(render([]) == "Mon 2 Nov 2026 (tomorrow)\n  No events.")
        #expect(render([], days: 7) == "No events from Mon 2 Nov 2026 to Sun 8 Nov 2026.")
        // Overnight event shows on both days; the empty day in between is left out.
        let text = render([
            event("Party", "2026-11-02T21:00:00Z", "2026-11-03T01:00:00Z"),
            event("Trip", "2026-11-04T09:00:00Z", "2026-11-04T10:00:00Z"),
        ], days: 3)
        #expect(text == """
        Mon 2 Nov 2026 (tomorrow)
          22:00–…      Party  Home

        Tue 3 Nov 2026
          …–02:00      Party  Home

        Wed 4 Nov 2026
          10:00–11:00  Trip   Home
        """)
    }

    @Test func longTitlesAreShortened() {
        let long = String(repeating: "x", count: 60)
        let text = render([
            event(long, "2026-11-02T08:00:00Z", "2026-11-02T09:00:00Z", calendar: "Work"),
            event("Short", "2026-11-02T10:00:00Z", "2026-11-02T11:00:00Z"),
        ])
        let lines = text.components(separatedBy: "\n")
        #expect(lines[1] == "  09:00–10:00  " + String(repeating: "x", count: 39) + "…  Work")
        #expect(lines[2] == "  11:00–12:00  Short" + String(repeating: " ", count: 35) + "  Home")
        let verbose = render([event(long, "2026-11-02T08:00:00Z", "2026-11-02T09:00:00Z")], verbose: true)
        #expect(verbose.contains("title     " + long))
    }

    @Test func multiLineTitleIsFlattened() {
        let text = render([event("Dinner\n at Mum's", "2026-11-02T18:00:00Z", "2026-11-02T20:00:00Z")])
        #expect(text.hasSuffix("19:00–21:00  Dinner at Mum's  Home"))
    }

    @Test func verbose() {
        var e = event("Dinner", "2026-11-02T18:00:00Z", "2026-11-02T20:00:00Z")
        e.location = "Mum's\nCopenhagen"
        e.notes = "Bring wine\nand dessert"
        e.isRecurring = true
        let text = render([e], verbose: true)
        #expect(text.contains("\n               zone      Europe/Copenhagen\n"))
        #expect(text.contains("\n               where     Mum's\n                         Copenhagen\n"))
        #expect(text.contains("\n               repeats   yes\n"))
        #expect(text.contains("\n               calendar  iCloud/Home\n"))
        #expect(text.contains("\n               id        id-Dinner\n"))
        #expect(text.hasSuffix("\n               notes     Bring wine\n                         and dessert"))
    }
}

/// Regression tests for the whole-repo review.
@Suite struct ReviewFindingTests {
    @Test func allDayTodayIsNotInThePast() throws {
        // now = Sun 1 Nov 01:00. "1w" is past; 09:00 today is still ahead.
        let e = try resolve(["--title", "Mum", "--start", "today", "--all-day", "--alarm", "1w", "--alarm", "09:00"])
        #expect(e.alarms == [.at(utc("2026-11-01T08:00:00Z"))])
        #expect(e.warnings == ["left out an alarm that is already in the past: 1 week before"])
        let yesterday = try resolve(["--title", "x", "--start", "yesterday", "--all-day"])
        #expect(yesterday.warnings == ["the event starts in the past"])
    }

    @Test func offsetInStartIsTheEventsZone() throws {
        let e = try resolve(["--title", "x", "--start", "2026-11-06T18:00+11:00", "--end", "21:00", "--alarm", "09:00"])
        #expect(e.start == utc("2026-11-06T07:00:00Z"))
        #expect(e.end == utc("2026-11-06T10:00:00Z"))  // 3 hours, not 13
        #expect(e.alarms == [.at(utc("2026-11-05T22:00:00Z"))])
        #expect(e.timeZone.secondsFromGMT(for: e.start) == 39_600)
        // An explicit --timezone still wins for everything but the start's own instant.
        let z = try resolve(["--title", "x", "--start", "2026-11-06T18:00+11:00", "--end", "21:00", "--timezone", "Europe/Copenhagen"])
        #expect(z.start == utc("2026-11-06T07:00:00Z"))
        #expect(z.end == utc("2026-11-06T20:00:00Z"))
        #expect(z.timeZone == copenhagen)
        // A UTC start gives a UTC event in the .ics.
        let ics = ICS.render(try resolve(["--title", "x", "--start", "2026-11-06T07:00Z"]), uid: "u", now: now)
        #expect(ics.contains("DTSTART:20261106T070000Z\r\n"))
    }

    @Test func allDayIgnoresATimedTemplatesDuration() throws {
        let dinner = Template(name: "dinner", time: "19:00", duration: "2h30m", alarms: ["3h"])
        let e = try resolve(["--title", "x", "--start", "2026-11-20", "--all-day"], template: dinner)
        #expect(e.isAllDay)
        #expect(e.end.timeIntervalSince(e.start) == 86_400)
        // An all-day template's own duration still applies.
        let trip = Template(name: "trip", duration: "3d", allDay: true)
        let t = try resolve(["--title", "x", "--start", "2026-11-20"], template: trip)
        #expect(t.end.timeIntervalSince(t.start) == 3 * 86_400)
    }

    @Test func helpOnlyInOptionPosition() throws {
        guard case .add(let add) = try Invocation.parse(["add", "--title", "x", "--notes", "-h"]) else {
            Issue.record("expected add"); return
        }
        #expect(add.notes == "-h")
        #expect(try Invocation.parse(["add", "--title", "x", "-h"]) == .help("add"))
        #expect(try Invocation.parse(["list", "--help"]) == .help("list"))
        #expect(try Invocation.parse(["calendars", "-h"]) == .help("calendars"))
        #expect(try Invocation.parse(["templates", "--help"]) == .help("templates"))
    }

    @Test func timezoneAliasCountsAsTheSameOption() throws {
        #expect(throws: CalUtilError.self) { try AddOptions.parse(["--tz", "UTC", "--timezone", "Australia/Sydney"]) }
        #expect(try AddOptions.parse(["--tz", "UTC"]).timezone == "UTC")
    }

    @Test func windowsLineBreaksAreOneBreak() {
        #expect("a\r\nb\nc\rd".lines == ["a", "b", "c", "d"])
        var e = ListedEvent(title: "x", calendar: "Home", calendarFullName: "iCloud/Home",
                            start: utc("2026-11-02T08:00:00Z"), end: utc("2026-11-02T09:00:00Z"))
        e.notes = "Agenda\r\nItem 1"
        let text = EventList.render([e], from: utc("2026-11-01T23:00:00Z"), days: 1, timeZone: copenhagen, now: now, verbose: true)
        #expect(text.hasSuffix("notes     Agenda\n                         Item 1"))
    }

    @Test func trimmedNonEmpty() {
        #expect(CalUtilCore.trimmedNonEmpty("  Pilates \n") == "Pilates")
        #expect(CalUtilCore.trimmedNonEmpty(" \n ") == nil)
        #expect(CalUtilCore.trimmedNonEmpty(nil) == nil)
    }
}

/// Regression tests for the second whole-repo review.
@Suite struct ReviewFindingTests2 {
    let santiago = TimeZone(identifier: "America/Santiago")!

    @Test func allDayWhereDSTSkipsMidnight() throws {
        // Chile's clocks jump from 00:00 to 01:00 on 6 Sep 2026: that day starts at 01:00.
        #expect(throws: CalUtilError.self) {
            try DateParsing.makeDate(year: 2026, month: 9, day: 6, time: TimeOfDay(hour: 0, minute: 0), timeZone: santiago)
        }
        let dayStart = try DateParsing.startOfDay(year: 2026, month: 9, day: 6, timeZone: santiago)
        #expect(DateParsing.gregorian(santiago).component(.hour, from: dayStart) == 1)

        let one = try resolve(["--title", "x", "--start", "2026-09-06", "--all-day"], local: santiago)
        #expect(one.start == dayStart)
        let span = try resolve(["--title", "x", "--start", "2026-09-05", "--end", "2026-09-06", "--all-day"], local: santiago)
        // Ends at the start of 7 Sep, which is midnight again, not 01:00.
        #expect(span.end == utc("2026-09-07T03:00:00Z"))
        let three = try resolve(["--title", "x", "--start", "2026-09-05", "--duration", "3d", "--all-day"], local: santiago)
        #expect(three.end == utc("2026-09-08T03:00:00Z"))
        // The list's day boundaries snap the same way.
        let event = ListedEvent(title: "Late", calendar: "Home", calendarFullName: "iCloud/Home",
                                start: utc("2026-09-07T03:30:00Z"), end: utc("2026-09-07T04:00:00Z"))  // 7 Sep 00:30
        let text = EventList.render([event], from: dayStart, days: 2, timeZone: santiago, now: now, verbose: false)
        #expect(text.hasPrefix("Mon 7 Sep 2026\n  00:30–01:00"))
    }

    @Test func noAllDayIgnoresAnAllDayTemplatesDuration() throws {
        let trip = Template(name: "trip", duration: "3d", allDay: true)
        let e = try resolve(["--title", "x", "--start", "2026-11-20T09:00", "--no-all-day"], template: trip)
        #expect(!e.isAllDay)
        #expect(e.end.timeIntervalSince(e.start) == 3_600)
    }

    @Test func offsetMatchingTheMacKeepsItsNamedZone() throws {
        let sydneyMac = try resolve(["--title", "x", "--start", "2026-11-06T18:00+11:00"], local: sydney)
        #expect(sydneyMac.timeZone == sydney)
        let copenhagenMac = try resolve(["--title", "x", "--start", "2026-11-06T18:00+01:00", "--end", "21:00"])
        #expect(copenhagenMac.timeZone == copenhagen)
        #expect(copenhagenMac.end == utc("2026-11-06T20:00:00Z"))
        // A different offset still gets a fixed zone (see offsetInStartIsTheEventsZone).
        let other = try resolve(["--title", "x", "--start", "2026-11-06T18:00+11:00"])
        #expect(other.timeZone.identifier == "GMT+1100")
    }

    @Test func messagesNameTheOptionAsTyped() {
        func message(_ body: () throws -> Any) -> String {
            do { _ = try body(); return "" } catch { return (error as? CalUtilError)?.message ?? "" }
        }
        #expect(message { try Invocation.parse(["list", "--title", "x"]) }.contains("unknown option --title for 'calutil list'"))
        #expect(message { try AddOptions.parse(["--tz"]) } == "--tz needs a value")
        #expect(message { try AddOptions.parse(["--tz", "UTC", "--timezone", "UTC"]) } == "--timezone / --tz was given more than once")
        #expect(message { try AddOptions.parse(["--save", "--open"]) } == "--save and --open can't be combined; pick one")
    }

    @Test func emptyTemplateMeansNone() throws {
        #expect(try AddOptions.parse(["--template", ""]).template == nil)
        #expect(try AddOptions.parse(["--template", " concert "]).template == "concert")
    }

    @Test func everyTemplateSettingRoundTrips() throws {
        let all = Template(name: "all", title: "T", location: "L", map: "1,2", notes: "N", url: "https://u.example",
                           calendar: "C", timezone: "UTC", time: "19:30", duration: "2h", allDay: false, alarms: ["1d"])
        #expect(try TemplateStore.parse(Data(TemplateStore.json(["all": all]).utf8), source: "test") == ["all": all])
        #expect(Template.allKeys == ["title", "location", "map", "notes", "url", "calendar", "timezone", "time", "duration", "allDay", "alarms"])
    }

    @Test func zeroLengthAndLongEventsInTheSinglePass() {
        let monday = utc("2026-11-01T23:00:00Z")
        let at = ListedEvent(title: "Ping", calendar: "Home", calendarFullName: "iCloud/Home",
                             start: utc("2026-11-03T08:00:00Z"), end: utc("2026-11-03T08:00:00Z"))
        let trip = ListedEvent(title: "Trip", calendar: "Home", calendarFullName: "iCloud/Home",
                               start: utc("2026-10-31T23:00:00Z"), end: utc("2026-11-03T22:59:59Z"), isAllDay: true)
        let text = EventList.render([at, trip], from: monday, days: 3, timeZone: copenhagen, now: now, verbose: false)
        #expect(text == """
        Mon 2 Nov 2026 (tomorrow)
          all day      Trip  Home

        Tue 3 Nov 2026
          all day      Trip  Home
          09:00        Ping  Home
        """)
    }
}

/// Time-zone corner cases: a day that starts at 01:00 (Santiago), an explicit UTC time next
/// to a daylight-saving change (London), and the Mac's own offset (Sydney).
@Suite struct TimeZoneEdgeTests {
    let santiago = TimeZone(identifier: "America/Santiago")!
    let london = TimeZone(identifier: "Europe/London")!
    let sydney = TimeZone(identifier: "Australia/Sydney")!

    @Test func daysAreCountedByDate() throws {
        let calendar = DateParsing.gregorian(santiago)
        let sixth = try DateParsing.startOfDay(year: 2026, month: 9, day: 6, timeZone: santiago)  // 01:00
        let seventh = DateParsing.startOfDay(1, after: sixth, calendar: calendar)                // 00:00
        #expect(DateParsing.daysBetween(sixth, seventh, calendar: calendar) == 1)
        #expect(DateParsing.daysBetween(seventh, sixth, calendar: calendar) == -1)
        #expect(DateParsing.daysBetween(sixth, sixth.addingTimeInterval(3_600), calendar: calendar) == 0)
    }

    @Test func listLabelsTomorrowAfterADayStartingAt1() throws {
        let sixth = try DateParsing.startOfDay(year: 2026, month: 9, day: 6, timeZone: santiago)
        let noonOnSixth = utc("2026-09-06T15:00:00Z")
        let events = [
            ListedEvent(title: "A", calendar: "Home", calendarFullName: "iCloud/Home",
                        start: utc("2026-09-06T16:00:00Z"), end: utc("2026-09-06T17:00:00Z")),
            ListedEvent(title: "B", calendar: "Home", calendarFullName: "iCloud/Home",
                        start: utc("2026-09-07T16:00:00Z"), end: utc("2026-09-07T17:00:00Z")),
        ]
        let text = EventList.render(events, from: sixth, days: 2, timeZone: santiago, now: noonOnSixth, verbose: false)
        #expect(text.contains("Sun 6 Sep 2026 (today)"))
        #expect(text.contains("Mon 7 Sep 2026 (tomorrow)"))
    }

    @Test func allDaySummaryCountsDaysByDate() throws {
        let e = try resolve(["--title", "x", "--start", "2026-09-06", "--duration", "3d", "--all-day"], local: santiago)
        let text = Summary.render(e, localTimeZone: santiago)
        #expect(text.contains("Sun 6 Sep 2026 – Tue 8 Sep 2026 (all day, 3 days)"))
        let one = try resolve(["--title", "x", "--start", "2026-09-06", "--all-day"], local: santiago)
        #expect(Summary.render(one, localTimeZone: santiago).contains("Sun 6 Sep 2026 (all day)"))
    }

    @Test func zMeansUTCEvenWhenItIsTheLocalOffset() throws {
        // London is on UTC until 01:00 UTC on 29 Mar 2026, then on UTC+1.
        let e = try resolve(["--title", "x", "--start", "2026-03-28T23:00Z", "--end", "02:00"], local: london)
        #expect(ICS.isUTC(e.timeZone))
        #expect(e.end.timeIntervalSince(e.start) == 3 * 3_600)
        let ics = ICS.render(e, uid: "u", now: now)
        #expect(ics.contains("DTSTART:20260328T230000Z"))
        #expect(!ics.contains("TZID=Europe/London"))
    }

    @Test func theMacsOwnOffsetKeepsItsNamedZone() throws {
        let e = try resolve(["--title", "x", "--start", "2026-11-20T19:00+11:00"], local: sydney)
        #expect(e.timeZone.identifier == "Australia/Sydney")
        let other = try resolve(["--title", "x", "--start", "2026-11-20T19:00+10:00"], local: sydney)
        #expect(other.timeZone.secondsFromGMT() == 36_000)
    }

    @Test func aRolledOverEndInADaylightSavingGapIsAnError() throws {
        // 00:30 on 6 Sep doesn't exist in Santiago.
        #expect(throws: CalUtilError.self) {
            try resolve(["--title", "x", "--start", "2026-09-05T23:00", "--end", "00:30"], local: santiago)
        }
        // From 01:30 on the 6th, 00:30 is on the 7th, which exists.
        let e = try resolve(["--title", "x", "--start", "2026-09-06T01:30", "--end", "00:30"], local: santiago)
        #expect(e.end == utc("2026-09-07T03:30:00Z"))
        // Later on the clock than the start: the same day.
        let same = try resolve(["--title", "x", "--start", "2026-09-06T18:00", "--end", "21:00"], local: santiago)
        #expect(same.end.timeIntervalSince(same.start) == 3 * 3_600)
    }

    @Test func aDroppedTemplateDurationIsWarnedAbout() throws {
        let timed = Template(name: "gig", duration: "3h")
        let allDay = try resolve(["--title", "x", "--start", "2026-11-20", "--all-day"], template: timed)
        #expect(allDay.warnings.contains { $0.contains("ignored the template's duration 3h") })
        let trip = Template(name: "trip", duration: "3d", allDay: true)
        let notAllDay = try resolve(["--title", "x", "--start", "2026-11-20T09:00", "--no-all-day"], template: trip)
        #expect(notAllDay.warnings.contains { $0.contains("ignored the template's duration 3d") })
        // No warning when the command line sets the length anyway.
        let given = try resolve(["--title", "x", "--start", "2026-11-20", "--all-day", "--duration", "2d"], template: timed)
        #expect(!given.warnings.contains { $0.contains("duration") })
    }
}

@Suite struct MapTests {
    let operaHouse = Place(name: "Sydney Opera House", address: "Bennelong Point, Sydney NSW 2000, Australia",
                           latitude: -33.8568674, longitude: 151.2152855)
    let carPark = Place(name: "Wilson Parking", address: "2A Macquarie St, Sydney NSW 2000, Australia",
                        latitude: -33.8593064, longitude: 151.2135351)

    @Test func coordinates() {
        #expect(Places.parseCoordinates("-33.8569,151.2153") == Place(latitude: -33.8569, longitude: 151.2153))
        #expect(Places.parseCoordinates(" -33.8569 , 151.2153 ") != nil)
        for bad in ["Sydney Opera House", "-33.8569", "91,0", "0,181", "1,2,3", "1e3,2", ",", "a,b"] {
            #expect(Places.parseCoordinates(bad) == nil, "\(bad)")
        }
        #expect(operaHouse.coordinates == "-33.8569, 151.2153")
        #expect(operaHouse.locationText == "Sydney Opera House\nBennelong Point, Sydney NSW 2000, Australia")
    }

    @Test func bestMatchPrefersTheName() {
        #expect(Places.query(for: "Sydney Opera House\n Bennelong Point ") == "Sydney Opera House, Bennelong Point")
        #expect(Places.bestMatch([carPark, operaHouse], for: "sydney opera house") == 1)
        #expect(Places.bestMatch([carPark, operaHouse], for: "Sydney Opera House, Bennelong Point") == 1)
        #expect(Places.bestMatch([carPark, operaHouse], for: "2A Macquarie St") == 0)
        let cafe = Place(name: "Café Sydney", latitude: 0, longitude: 0)
        #expect(Places.bestMatch([carPark, cafe], for: "Cafe Sydney") == 1)
    }

    @Test func choosing() throws {
        var event = try resolve(["--title", "x", "--start", "2026-11-20T19:00", "--location", "Sydney Opera House"])
        try Places.choose(from: [carPark, operaHouse], query: "Sydney Opera House", pick: nil, for: &event)
        #expect(event.place == operaHouse)
        #expect(event.location == "Sydney Opera House")  // the given text is kept
        try Places.choose(from: [carPark, operaHouse], query: "Sydney Opera House", pick: 1, for: &event)
        #expect(event.place == carPark)
        #expect(throws: CalUtilError.self) {
            try Places.choose(from: [carPark, operaHouse], query: "Sydney Opera House", pick: 3, for: &event)
        }
        #expect(throws: CalUtilError.self) {
            try Places.choose(from: [], query: "Sydney Opera House", pick: 1, for: &event)
        }

        var plain = try resolve(["--title", "x", "--start", "2026-11-20T19:00", "--location", "Nowhere"])
        try Places.choose(from: [], query: "Nowhere", pick: nil, for: &plain)
        #expect(plain.place == nil)
        #expect(plain.warnings.contains { $0.hasPrefix("nothing found on the map for 'Nowhere'") })

        // With --map and no --location, the place gives the location text.
        var found = try resolve(["--title", "x", "--start", "2026-11-20T19:00", "--map", "Sydney Opera House"])
        try Places.choose(from: [operaHouse], query: "Sydney Opera House", pick: nil, for: &found)
        #expect(found.location == "Sydney Opera House\nBennelong Point, Sydney NSW 2000, Australia")
    }

    @Test func whatToLookUp() throws {
        let base = ["--title", "x", "--start", "2026-11-20T19:00"]
        #expect(try resolve(base).map == .none)
        #expect(try resolve(base + ["--location", "Sydney Opera House\nBennelong Point"]).map
                == .search("Sydney Opera House, Bennelong Point", pick: nil))
        #expect(try resolve(base + ["--location", "Home", "--map", "City Recital Hall", "--map-match", "2"]).map
                == .search("City Recital Hall", pick: 2))
        #expect(try resolve(base + ["--location", "Home", "--map", "-33.8569, 151.2153"]).map
                == .place(Place(latitude: -33.8569, longitude: 151.2153)))
        #expect(try resolve(base + ["--location", "Home", "--no-map"]).map == .none)
        // A template's location is looked up too.
        #expect(try resolve(base, template: Template(name: "t", location: "Hall")).map == .search("Hall", pick: nil))

        #expect(throws: CalUtilError.self) { try resolve(base + ["--map-match", "1"]) }
        #expect(throws: CalUtilError.self) { try resolve(base + ["--map", "-33.8569,151.2153", "--map-match", "1"]) }
        #expect(throws: CalUtilError.self) { try AddOptions.parse(["--no-map", "--map", "Hall"]) }
        #expect(throws: CalUtilError.self) { try AddOptions.parse(["--no-map", "--map-match", "1"]) }
        #expect(throws: CalUtilError.self) { try AddOptions.parse(["--map-match", "0"]) }
        #expect(throws: CalUtilError.self) { try AddOptions.parse(["--map-match", "6"]) }
    }

    @Test func summaryAndICS() throws {
        var event = try resolve(["--title", "x", "--start", "2026-11-20T19:00", "--no-alarms",
                                 "--location", "Sydney Opera House"], local: TimeZone(identifier: "Australia/Sydney")!)
        try Places.choose(from: [carPark, operaHouse], query: "Sydney Opera House", pick: nil, for: &event)

        let dryRun = Summary.render(event, localTimeZone: TimeZone(identifier: "Australia/Sydney")!, listMatches: true)
        #expect(dryRun.contains("""
            Map        1    Wilson Parking, 2A Macquarie St, Sydney NSW 2000, Australia
                       2 ✓  Sydney Opera House, Bennelong Point, Sydney NSW 2000, Australia  (-33.8569, 151.2153)
                       pick another with --map-match N
            """))
        let saved = Summary.render(event, localTimeZone: TimeZone(identifier: "Australia/Sydney")!)
        #expect(saved.contains("Map        Sydney Opera House, Bennelong Point, Sydney NSW 2000, Australia  (-33.8569, 151.2153)\n"))

        let ics = ICS.render(event, uid: "u", now: now).replacingOccurrences(of: "\r\n ", with: "")
        #expect(ics.contains("GEO:-33.856867;151.215285\r\n"))
        #expect(ics.contains("X-APPLE-STRUCTURED-LOCATION;VALUE=URI;X-ADDRESS=\"Bennelong Point, Sydney NSW 2000, Australia\";X-TITLE=Sydney Opera House:geo:-33.856867,151.215285\r\n"))
        #expect(ICS.parameter("Say \"hi\"\nthere; now") == "\"Say 'hi' there; now\"")
    }

    @Test func listShowsTheMapPoint() {
        let event = ListedEvent(title: "Gig", calendar: "Home", calendarFullName: "iCloud/Home",
                                start: utc("2026-11-20T08:00:00Z"), end: utc("2026-11-20T10:00:00Z"),
                                location: "Sydney Opera House", place: operaHouse)
        let text = EventList.render([event], from: utc("2026-11-19T13:00:00Z"), days: 1,
                                    timeZone: TimeZone(identifier: "Australia/Sydney")!, now: now, verbose: true)
        #expect(text.contains("map       -33.8569, 151.2153"))
    }
}

@Suite struct TemplateMapTests {
    let venue = Template(name: "opera_house", location: "Sydney Opera House\nBennelong Point, Sydney NSW 2000, Australia",
                         map: "-33.8569,151.2153", duration: "2h")
    let base = ["--title", "x", "--start", "2026-11-20T19:00"]
    let point = MapRequest.place(Place(latitude: -33.8569, longitude: 151.2153))

    @Test func templateMapWithItsOwnLocation() throws {
        #expect(try resolve(base, template: venue).map == point)
        // The same location given on the command line too.
        #expect(try resolve(base + ["--location", "Sydney Opera House\nBennelong Point, Sydney NSW 2000, Australia"],
                            template: venue).map == point)
    }

    @Test func anotherLocationIsSearchedInstead() throws {
        #expect(try resolve(base + ["--location", "City Recital Hall"], template: venue).map
                == .search("City Recital Hall", pick: nil))
    }

    @Test func commandLineWins() throws {
        #expect(try resolve(base + ["--map", "Sydney Opera House"], template: venue).map
                == .search("Sydney Opera House", pick: nil))
        // --map "" drops the template's map; the location is searched.
        #expect(try resolve(base + ["--map", ""], template: venue).map
                == .search("Sydney Opera House, Bennelong Point, Sydney NSW 2000, Australia", pick: nil))
        #expect(try resolve(base + ["--no-map"], template: venue).map == .none)
        #expect(throws: CalUtilError.self) { try resolve(base + ["--map-match", "2"], template: venue) }
    }

    @Test func parsedAndListed() throws {
        let file = try TemplateStore.parse(Data(#"{"v": {"location": "Hall", "map": "1,2"}}"#.utf8), source: "t")
        #expect(file["v"]?.map == "1,2")
        #expect(TemplateStore.json(file).contains(#""map" : "1,2""#))
    }
}

@Suite struct ListAlarmOrderTests {
    @Test func alarmsAreListedInTheOrderTheyGoOff() {
        let start = utc("2027-06-12T09:00:00Z")
        let event = ListedEvent(title: "Dvořák", calendar: "Home", calendarFullName: "iCloud/Home",
                                start: start, end: start.addingTimeInterval(7_200),
                                alarms: [.beforeStart(seconds: 2 * 86_400), .beforeStart(seconds: -900),
                                         .at(start.addingTimeInterval(-3_600)), .beforeStart(seconds: 7 * 86_400)])
        let text = EventList.render([event], from: utc("2027-06-11T14:00:00Z"), days: 1,
                                    timeZone: TimeZone(identifier: "Australia/Sydney")!, now: now, verbose: false)
        #expect(text.contains("⏰ 1w, 2d, at 18:00, 15m after"))
    }
}

@Suite struct SearchTests {
    let sydney = TimeZone(identifier: "Australia/Sydney")!
    let dvorak = ListedEvent(title: "Dvořák’s Symphony of the World", calendar: "Home", calendarFullName: "iCloud/Home",
                             start: utc("2027-06-12T09:00:00Z"), end: utc("2027-06-12T11:00:00Z"),
                             location: "Sydney Opera House\nBennelong Point, Sydney NSW 2000, Australia",
                             notes: "Row K")
    let dentist = ListedEvent(title: "Dentist", calendar: "Home", calendarFullName: "iCloud/Home",
                              start: utc("2026-12-01T22:00:00Z"), end: utc("2026-12-01T23:00:00Z"))

    func options(_ args: [String]) throws -> SearchOptions { try SearchOptions.parse(args) }

    @Test func parsing() throws {
        let o = try options(["new", "world", "--location", " opera ", "--from", "2026-01-01", "--to", "today",
                             "--calendar", "Home", "--calendar", "Family", "-v"])
        #expect(o.text == "new world")
        #expect(o.location == "opera")
        #expect(o.from == "2026-01-01" && o.to == "today")
        #expect(o.calendars == ["Home", "Family"])
        #expect(o.verbose)
        #expect(try Invocation.parse(["search", "dvorak"]) == .search(try options(["dvorak"])))
        #expect(try Invocation.parse(["search", "--help"]) == .help("search"))
        #expect(throws: CalUtilError.self) { try options([]) }
        #expect(throws: CalUtilError.self) { try options(["--title", " "]) }
        #expect(throws: CalUtilError.self) { try options(["x", "--days", "3"]) }
        #expect(Help.text(for: "search") != nil)
    }

    @Test func matching() throws {
        func finds(_ args: [String], _ event: ListedEvent) throws -> Bool { EventSearch.matches(event, try options(args)) }
        #expect(try finds(["dvorak"], dvorak))
        #expect(try finds(["DVORAK'S"], dvorak))                 // straight quote finds the curly one
        #expect(try finds(["symphony", "dvořák"], dvorak))      // words in any order
        #expect(try finds(["opera", "house", "bennelong"], dvorak))  // across the location's lines
        #expect(try finds(["dvorak", "bennelong", "row"], dvorak))   // title, location and notes together
        #expect(try finds(["--title", "world", "--location", "opera"], dvorak))
        #expect(!(try finds(["--title", "opera"], dvorak)))      // the opera house is the location
        #expect(!(try finds(["dvorak", "--notes", "row j"], dvorak)))
        #expect(!(try finds(["mahler"], dvorak)))
        #expect(!(try finds(["--location", "opera"], dentist)))  // no location at all
    }

    @Test func range() throws {
        let now = utc("2026-11-07T01:00:00Z")  // Sat 7 Nov 2026 12:00 in Sydney
        let year = try EventSearch.range(try options(["x"]), now: now, timeZone: sydney)
        #expect(year.first == utc("2026-11-06T13:00:00Z"))   // today, from midnight
        #expect(year.end == utc("2027-11-06T13:00:00Z"))     // to the same day next year
        #expect(year.days == 365)

        let back = try EventSearch.range(try options(["x", "--from", "2025-01-01", "--to", "2025-01-31"]),
                                         now: now, timeZone: sydney)
        #expect(back.days == 31)
        let oneDay = try EventSearch.range(try options(["x", "--from", "today", "--to", "today"]), now: now, timeZone: sydney)
        #expect(oneDay.days == 1)

        let backwards = try options(["x", "--to", "2026-01-01"])
        #expect(throws: CalUtilError.self) { try EventSearch.range(backwards, now: now, timeZone: sydney) }
        #expect(throws: CalUtilError.self) {
            try EventSearch.range(try options(["x", "--from", "1900-01-01", "--to", "2026-01-01"]), now: now, timeZone: sydney)
        }
        #expect(throws: CalUtilError.self) {
            try EventSearch.range(try options(["x", "--from", "someday"]), now: now, timeZone: sydney)
        }
    }

    @Test func windowsStayUnderEventKitsLimit() {
        let calendar = DateParsing.gregorian(sydney)
        let first = utc("2016-01-01T00:00:00Z"), end = utc("2026-06-01T00:00:00Z")
        let windows = EventSearch.windows(from: first, to: end, calendar: calendar)
        #expect(windows.count == 4)
        #expect(windows.first?.start == first && windows.last?.end == end)
        #expect(zip(windows, windows.dropFirst()).allSatisfy { $0.end == $1.start })
        #expect(windows.allSatisfy { $0.end.timeIntervalSince($0.start) < 4 * 365 * 86_400 })
    }

    @Test func rendering() throws {
        let now = utc("2026-11-07T01:00:00Z")
        let o = try options(["dvorak"])
        let r = try EventSearch.range(o, now: now, timeZone: sydney)
        let text = EventSearch.render([dvorak, dentist], options: o, first: r.first, end: r.end, days: r.days,
                                      timeZone: sydney, now: now)
        #expect(text == """
            Sat 12 Jun 2027
              19:00–21:00  Dvořák’s Symphony of the World  Home

            1 event matching 'dvorak' from Sat 7 Nov 2026 to Sat 6 Nov 2027.
            """)
        let none = EventSearch.render([dentist], options: try options(["mahler", "--location", "town hall"]),
                                      first: r.first, end: r.end, days: r.days, timeZone: sydney, now: now)
        #expect(none == "No events matching 'mahler', location 'town hall' from Sat 7 Nov 2026 to Sat 6 Nov 2027.")
    }
}

@Suite struct EditTests {
    let sydney = TimeZone(identifier: "Australia/Sydney")!
    let now = utc("2026-11-07T01:00:00Z")  // Sat 7 Nov 2026 12:00 in Sydney
    let operaHouse = Place(name: "Sydney Opera House", address: "Bennelong Point, Sydney NSW 2000, Australia",
                           latitude: -33.8568674, longitude: 151.2152855)
    /// Sat 11 Sep 2027 20:00–22:00 in Sydney (UTC+10).
    var concert: EventSpec {
        EventSpec(title: "Prokofiev's Seconds Piano Concerto", location: "Sydney Opera House", url: nil,
                  calendarName: "iCloud/Home", timeZone: sydney, isAllDay: false,
                  start: utc("2027-09-11T10:00:00Z"), end: utc("2027-09-11T12:00:00Z"),
                  alarms: [.beforeStart(seconds: 7 * 86_400), .beforeStart(seconds: 2 * 86_400)], place: operaHouse)
    }

    func edit(_ args: [String], _ event: EventSpec? = nil) throws -> EventSpec {
        let options = try EditOptions.parse(["--id", "x"] + args)
        return try Editor.apply(options.changes, to: event ?? concert, now: now, localTimeZone: sydney)
    }

    @Test func parsing() throws {
        let o = try EditOptions.parse(["--match", "lena berg", "--match-calendar", "Home", "--on", "2027-07-05",
                                       "--title", "New", "--calendar", "Family", "--future", "--save"])
        #expect(o.selection.search.text == "lena berg")
        #expect(o.selection.search.calendars == ["Home"])
        #expect(o.selection.searchOptions.from == "2027-07-05" && o.selection.searchOptions.to == "2027-07-05")
        #expect(o.changes.title == "New" && o.changes.calendar == "Family")
        #expect(o.future && o.save)
        #expect(try Invocation.parse(["edit", "--help"]) == .help("edit"))
        #expect(try Invocation.parse(["delete", "--id", "x", "--yes"]) == .delete({
            var d = DeleteOptions(); d.selection.id = "x"; d.confirmed = true; return d }()))

        #expect(throws: CalUtilError.self) { try EditOptions.parse(["--title", "x"]) }               // which event?
        #expect(throws: CalUtilError.self) { try EditOptions.parse(["--id", "x"]) }                  // nothing to change
        #expect(throws: CalUtilError.self) { try EditOptions.parse(["--id", "x", "--match", "y", "--title", "z"]) }
        #expect(throws: CalUtilError.self) { try EditOptions.parse(["--id", "x", "--from", "today", "--title", "z"]) }
        #expect(throws: CalUtilError.self) { try EditOptions.parse(["--match", "x", "--on", "today", "--to", "friday", "--title", "z"]) }
        #expect(throws: CalUtilError.self) { try EditOptions.parse(["--id", "x", "--template", "concert"]) }
        #expect(throws: CalUtilError.self) { try EditOptions.parse(["--id", "x", "--end", "21:00", "--duration", "1h"]) }
        #expect(throws: CalUtilError.self) { try DeleteOptions.parse(["--id", "x", "--title", "y"]) }
        #expect(throws: CalUtilError.self) { try DeleteOptions.parse(["--yes"]) }
    }

    @Test func onlyWhatIsGivenChanges() throws {
        let e = try edit(["--title", "Prokofiev's Second Piano Concerto"])
        var expected = concert
        expected.title = "Prokofiev's Second Piano Concerto"
        #expect(e == expected)
        #expect(Editor.differences(from: concert, to: e, localTimeZone: sydney) == """
            Title  - Prokofiev's Seconds Piano Concerto
                   + Prokofiev's Second Piano Concerto
            """)
        #expect(throws: CalUtilError.self) { try edit(["--title", " "]) }
        #expect(Editor.differences(from: concert, to: try edit(["--calendar", "iCloud/Home"]), localTimeZone: sydney) == nil)
    }

    @Test func clearingAndSettingFields() throws {
        let e = try edit(["--notes", "Row K", "--url", "https://example.com", "--location", ""])
        #expect(e.notes == "Row K")
        #expect(e.url?.absoluteString == "https://example.com")
        #expect(e.location == nil && e.place == nil && e.map == .none)  // no location, no map
        #expect(throws: CalUtilError.self) { try edit(["--url", "example.com"]) }
    }

    @Test func movingKeepsTheLength() throws {
        let later = try edit(["--start", "2027-09-11T19:30"])
        #expect(later.start == utc("2027-09-11T09:30:00Z"))
        #expect(later.end == utc("2027-09-11T11:30:00Z"))
        // A day alone keeps the clock time.
        let nextDay = try edit(["--start", "2027-09-12"])
        #expect(nextDay.start == utc("2027-09-12T10:00:00Z"))
        // Changing only the end.
        #expect(try edit(["--end", "23:00"]).end == utc("2027-09-11T13:00:00Z"))
        #expect(try edit(["--duration", "90m"]).end == utc("2027-09-11T11:30:00Z"))
        // Relative alarms follow the start; that is not a change to the alarms.
        #expect(later.alarms == concert.alarms)
    }

    @Test func aNewZoneKeepsTheClockTime() throws {
        let e = try edit(["--timezone", "Europe/Copenhagen"])
        #expect(e.timeZone.identifier == "Europe/Copenhagen")
        #expect(e.start == utc("2027-09-11T18:00:00Z"))  // 20:00 in Copenhagen (UTC+2)
        #expect(e.end.timeIntervalSince(e.start) == 7_200)
    }

    @Test func allDayAndBack() throws {
        let allDay = try edit(["--all-day"])
        #expect(allDay.isAllDay)
        #expect(allDay.start == utc("2027-09-10T14:00:00Z"))  // midnight in Sydney
        #expect(allDay.end == utc("2027-09-11T14:00:00Z"))
        #expect(throws: CalUtilError.self) { try edit(["--no-all-day"], allDay) }
        #expect(throws: CalUtilError.self) { try edit(["--no-all-day", "--start", "2027-09-11"], allDay) }
        let timed = try edit(["--no-all-day", "--start", "2027-09-11T20:00"], allDay)
        #expect(!timed.isAllDay && timed.end.timeIntervalSince(timed.start) == 3_600)
        // A two-day all-day event keeps its days when moved.
        let twoDays = try edit(["--duration", "2d"], allDay)
        let moved = try edit(["--start", "2027-10-01"], twoDays)
        #expect(moved.end == utc("2027-10-02T14:00:00Z"))
    }

    @Test func alarms() throws {
        #expect(try edit(["--no-alarms"]).alarms.isEmpty)
        #expect(try edit(["--alarm", "1d"]).alarms == [.beforeStart(seconds: 86_400)])
        #expect(try edit(["--add-alarm", "1h", "--add-alarm", "2d"]).alarms
                == [.beforeStart(seconds: 7 * 86_400), .beforeStart(seconds: 2 * 86_400), .beforeStart(seconds: 3_600)])
        // A new alarm already in the past is left out with a warning; existing ones stay.
        let soon = EventSpec(title: "Soon", timeZone: sydney, isAllDay: false, start: utc("2026-11-08T01:00:00Z"),
                             end: utc("2026-11-08T02:00:00Z"), alarms: [.beforeStart(seconds: 7 * 86_400)])
        let e = try edit(["--add-alarm", "2d", "--add-alarm", "1h"], soon)
        #expect(e.alarms == [.beforeStart(seconds: 7 * 86_400), .beforeStart(seconds: 3_600)])
        #expect(e.warnings.contains { $0.contains("2 days before") })
    }

    @Test func map() throws {
        #expect(try edit(["--no-map"]).place == nil)
        #expect(try edit(["--location", "City Recital Hall"]).map == .search("City Recital Hall", pick: nil))
        #expect(try edit(["--location", "City Recital Hall"]).place == nil)
        var plain = concert
        plain.place = nil
        #expect(try edit(["--map", "-33.8569,151.2153"], plain).map == .place(Place(latitude: -33.8569, longitude: 151.2153)))
        #expect(try edit(["--map", "Sydney Opera House", "--map-match", "2"], plain).map == .search("Sydney Opera House", pick: 2))
        #expect(throws: CalUtilError.self) { try edit(["--map-match", "2"]) }
        // An unchanged location keeps its map point.
        #expect(try edit(["--title", "x"]).place == operaHouse)
    }

    @Test func differencesShowOldAndNew() throws {
        let e = try edit(["--start", "2027-09-11T19:30", "--location", "City Recital Hall", "--no-alarms"])
        let text = Editor.differences(from: concert, to: e, localTimeZone: sydney)
        #expect(text == """
            Location  - Sydney Opera House
                      + City Recital Hall
            Map       - Sydney Opera House, Bennelong Point, Sydney NSW 2000, Australia  (-33.8569, 151.2153)
                      + (none)
            Starts    - Sat 11 Sep 2027 20:00
                      + Sat 11 Sep 2027 19:30
            Ends      - Sat 11 Sep 2027 22:00  (2 hours)
                      + Sat 11 Sep 2027 21:30  (2 hours)
            Alarms    - 1 week before  Sat 4 Sep 2027 20:00
                      - 2 days before  Thu 9 Sep 2027 20:00
                      + none
            """)
        #expect(Editor.describe(concert) == "“Prokofiev's Seconds Piano Concerto” on Sat 11 Sep 2027 20:00 in iCloud/Home")
    }
}

@Suite struct ListTimeZoneTests {
    let sydney = TimeZone(identifier: "Australia/Sydney")!
    let copenhagen = TimeZone(identifier: "Europe/Copenhagen")!
    let now = utc("2026-11-07T01:00:00Z")

    @Test func parsing() throws {
        #expect(try ListOptions.parse(["friday", "--tz", "Europe/Copenhagen"]).timezone == "Europe/Copenhagen")
        #expect(try SearchOptions.parse(["x", "--timezone", "UTC"]).timezone == "UTC")
        #expect(throws: CalUtilError.self) { try ListOptions.parse(["--tz", "UTC", "--timezone", "UTC"]) }
        #expect(throws: CalUtilError.self) { try DateParsing.timeZone(named: "Mars/Olympus") }
        #expect(try DateParsing.timeZone(named: " Europe/Copenhagen ").identifier == "Europe/Copenhagen")
    }

    @Test func timedEventsMoveAndAllDayEventsKeepTheirDate() throws {
        // Copenhagen's Saturday: Sat 14 Nov 00:00 CET = 13 Nov 23:00 UTC.
        let first = try DateParsing.startOfDay(year: 2026, month: 11, day: 14, timeZone: copenhagen)
        let end = DateParsing.startOfDay(1, after: first, calendar: DateParsing.gregorian(copenhagen))
        let marathon = ListedEvent(title: "Marathon", calendar: "Home", calendarFullName: "iCloud/Home",
                                   start: utc("2026-11-13T17:00:00Z"), end: utc("2026-11-13T22:00:00Z"),  // 04:00–09:00 Sydney
                                   timeZone: TimeZone(identifier: "Pacific/Auckland"))
        let gig = ListedEvent(title: "Gig", calendar: "Home", calendarFullName: "iCloud/Home",
                              start: utc("2026-11-14T08:00:00Z"), end: utc("2026-11-14T10:00:00Z"),  // Sat 19:00 Sydney
                              timeZone: sydney)
        // As EventKit gives a Saturday all-day event on a Mac in Sydney.
        let holiday = ListedEvent(title: "Holiday", calendar: "Hols", calendarFullName: "Hols",
                                  start: utc("2026-11-13T13:00:00Z"), end: utc("2026-11-14T12:59:59Z"), isAllDay: true)
        let sunday = ListedEvent(title: "Sunday thing", calendar: "Hols", calendarFullName: "Hols",
                                 start: utc("2026-11-14T13:00:00Z"), end: utc("2026-11-15T12:59:59Z"), isAllDay: true)

        let events = EventList.prepare([marathon, gig, holiday, sunday], local: sydney, zone: copenhagen, from: first, to: end)
        #expect(events.map(\.title) == ["Gig", "Holiday"])  // the marathon is on Friday in Copenhagen
        #expect(events[1].start == first)
        let text = EventList.render(events, from: first, days: 1, timeZone: copenhagen, now: now, verbose: false)
        #expect(text == """
            Sat 14 Nov 2026
              all day      Holiday  Hols
              09:00–11:00  Gig      Home  (19:00 Australia/Sydney)
            """)
        #expect(EventList.zoneNote(copenhagen, local: sydney, at: first) == "Times are in Europe/Copenhagen (UTC+1).")
        #expect(EventList.zoneNote(sydney, local: sydney, at: first) == nil)
        // In the Mac's own zone nothing moves.
        #expect(EventList.prepare([holiday], local: sydney, zone: sydney, from: holiday.start, to: holiday.end) == [holiday])
    }
}

@Suite struct CompletionTests {
    let source = Completion.Source(
        templates: { path in path == "other.json" ? ["other"] : ["concert", "birthday"] },
        calendars: { [Completion.Candidate("Home", "iCloud/Home"), Completion.Candidate("Family", "several calendars")] },
        timeZones: { ["Europe/Copenhagen", "Australia/Sydney"] })

    func values(_ words: [String]) -> [String] {
        guard case .values(let candidates) = Completion.reply(for: words, source: source) else { return ["(not values)"] }
        return candidates.map(\.value)
    }

    @Test func commandsAndOptions() {
        #expect(values([""]).starts(with: ["add", "list", "search", "edit", "delete"]))
        #expect(values(["add", "--"]).contains("--template"))
        #expect(values(["edit", "-"]).contains("--match-calendar"))
        #expect(!values(["delete", "--"]).contains("--title"))
        #expect(values(["help", ""]).contains("search"))
        #expect(values(["completion", ""]) == ["zsh", "bash", "install"])
        #expect(values(["completion", "install", "--"]) == ["--shell", "--dir", "--dry-run", "--help"])
    }

    @Test func values() {
        #expect(values(["add", "--template", ""]) == ["birthday", "concert"])
        #expect(values(["add", "--templates", "other.json", "--template", ""]) == ["other"])
        #expect(values(["add", "--calendar", ""]) == ["Home", "Family"])
        #expect(values(["list", "--tz", "Eu"]) == ["Europe/Copenhagen", "Australia/Sydney"])  // the shell filters
        #expect(values(["list", "--timezone=Eu"]) == ["--timezone=Europe/Copenhagen", "--timezone=Australia/Sydney"])
        #expect(values(["list", ""]).first == "today")
        #expect(values(["search", "--from", ""]).contains("friday"))
        #expect(values(["add", "--alarm", ""]).contains("1w"))
        #expect(values(["add", "--title", ""]).isEmpty)      // free text: nothing to offer
        #expect(values(["add", "--save", ""]).isEmpty)       // after a flag, nothing positional
        #expect(Completion.reply(for: ["add", "--templates", ""], source: source) == .files)
        #expect(Completion.reply(for: ["completion", "install", "--dir", ""], source: source) == .directories)
    }

    @Test func onlyCalendarNamesNeedCalendar() throws {
        #expect(Completion.needsCalendars(["add", "--calendar", ""]))
        #expect(Completion.needsCalendars(["edit", "--match-calendar=Ho"]))
        #expect(!Completion.needsCalendars(["add", "--title", ""]))
        #expect(!Completion.needsCalendars(["list", ""]))
        #expect(try Invocation.parse(["__complete", "add", "--calendar", ""]) == .complete(["add", "--calendar", ""]))
        #expect(try Invocation.parse(["__complete"]) == .complete([""]))
    }

    @Test func output() {
        #expect(Completion.render(.values([Completion.Candidate("--save", "add it"), Completion.Candidate("x")])) == "--save\tadd it\nx")
        #expect(Completion.render(.files) == ":files")
        #expect(Completion.script(for: "zsh")!.hasPrefix("#compdef calutil\n"))
        #expect(Completion.script(for: "bash")!.contains("complete -F _calutil calutil"))
        #expect(Completion.fileName(for: "zsh") == "_calutil" && Completion.fileName(for: "bash") == "calutil")
    }

    @Test func parsing() throws {
        #expect(try Invocation.parse(["completion", "zsh"]) == .completionScript(shell: "zsh"))
        #expect(try Invocation.parse(["completion", "install"]) == .completionInstall(shell: "auto", dir: nil, dryRun: false))
        #expect(try Invocation.parse(["completion", "install", "--shell", "bash", "--dir", "/tmp/x", "--dry-run"])
                == .completionInstall(shell: "bash", dir: "/tmp/x", dryRun: true))
        #expect(try Invocation.parse(["completion"]) == .help("completion"))
        #expect(throws: CalUtilError.self) { try Invocation.parse(["completion", "fish"]) }
        #expect(throws: CalUtilError.self) { try Invocation.parse(["completion", "install", "--shell", "fish"]) }
        #expect(throws: CalUtilError.self) { try Invocation.parse(["completion", "zsh", "--dry-run"]) }
    }

    @Test func installDirectoryScore() {
        let home = "/Users/me"
        #expect(CompletionInstall.score("/opt/homebrew/share/zsh/site-functions", home: home) == 2)
        #expect(CompletionInstall.score("/Users/me/.oh-my-zsh/completions", home: home) == 11)
        #expect(CompletionInstall.score("/Users/me/.local/share/zsh/site-functions", home: home) == 12)
        #expect(CompletionInstall.score("/Users/me/.oh-my-zsh/cache/completions", home: home) == 0)
        #expect(CompletionInstall.score("/Users/me/.oh-my-zsh/functions", home: home) == 0)
    }

    /// Every option Tab offers must be one the command accepts.
    @Test func everyOfferedOptionIsAccepted() {
        for (command, options) in Completion.options {
            for option in options {
                let args = command.split(separator: " ").map(String.init) + [option.name]
                    + (option.kind == .flag ? [] : ["x"])
                do {
                    _ = try Invocation.parse(args)
                } catch let error as CalUtilError {
                    #expect(!error.message.contains("unknown option"), "\(command) \(option.name): \(error.message)")
                } catch {}
            }
        }
    }
}

@Suite struct KeepTimeTests {
    let auckland = TimeZone(identifier: "Pacific/Auckland")!
    let sydney = TimeZone(identifier: "Australia/Sydney")!
    /// Stored in GMT, as booking sites often do: Sun 15 Nov 2026 00:00–03:30 GMT.
    var tour: EventSpec {
        EventSpec(title: "Harbour Cruise", timeZone: TimeZone(secondsFromGMT: 0)!, isAllDay: false,
                  start: utc("2026-11-15T00:00:00Z"), end: utc("2026-11-15T03:30:00Z"),
                  alarms: [.beforeStart(seconds: 86_400)])
    }

    func edit(_ args: [String], _ event: EventSpec? = nil) throws -> EventSpec {
        let options = try EditOptions.parse(["--id", "x"] + args)
        return try Editor.apply(options.changes, to: event ?? tour, now: now, localTimeZone: sydney,
                                keepTime: options.keepTime)
    }

    @Test func keepsTheMoment() throws {
        let e = try edit(["--timezone", "Pacific/Auckland", "--keep-time"])
        #expect(e.timeZone.identifier == "Pacific/Auckland")
        #expect(e.start == tour.start && e.end == tour.end)
        #expect(e.alarms == tour.alarms)
        #expect(Editor.differences(from: tour, to: e, localTimeZone: sydney) == """
            Starts     - Sun 15 Nov 2026 00:00
                       + Sun 15 Nov 2026 13:00
            Ends       - Sun 15 Nov 2026 03:30  (3 hours 30 minutes)
                       + Sun 15 Nov 2026 16:30  (3 hours 30 minutes)
            Time zone  - GMT (UTC)
                       + Pacific/Auckland (UTC+13)
            """)
        // Without it, the clock time stays and the moment moves.
        let clock = try edit(["--timezone", "Pacific/Auckland"])
        #expect(clock.start == utc("2026-11-14T11:00:00Z"))  // 00:00 in Auckland
    }

    @Test func endAndDurationStillWork() throws {
        let e = try edit(["--tz", "Pacific/Auckland", "--keep-time", "--end", "17:00"])
        #expect(e.start == tour.start)
        #expect(e.end == utc("2026-11-15T04:00:00Z"))  // 17:00 in Auckland
        #expect(try edit(["--tz", "Pacific/Auckland", "--keep-time", "--duration", "4h"]).end == utc("2026-11-15T04:00:00Z"))
    }

    @Test func misuse() throws {
        #expect(throws: CalUtilError.self) { try EditOptions.parse(["--id", "x", "--keep-time", "--title", "y"]) }
        #expect(throws: CalUtilError.self) {
            try EditOptions.parse(["--id", "x", "--timezone", "UTC", "--keep-time", "--start", "2026-11-15T13:00"])
        }
        var allDay = tour
        allDay.isAllDay = true
        #expect(throws: CalUtilError.self) { try edit(["--timezone", "Pacific/Auckland", "--keep-time"], allDay) }
        #expect(throws: CalUtilError.self) { try edit(["--timezone", "Pacific/Auckland", "--keep-time", "--all-day"]) }
    }
}

@Suite struct EditAllTests {
    func parse(_ args: [String]) throws -> EditOptions { try EditOptions.parse(args) }

    @Test func parsing() throws {
        let o = try parse(["--match-notes", "Trip 2026", "--all", "--tz", "Pacific/Auckland", "--keep-time"])
        #expect(o.all && o.keepTime && o.changes.timezone == "Pacific/Auckland")
        #expect(try parse(["--match", "concert", "--all", "--add-alarm", "1d", "--location", "Hall",
                           "--notes", "n", "--url", "https://x.example", "--calendar", "Home", "--no-map"]).all)
    }

    @Test func refusesWhatShouldNotBeTheSameEverywhere() {
        for args in [["--title", "x"], ["--start", "2027-01-01T10:00"], ["--end", "11:00"], ["--duration", "1h"],
                     ["--all-day"], ["--no-all-day"]] {
            #expect(throws: CalUtilError.self, "\(args)") { try parse(["--match", "x", "--all"] + args) }
        }
        #expect(throws: CalUtilError.self) { try parse(["--id", "x", "--all", "--notes", "n"]) }
        #expect(throws: CalUtilError.self) { try parse(["--match", "x", "--all", "--future", "--notes", "n"]) }
        #expect(throws: CalUtilError.self) { try parse(["--match", "x", "--all"]) }  // nothing to change
    }

    @Test func allDayEventsKeepTheirTimeZone() throws {
        var o = AddOptions()
        o.timezone = "Pacific/Auckland"
        #expect(Editor.bulkChanges(o, keepTime: true, forAllDay: true) == nil)  // nothing else to do
        let timed = Editor.bulkChanges(o, keepTime: true, forAllDay: false)
        #expect(timed?.changes.timezone == "Pacific/Auckland" && timed?.keepTime == true && timed?.note == nil)
        o.notes = "Trip"
        let allDay = Editor.bulkChanges(o, keepTime: true, forAllDay: true)
        #expect(allDay?.changes.timezone == nil && allDay?.changes.notes == "Trip" && allDay?.keepTime == false)
        #expect(allDay?.note != nil)
    }
}
