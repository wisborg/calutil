import Foundation
import Testing
@testable import CalAddCore

let sydney = TimeZone(identifier: "Australia/Sydney")!
let copenhagen = TimeZone(identifier: "Europe/Copenhagen")!
/// A fixed "now" before the test events.
let now = ISO8601DateFormatter().date(from: "2026-11-01T00:00:00Z")!

func options(_ args: String...) throws -> Options { try Options.parse(args) }

func resolve(_ args: [String], template: Template? = nil, local: TimeZone = copenhagen) throws -> EventSpec {
    try Resolver.resolve(options: Options.parse(args), template: template, now: now, localTimeZone: local)
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
        #expect(throws: CalAddError.self) { try Durations.parse(text) }
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
        #expect(throws: CalAddError.self) { try DateParsing.parseDateTime(text) }
    }

    @Test func impossibleDates() {
        #expect(throws: CalAddError.self) {
            try DateParsing.makeDate(year: 2026, month: 2, day: 30, time: TimeOfDay(hour: 12, minute: 0), timeZone: copenhagen)
        }
        // 02:30 doesn't exist in Copenhagen on 2026-03-29 (clocks jump 02:00 → 03:00).
        #expect(throws: CalAddError.self) {
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
        #expect(throws: CalAddError.self) { try options("Beethoven") }           // positional
        #expect(throws: CalAddError.self) { try options("--titel", "x") }        // typo
        #expect(throws: CalAddError.self) { try options("--title") }             // missing value
        #expect(throws: CalAddError.self) { try options("--title", "--start") }  // value looks like option
        #expect(throws: CalAddError.self) { try options("--title", "a", "--title", "b") }
        #expect(throws: CalAddError.self) { try options("--save", "--open") }
        #expect(throws: CalAddError.self) { try options("--save=yes") }
        #expect(throws: CalAddError.self) { try options("--no-alarms", "--alarm", "1h") }
        #expect(throws: CalAddError.self) { try options("--verbose", "--title", "x") }
        #expect((try? options("--list-calendars", "-v"))?.verbose == true)
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
        #expect(throws: CalAddError.self) { try resolve(["--title", "x", "--start", "2026-11-20"]) }
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
            (error as? CalAddError)?.message.contains("template 'broken'") == true
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
        #expect(throws: CalAddError.self) { try resolve(["--title", "x", "--start", "2026-12-24T10:00", "--all-day"]) }
        #expect(throws: CalAddError.self) { try resolve(["--title", "x", "--start", "2026-12-24", "--all-day", "--duration", "5h"]) }
    }

    @Test func otherErrors() {
        #expect(throws: CalAddError.self) { try resolve(["--start", "2026-11-20T19:00"]) }
        #expect(throws: CalAddError.self) { try resolve(["--title", "x"]) }
        #expect(throws: CalAddError.self) { try resolve(["--title", "x", "--start", "2026-11-20T19:00", "--timezone", "Mars/Olympus"]) }
        #expect(throws: CalAddError.self) { try resolve(["--title", "x", "--start", "2026-11-20T19:00", "--end", "2026-11-20T18:00"]) }
        #expect(throws: CalAddError.self) { try resolve(["--title", "x", "--start", "2026-11-20T19:00", "--url", "example.com"]) }
        #expect(throws: CalAddError.self) { try resolve(["--title", "x", "--start", "2026-11-20T19:00", "--alarm", "soon"]) }
    }

    @Test func warnsAboutThePast() throws {
        let e = try resolve(["--title", "x", "--start", "2026-10-01T19:00"])
        #expect(e.warnings.contains("the event starts in the past"))
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
        #expect(throws: CalAddError.self) { try TemplateStore.parse(Data(text.utf8), source: "test") }
    }

    @Test func defaultPath() {
        #expect(TemplateStore.defaultPath(environment: ["CAL_ADD_TEMPLATES": "/x/t.json"]) == "/x/t.json")
        #expect(TemplateStore.defaultPath(environment: ["XDG_CONFIG_HOME": "/cfg"]) == "/cfg/cal-add/templates.json")
        #expect(TemplateStore.defaultPath(environment: [:]).hasSuffix("/.config/cal-add/templates.json"))
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
