public enum Help {
    public static let version = "0.2.0"

    public static func text(for topic: String?) -> String? {
        switch topic {
        case nil: general
        case "add": add
        case "list": list
        case "search": search
        case "edit": edit
        case "completion": completion
        case "delete": delete
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
      list         Show the events on a day, or over several days
      search       Find events by title, location or notes
      edit         Change an event (a dry run unless you pass --save)
      delete       Delete an event (a dry run unless you pass --yes)
      calendars    List your calendars
      templates    List the event templates for 'add'
      completion   Tab completion for zsh and bash ('calutil completion install')
      help [CMD]   Show help, for one command if given
      version      Show the version

      Run 'calutil help <command>' for the options of a command.

    EXAMPLES
      calutil add --template concert --title "Beethoven's 9th" --start 2026-11-28 --save
      calutil list tomorrow
      calutil list 2026-12-20 --days 14 --calendar Home
      calutil search dvorak
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
                           Day words work too: today, tomorrow, friday, "tomorrow 18:00".
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

      For an event still ahead, alarms that would already be in the past are left out, with
      a warning. An event that has already started keeps its alarms.

    MAP
      The location is looked up in Apple Maps, so Calendar shows a map for it (and can offer
      "Alert when I need to leave"). The dry run lists what was found; the first match named
      like the location's first line is used, else the first match.

      --map TEXT           Search for TEXT instead of the location. Without a --location, the
                           place found gives it ("City Recital Hall" + its address).
      --map LAT,LON        Use these coordinates, e.g. --map -33.8569,151.2153 (no search)
      --map-match N        Use the Nth match the dry run lists
      --no-map             Keep the location as text only

      A template can set "map" too (coordinates or search text). It belongs to the template's
      location, so it is used only when --location is left out or is the same text.

    OTHER
      --templates PATH     Template file (default: $CALUTIL_TEMPLATES, else
                           $XDG_CONFIG_HOME/calutil/templates.json, else
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

      Settings: title, location, map, notes, url, calendar, timezone, time, duration, allDay,
      alarms.
      Whatever is given on the command line wins over the template.

    EXAMPLE
      calutil add --template concert --title "Beethoven's 9th" --location "Sydney Opera House" \\
                  --start 2026-11-06T18:00 --timezone Australia/Sydney --add-alarm 15m --save
    """

    static let search = """
    calutil search: find events by title, location or notes

    USAGE
      calutil search [TEXT...] [--title T] [--location L] [--notes N]
                     [--from DAY] [--to DAY] [--calendar NAME]... [--timezone ZONE] [--verbose]

      Every word of TEXT must appear in the event's title, location or notes (any mix of
      them). --title, --location and --notes look in that field only. When several are
      given, all must match. Case and accents don't matter: dvorak finds Dvořák.

      Matches are shown as 'calutil list' shows events, grouped by day. A repeating event
      shows each time it occurs.

    OPTIONS
      --from DAY           First day to search (default: today). To search back in time,
                           give an earlier day, e.g. --from 2025-01-01.
      --to DAY             Last day to search (default: a year after --from)
      --calendar NAME      Only this calendar; repeat for more (default: all)
      --timezone ZONE      Show the times in this zone instead of this Mac's (as for list)
      -v, --verbose        Also show the full title, time zone, location, notes, URL,
                           calendar and event id

      DAY is as for 'calutil list': today, tomorrow, yesterday, a weekday or a date.

    EXAMPLES
      calutil search dvorak
      calutil search --location "opera house" --from 2026-01-01 --to 2027-12-31
      calutil search concert --calendar Home --verbose
    """

    static let completion = """
    calutil completion: Tab completion for zsh and bash

    USAGE
      calutil completion install [--shell zsh|bash|all|auto] [--dir DIR] [--dry-run]
      calutil completion zsh|bash

      'install' writes the completion script into a directory your shell reads, creating
      it if needed, and then says whether that directory is one your shell actually reads.
      If it is not, it prints the line to add and where. It never edits your startup files.

      'zsh' and 'bash' print the script, if you would rather place it yourself.

      Tab then offers commands and options (with what they do), your templates, your
      calendars, time zones, day words, durations and alarms, read as they are each time.

    OPTIONS (install)
      --shell SHELL        zsh, bash, all, or auto: the shell $SHELL names (the default;
                           both if it is neither)
      --dir DIR            Install into this directory instead (needs one --shell)
      --dry-run            Say where it would go; write nothing
    """

    static let edit = """
    calutil edit: change an event

    USAGE
      calutil edit --id ID [--on DAY] [changes] [--future] [--save]
      calutil edit --match TEXT [--match-title T] [--match-location L] [--match-notes N]
                   [--match-calendar NAME]... [--on DAY | --from DAY --to DAY]
                   [changes] [--future] [--save]

      Without --save this is a dry run: it shows what would change and changes nothing.

    WHICH EVENT
    \(selection)

    CHANGES
      The same options as 'calutil add'; only what you give changes.

      --title TEXT, --location TEXT, --notes TEXT, --url URL
                           New values; "" clears the location, notes or URL
      --calendar NAME      Move it to this calendar
      --start DATETIME     Move it, keeping its length. A day alone (2027-09-12) keeps the time.
      --end DATETIME|TIME, --duration DUR
                           Change when it ends
      --all-day, --no-all-day
                           Make it all-day, or timed (which needs a --start with a time)
      --timezone ZONE      Put it in another zone, keeping its clock time (19:00 stays 19:00)
      --keep-time          With --timezone: keep the moment instead, so the clock time
                           changes (00:00 GMT becomes 13:00 in Pacific/Auckland)
      --alarm WHEN         Replace the alarms (repeatable); --add-alarm WHEN adds one;
                           --no-alarms removes them all
      --map TEXT|LAT,LON, --map-match N, --no-map
                           As for add. A new --location is looked up on the map too; --map on
                           its own adds a map to an event that has none.

    REPEATING EVENTS
      --future             Change this and the later occurrences (default: only this one)

    EXAMPLES
      calutil edit --match prokofiev --title "Prokofiev's Second Piano Concerto"
      calutil edit --match "lena berg" --on 2027-07-05 --start 2027-07-05T19:30 --save
      calutil edit --id 1A2B3C4D-…:5E6F7A8B-… --map "Sydney Opera House" --save
      calutil edit --match "harbour cruise" --timezone Pacific/Auckland --keep-time
    """

    static let delete = """
    calutil delete: delete an event

    USAGE
      calutil delete --id ID [--on DAY] [--future] [--yes]
      calutil delete --match TEXT [--match-title T] [--match-location L] [--match-notes N]
                     [--match-calendar NAME]... [--on DAY | --from DAY --to DAY]
                     [--future] [--yes]

      Without --yes this is a dry run: it shows the event and deletes nothing.

    WHICH EVENT
    \(selection)

    REPEATING EVENTS
      --future             Delete this and the later occurrences (default: only this one)

    EXAMPLES
      calutil delete --match dentist --on 2026-12-01
      calutil delete --match dentist --on 2026-12-01 --yes
    """

    /// How edit and delete pick their event.
    private static let selection = """
      --id ID              The event's id, as 'calutil search --verbose' shows it. For a
                           repeating event, add --on DAY to say which occurrence.
      --match TEXT         Find it as 'calutil search TEXT' would (title, location or notes);
                           it must find exactly one event, or the matches are listed
      --match-title T, --match-location L, --match-notes N
                           Look in that field only
      --match-calendar NAME
                           Only in this calendar (repeatable)
      --on DAY             The day the event (or occurrence) is on
      --from DAY, --to DAY Search these days instead (default: today to a year ahead)
    """

    static let list = """
    calutil list: show the events on a day, or over several days

    USAGE
      calutil list [DAY] [--days N] [--calendar NAME]... [--timezone ZONE] [--verbose]

      DAY is today (the default), tomorrow, yesterday, a weekday (friday: the next one, today
      included) or a date (2026-11-14). Times are in this Mac's time zone; an event set in
      another zone also shows its own time.

    OPTIONS
      --days N             Show N days starting at DAY (default 1); days without events are
                           left out
      --calendar NAME      Only this calendar; repeat for more (default: all). Takes the same
                           names and ids as 'calutil add --calendar'.
      --timezone ZONE      Show the times, and split the days, in this zone instead of this
                           Mac's, e.g. Europe/Copenhagen (--tz for short). DAY is a day there.
                           All-day events stay on their dates.
      -v, --verbose        Also show the full title, time zone, location, notes, URL,
                           calendar and event id

    EXAMPLES
      calutil list
      calutil list friday --calendar Home --calendar Family
      calutil list 2026-12-20 --days 14
      calutil list friday --timezone Europe/Copenhagen
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
      calutil templates [--json] [--templates PATH]

      Templates are read from $CALUTIL_TEMPLATES, else $XDG_CONFIG_HOME/calutil/templates.json,
      else ~/.config/calutil/templates.json.
      See 'calutil help add' for the file format.

    OPTIONS
      --json               Print the templates as strict JSON (without the file's comments),
                           e.g. for jq: calutil templates --json | jq .concert
      --templates PATH     Read this template file instead
    """
}
