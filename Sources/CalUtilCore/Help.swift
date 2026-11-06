public enum Help {
    public static let version = "0.2.0"

    public static func text(for topic: String?) -> String? {
        switch topic {
        case nil: general
        case "add": add
        case "calendars": calendars
        case "templates": templates
        case "help": general
        case "version": "calutil version\n\nShows the version of calutil."
        default: nil
        }
    }

    static let general = """
    calutil: work with Apple Calendar from the command line

    USAGE
      calutil <command> [options]

    COMMANDS
      add          Add an event (a dry run unless you pass --save or --open)
      calendars    List your calendars
      templates    List the event templates for 'add'
      help [CMD]   Show help, for one command if given
      version      Show the version

      Run 'calutil help <command>' for the options of a command.

    EXAMPLES
      calutil add --template concert --title "Beethoven's 9th" --start 2026-11-28 --save
      calutil calendars --verbose
    """

    static let add = """
    calutil add: add an event to Apple Calendar

    USAGE
      calutil add --title TEXT --start DATETIME [options]
      calutil add --template NAME --title TEXT --start DATETIME [options]

      Without an action this is a dry run: it shows the event and changes nothing.

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
                           (see 'calutil calendars') if even that is ambiguous.

    ALARMS
      --alarm WHEN         Set an alarm, replacing the template's alarms. Repeatable.
      --add-alarm WHEN     Add an alarm on top of the template's alarms. Repeatable.
      --no-alarms          Drop the template's alarms.

      WHEN is one of:
        15m  2h  1d  1w  1h30m    that long before the start (0 = at the start)
        09:00                     at that time on the day of the event
        2026-11-05T09:00          at that date and time (in the event's time zone)

    OTHER
      --templates PATH     Template file (default: $CALUTIL_TEMPLATES, else
                           ~/.config/calutil/templates.json)

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
      calutil add --template concert --title "Beethoven's 9th" --location "Sydney Opera House" \\
                  --start 2026-11-06T18:00 --timezone Australia/Sydney --add-alarm 15m --save
    """

    static let calendars = """
    calutil calendars: list your calendars

    USAGE
      calutil calendars [--verbose]

      Shows each calendar as Account/Name, the form --calendar accepts. Calendars that share
      both account and name also show their id, which --calendar accepts too.

    OPTIONS
      -v, --verbose        Also show each calendar's id, type and colour, and how many events
                           it has in the past and coming year, with the latest and next one
    """

    static let templates = """
    calutil templates: list the templates for 'calutil add'

    USAGE
      calutil templates [--templates PATH]

      Templates are read from $CALUTIL_TEMPLATES, else ~/.config/calutil/templates.json.
      See 'calutil help add' for the file format.
    """
}
