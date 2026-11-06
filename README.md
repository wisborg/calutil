# calutil

Work with Apple Calendar from the command line: add events (using templates for the ones you
add often) and see your calendars.

```
calutil add --template concert --title "Beethoven's 9th" --location "Sydney Opera House" \
            --start 2026-11-06T18:00 --add-alarm 15m
calutil calendars --verbose
calutil templates
```

| Command     | What it does                                                    |
|-------------|-----------------------------------------------------------------|
| `add`       | Add an event (a dry run unless you pass `--save` or `--open`)   |
| `calendars` | List your calendars; `--verbose` adds ids, colours and contents |
| `templates` | List the templates for `add`                                    |
| `help`      | `calutil help <command>` shows every option of a command        |

## Adding events

By default `calutil add` is a **dry run**: it prints the event and changes nothing. To
actually add it, pick an action:

| Flag        | What happens                                                                            |
|-------------|-----------------------------------------------------------------------------------------|
| (none)      | Dry run: print a summary                                                                |
| `--ics`     | Dry run: print the iCalendar text (`> event.ics` to keep it)                             |
| `--open`    | Write an `.ics` file and open it in Calendar, which asks you to confirm and pick a calendar |
| `--save`    | Add it straight to Calendar through EventKit                                            |

Run `calutil help add` for every option.

## Install

Needs macOS 14 or later and Swift 6 (Xcode or the command-line tools).

```
make install              # builds and installs to ~/.local/bin/calutil (PREFIX=... to change)
make install-templates    # copies templates.example.json to ~/.config/calutil/templates.json
```

## Calendar access

The first `calutil add --save` or `calutil calendars` asks macOS for access to your calendars. Choose
**Allow Full Access**: calutil needs to read your calendar list so it can find calendars by
name.

Normally macOS charges a command-line tool's permissions to the terminal app it runs in, which
would give every program in that terminal calendar access, and fails outright in terminals
such as iTerm that don't declare full calendar access. To avoid that, calutil relaunches
itself as its own "responsible" process when it needs your calendars, so the permission
belongs to **calutil** alone and works the same in any terminal.

If you said no, change it under **System Settings → Privacy & Security → Calendars → calutil**.

The binary is ad-hoc signed, so macOS may treat a rebuilt or reinstalled calutil as a new
program and ask again.

A dry run, `--ics`, `--open` and `calutil templates` need no permission.

## `add` options in short

```
--title TEXT  --start DATETIME  [--end DATETIME|TIME | --duration DUR]  [--all-day]
--location TEXT  --notes TEXT  --url URL  --calendar NAME  --timezone ZONE
--alarm WHEN (replaces the template's)  --add-alarm WHEN (adds)  --no-alarms
--template NAME  --templates PATH
```

* **Dates:** `2026-11-06T18:00` or `"2026-11-06 18:00"`. A date alone is used for all-day
  events, or when the template sets a `time`. `--end 21:30` means the same day (or the next
  day if it would otherwise be before the start).
* **Time zones:** times are in this Mac's zone unless you pass `--timezone Australia/Sydney`
  (or end the time with `Z` or `+11:00`). The event keeps that zone in Calendar, and the dry run
  shows your local time too.
* **Alarms:** `15m`, `2h`, `1d`, `1w`, `1h30m` before the start (`0` = at the start); `09:00`
  on the day of the event; or `2026-11-05T09:00` at an exact moment. Repeat the option for
  more than one.
* **Calendars:** `--calendar Personal`; if two accounts both have one with that name, use
  `--calendar "iCloud/Personal"`; if even that is ambiguous (e.g. several shared calendars
  called "Family"), use the id that `calutil calendars` shows next to each of them.
* An empty value (`--notes ""`) clears what the template set.

## Templates

A JSON file at `~/.config/calutil/templates.json`, or wherever `$CALUTIL_TEMPLATES` or
`--templates` points. Comments and trailing commas are allowed. See
[`templates.example.json`](templates.example.json).

```jsonc
{
  "concert": {
    "time": "19:30",          // used when --start is a date only
    "duration": "3h",
    "alarms": ["1d", "2h"],
    "calendar": "Personal",
    "notes": "Bring the tickets.",
  },
}
```

Settings: `title`, `location`, `notes`, `url`, `calendar`, `timezone`, `time`, `duration`,
`allDay`, `alarms`. A misspelt setting is an error rather than being silently ignored.

## Development

```
swift build
swift test
```

`Sources/CalUtilCore` holds everything that can be tested without touching your calendar:
argument parsing, templates, dates, the summary and the iCalendar writer.
`Sources/calutil` is the executable and the EventKit code. `Sources/calutil/Info.plist` is
linked into the binary, because macOS won't grant calendar access to a program that doesn't
say why it wants it.
