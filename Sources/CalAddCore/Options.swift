import Foundation

public enum Action: Equatable, Sendable {
    /// Print a readable summary; change nothing. The default.
    case dryRun
    /// Print the iCalendar text; change nothing.
    case printICS
    /// Write an .ics file and open it in Calendar.
    case openICS
    /// Add the event through EventKit.
    case save
}

public enum Command: Equatable, Sendable {
    case run, help, version, listTemplates, listCalendars
}

/// The command line as given, before templates and defaults are applied.
public struct Options: Equatable, Sendable {
    public var command: Command = .run
    public var action: Action = .dryRun

    public var template: String?
    public var templatesPath: String?
    public var title: String?
    public var location: String?
    public var notes: String?
    public var url: String?
    public var calendar: String?
    public var timezone: String?
    public var start: String?
    public var end: String?
    public var duration: String?
    public var allDay: Bool?
    /// `--alarm` values; when set they replace the template's alarms.
    public var alarms: [String]?
    /// `--add-alarm` values; added to whatever alarms there are.
    public var addAlarms: [String] = []
    public var noAlarms = false
    public var verbose = false

    public init() {}

    public static func parse(_ arguments: [String]) throws -> Options {
        var options = Options()
        var actionFlag: String?
        var seen: Set<String> = []
        var index = 0

        while index < arguments.count {
            let argument = arguments[index]
            var name = argument
            var inline: String?
            if argument.hasPrefix("--"), let eq = argument.firstIndex(of: "=") {
                name = String(argument[..<eq])
                inline = String(argument[argument.index(after: eq)...])
            }

            func value() throws -> String {
                if let inline { return inline }
                index += 1
                guard index < arguments.count, !arguments[index].hasPrefix("--") else {
                    throw CalAddError("\(name) needs a value", usage: true)
                }
                return arguments[index]
            }
            func single(_ assign: (String) -> Void) throws {
                guard seen.insert(name).inserted else {
                    throw CalAddError("\(name) was given more than once", usage: true)
                }
                assign(try value())
            }
            func flag() throws {
                guard inline == nil else { throw CalAddError("\(name) does not take a value", usage: true) }
            }
            func setAction(_ action: Action) throws {
                try flag()
                if let previous = actionFlag, previous != name {
                    throw CalAddError("\(previous) and \(name) can't be combined; pick one", usage: true)
                }
                actionFlag = name
                options.action = action
            }

            switch name {
            case "-h", "--help": try flag(); options.command = .help
            case "--version": try flag(); options.command = .version
            case "--list-templates": try flag(); options.command = .listTemplates
            case "--list-calendars": try flag(); options.command = .listCalendars
            case "-v", "--verbose": try flag(); options.verbose = true

            case "--save": try setAction(.save)
            case "--open": try setAction(.openICS)
            case "--ics": try setAction(.printICS)
            case "--dry-run": try setAction(.dryRun)

            case "--template": try single { options.template = $0 }
            case "--templates": try single { options.templatesPath = ($0 as NSString).expandingTildeInPath }
            case "--title": try single { options.title = $0 }
            case "--location": try single { options.location = $0 }
            case "--notes": try single { options.notes = $0 }
            case "--url": try single { options.url = $0 }
            case "--calendar": try single { options.calendar = $0 }
            case "--timezone", "--tz": try single { options.timezone = $0 }
            case "--start": try single { options.start = $0 }
            case "--end": try single { options.end = $0 }
            case "--duration": try single { options.duration = $0 }

            case "--all-day": try flag(); options.allDay = true
            case "--no-all-day": try flag(); options.allDay = false

            case "--alarm": options.alarms = (options.alarms ?? []) + [try value()]
            case "--add-alarm": options.addAlarms.append(try value())
            case "--no-alarms": try flag(); options.noAlarms = true

            default:
                if argument.hasPrefix("-") {
                    throw CalAddError("unknown option \(argument) (see cal-add --help)", usage: true)
                }
                throw CalAddError(
                    "unexpected argument '\(argument)': values are given with named options, e.g. --title \"\(argument)\"",
                    usage: true)
            }
            index += 1
        }

        if options.verbose && options.command != .listCalendars {
            throw CalAddError("--verbose only applies to --list-calendars", usage: true)
        }
        if options.noAlarms && options.alarms != nil {
            throw CalAddError("--no-alarms and --alarm can't be combined (--alarm already replaces the template's alarms)", usage: true)
        }
        return options
    }
}

public enum CLI {
    public static let version = "0.1.0"

    public static let help = """
    cal-add: add an event to Apple Calendar from the command line

    USAGE
      cal-add --title TEXT --start DATETIME [options]
      cal-add --template NAME --title TEXT --start DATETIME [options]

      Without an action cal-add does a dry run: it shows the event and changes nothing.

    ACTIONS (at most one)
      --dry-run            Print a summary of the event (the default)
      --ics                Print the event as iCalendar (.ics) text, e.g. to save with > file.ics
      --open               Write an .ics file and open it in Calendar, which asks you to confirm
                           and pick a calendar
      --save               Add the event straight to Calendar (EventKit)

    EVENT
      --template NAME      Start from a template (see TEMPLATES)
      --title TEXT         Event title
      --start DATETIME     2026-11-06T18:00 or "2026-11-06 18:00". A date alone (2026-11-06) is
                           allowed for all-day events, or when the template sets a "time".
                           A trailing Z or offset (+11:00) pins the exact moment.
      --end DATETIME|TIME  When it ends. A bare time (21:30) means the start day, or the next
                           day if that would be before the start. All-day: the last day.
      --duration DUR       Length instead of --end: 90m, 2h, 1h30m, 3d (default 1h; all-day 1d)
      --all-day            Make it an all-day event (--no-all-day overrides a template)
      --timezone ZONE      Time zone the times are in, e.g. Australia/Sydney (default: this Mac's)
      --location TEXT
      --notes TEXT
      --url URL
      --calendar NAME      Calendar for --save (default: your default calendar). Use
                           "Account/Name" if two calendars share a name, or the calendar's id
                           (shown by --list-calendars) if even that is ambiguous.

    ALARMS
      --alarm WHEN         Set an alarm, replacing the template's alarms. Repeatable.
      --add-alarm WHEN     Add an alarm on top of the template's alarms. Repeatable.
      --no-alarms          Drop the template's alarms.

      WHEN is one of:
        15m  2h  1d  1w  1h30m    that long before the start (0 = at the start)
        09:00                     at that time on the day of the event
        2026-11-05T09:00          at that date and time (in the event's time zone)

    OTHER
      --templates PATH     Template file (default: $CAL_ADD_TEMPLATES, else
                           ~/.config/cal-add/templates.json)
      --list-templates     Show the templates
      --list-calendars     Show your calendars (needs Calendar access)
      -v, --verbose        With --list-calendars: also show each calendar's id, colour, and
                           how many events it has, with the latest and next one
      -h, --help           Show this help
      --version            Show the version

      Values follow the option (--title "Beethoven's 9th") or an equals sign (--title=...).
      An empty value ("") clears what the template set.

    TEMPLATES
      A JSON file mapping template names to defaults. Comments and trailing commas are fine.

        {
          "concert": {
            "time": "19:30",          // used when --start has no time
            "duration": "3h",
            "alarms": ["1d", "2h"],
            "calendar": "Personal",
            "notes": "Bring the tickets",
          },
        }

      Settings: title, location, notes, url, calendar, timezone, time, duration, allDay, alarms.
      Whatever is given on the command line wins over the template.

    EXAMPLE
      cal-add --template concert --title "Beethoven's 9th" --location "Sydney Opera House" \\
              --start 2026-11-06T18:00 --timezone Australia/Sydney --add-alarm 15m --save
    """
}
