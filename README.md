# cal-add

Add events to Apple Calendar from the command line, using templates for the events you add
often.

```
cal-add --template concert --title "Beethoven's 9th" --location "Sydney Opera House" \
        --start 2026-11-06T18:00 --add-alarm 15m
```

By default this is a **dry run**: cal-add prints the event and changes nothing. To actually
add it, pick an action:

| Flag        | What happens                                                                            |
|-------------|-----------------------------------------------------------------------------------------|
| (none)      | Dry run: print a summary                                                                |
| `--ics`     | Dry run: print the iCalendar text (`> event.ics` to keep it)                             |
| `--open`    | Write an `.ics` file and open it in Calendar, which asks you to confirm and pick a calendar |
| `--save`    | Add it straight to Calendar through EventKit                                            |

Run `cal-add --help` for every option.

## Install

Needs macOS 14 or later and Swift 6 (Xcode or the command-line tools).

```
make install              # builds and installs to ~/.local/bin/cal-add (PREFIX=... to change)
make install-templates    # copies templates.example.json to ~/.config/cal-add/templates.json
```

## Calendar access

The first `--save` or `--list-calendars` asks macOS for access to your calendars. Depending on
how macOS attributes the request, the dialog names either your terminal app (Terminal, iTerm)
or cal-add. Choose **Allow Full Access**: cal-add needs to read your calendar list so it can
find calendars by name.

If you said no, or the dialog never appeared, change it under **System Settings → Privacy &
Security → Calendars**. If you need to start over: `tccutil reset Calendar` (this resets every
app's calendar permission, so you'll be asked again).

`--dry-run`, `--ics` and `--open` need no permission.

## Options in short

```
--title TEXT  --start DATETIME  [--end DATETIME|TIME | --duration DUR]  [--all-day]
--location TEXT  --notes TEXT  --url URL  --calendar NAME  --timezone ZONE
--alarm WHEN (replaces the template's)  --add-alarm WHEN (adds)  --no-alarms
--template NAME  --templates PATH  --list-templates  --list-calendars
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
  `--calendar "iCloud/Personal"`. `cal-add --list-calendars` shows them all.
* An empty value (`--notes ""`) clears what the template set.

## Templates

A JSON file at `~/.config/cal-add/templates.json`, or wherever `$CAL_ADD_TEMPLATES` or
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

`Sources/CalAddCore` holds everything that can be tested without touching your calendar:
argument parsing, templates, dates, the summary and the iCalendar writer.
`Sources/cal-add` is the executable and the EventKit code. `Sources/cal-add/Info.plist` is
linked into the binary, because macOS won't grant calendar access to a program that doesn't
say why it wants it.
