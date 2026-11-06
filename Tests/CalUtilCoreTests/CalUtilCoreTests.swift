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
