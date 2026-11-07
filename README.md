# calutil

Work with Apple Calendar from the command line: add events (using templates for the ones you
add often), see what's on, find, change and delete events, and look at your calendars.

```
calutil add --template concert --title "Beethoven's 9th" --location "Sydney Opera House" \
            --start 2026-11-06T18:00 --add-alarm 15m
calutil list tomorrow
calutil search dvorak
calutil calendars --verbose
```

| Command     | What it does                                                    |
|-------------|-----------------------------------------------------------------|
| `add`       | Add an event (a dry run unless you pass `--save` or `--open`)   |
| `list`      | Show the events on a day, or over several days                  |
| `search`    | Find events by title, location or notes                         |
| `edit`      | Change an event (a dry run unless you pass `--save`)            |
| `delete`    | Delete an event (a dry run unless you pass `--yes`)             |
| `calendars` | List your calendars; `--verbose` adds ids, colours and contents |
| `templates` | List the templates for `add`                                    |
| `completion`| Tab completion for zsh and bash (`calutil completion install`)  |
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
calutil completion install  # Tab completion for your shell (see Shell completion)
```

## Calendar access

The first `calutil add --save`, `list`, `search`, `edit`, `delete` or `calendars` asks macOS for access to your calendars. Choose
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

`calutil add` without `--save`, and `calutil templates`, need no permission.

## `add` options in short

```
--title TEXT  --start DATETIME  [--end DATETIME|TIME | --duration DUR]  [--all-day]
--location TEXT  --notes TEXT  --url URL  --calendar NAME  --timezone ZONE
--alarm WHEN (replaces the template's)  --add-alarm WHEN (adds)  --no-alarms
--template NAME  --templates PATH
```

* **Dates:** `2026-11-06T18:00` or `"2026-11-06 18:00"`, or with a day word: `today`,
  `tomorrow`, `friday` (the next one, today included), `"tomorrow 18:00"`. A day alone is used
  for all-day events, or when the template sets a `time`. `--end 21:30` means the same day (or the next
  day if it would otherwise be before the start).
* **Time zones:** times are in this Mac's zone unless you pass `--timezone Australia/Sydney`
  (or end the time with `Z` or `+11:00`). The event keeps that zone in Calendar, and the dry run
  shows your local time too. `Z` always means UTC; an offset that is this Mac's own at that
  moment keeps the Mac's zone, so the event follows its daylight-saving rules.
* **Alarms:** `15m`, `2h`, `1d`, `1w`, `1h30m` before the start (`0` = at the start); `09:00`
  on the day of the event; or `2026-11-05T09:00` at an exact moment. Repeat the option for
  more than one. Alarms that would already be in the past (say, a template's `1w` for an
  event in two days) are left out, with a warning. An event that has already started keeps
  its alarms.
* **Map:** the location is looked up in Apple Maps so Calendar shows a map (and can offer
  "Alert when I need to leave"). The dry run lists the matches; pick another with
  `--map-match 2`, search for other words with `--map "City Recital Hall"`, give coordinates
  with `--map -33.8569,151.2153`, or skip it with `--no-map`. A location with its address
  (`$'Sydney Opera House\nBennelong Point, Sydney NSW 2000, Australia'`) finds the right
  place most reliably. `calutil list --verbose` shows an event's map point. A template for a
  venue can set `"map": "-33.8569,151.2153"`; it is used only with the template's own
  location (when `--location` is left out or is the same text).
* **Calendars:** `--calendar Personal`; if two accounts both have one with that name, use
  `--calendar "iCloud/Personal"`; if even that is ambiguous (e.g. several shared calendars
  called "Family"), use the id that `calutil calendars` shows next to each of them.
* An empty value (`--notes ""`) clears what the template set.

## Listing events

```
calutil list                                  # today
calutil list friday --calendar Home --calendar Family
calutil list 2026-12-20 --days 14 --verbose
calutil list friday --timezone Europe/Copenhagen   # times as they are in Copenhagen
```

```
Sat 14 Nov 2026
  all day      Remembrance Day      Australian Holidays
  04:00–09:00  Lake Shore Marathon  Home                 (06:00 Pacific/Auckland)  ⏰ 1d
```

Times are in this Mac's time zone, or the one `--timezone` (`--tz`) names: the days are then
split, and day words like `friday` read, in that zone, and all-day events stay on their dates.
An event set in another zone also shows its own time.
Events that run past midnight show on each day (`22:00–…`, then `…–01:30`). With `--days`,
days without events are left out. `--calendar` takes the same names and ids as `add`, and a
name shared by several calendars includes all of them. Titles longer than 40 characters are
shortened with `…`. `--verbose` adds the full title, the event's time zone, location, URL,
notes, the full calendar name and the event id.

## Searching

```
calutil search dvorak                         # from today to a year ahead
calutil search new world --location opera
calutil search --title concert --from 2025-01-01 --to 2025-12-31 --calendar Home
```

Every word must appear in the title, location or notes (in any of them, in any order);
`--title`, `--location` and `--notes` look in one field only, and everything given must match.
Case, accents and curly quotes don't matter, so `dvorak's` finds "Dvořák’s". The search covers
today to a year ahead unless you give `--from` and `--to` (both take the same days as `list`).
Matches are shown as `list` shows them, followed by how many there were; a repeating event
shows each time it occurs.

## Changing and deleting events

```
calutil edit --match prokofiev --title "Prokofiev's Second Piano Concerto"
calutil edit --match "lena berg" --on 2027-07-05 --start 2027-07-05T19:30 --save
calutil edit --id 1A2B3C4D-…:5E6F7A8B-… --map "Sydney Opera House" --save
calutil delete --match dentist --on 2026-12-01 --yes
```

Pick the event with `--id` (which `search --verbose` shows) or with `--match`, which searches
as `calutil search` does (`--match-title`, `--match-location`, `--match-notes`,
`--match-calendar`, and `--on DAY` or `--from`/`--to` for the days). A search must find exactly
one event; otherwise the matches are listed and nothing happens.

`edit` takes the same options as `add`, and only what you give changes: `--start` moves the
event and keeps its length (a day alone keeps the time too), `--timezone` keeps the clock time
(or, with `--keep-time`, the moment: an event stored as 00:00 GMT becomes 13:00 in Auckland),
`--calendar` moves it to another calendar, a new `--location` gets a new map point, and `--map`
on its own adds one. It shows what would change, as `-` old and `+` new lines, and changes
nothing without `--save`. `delete` shows the event and deletes nothing without `--yes`.

A repeating event has one id for all its occurrences: with `--id`, say which with `--on DAY`.
Only that occurrence changes, unless you add `--future` for it and the later ones too.

`edit --all` changes every event a `--match` search finds, for changes that suit them all:
`--location`, `--notes`, `--url`, `--calendar`, `--timezone` (with or without `--keep-time`),
the alarm options and the map options, but not `--title` or the times. All-day events are left
out of a time zone change. It shows each event's changes, and with `--save` makes them
together, all or none:

```
calutil edit --match-notes "Trip 2026" --all --tz Pacific/Auckland --keep-time --save
calutil edit --match concert --match-calendar Home --all --add-alarm 1d --save
```

## Templates

A JSON file at `~/.config/calutil/templates.json` (or `$XDG_CONFIG_HOME/calutil/templates.json`
if you set that), or wherever `$CALUTIL_TEMPLATES` or `--templates` points. Comments and trailing commas are allowed. See
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

Settings: `title`, `location`, `map`, `notes`, `url`, `calendar`, `timezone`, `time`, `duration`,
`allDay`, `alarms`. A misspelt setting is an error rather than being silently ignored.

Because of the comments, tools such as `jq` can't read the file directly. `calutil templates
--json` prints it as strict JSON instead: `calutil templates --json | jq .concert`.

## Shell completion

```
calutil completion install
```

Writes the completion script into a directory your shell searches, creating it if needed,
and then says whether that directory is one your shell actually reads. If it is not, it
prints the line to add and where to add it: a completion script in an unsearched directory
does nothing and says nothing about it. It picks the destination for you (`--shell
zsh|bash|all`, `--dir` to override, `--dry-run` to see the choice first) and never edits
your startup files. `calutil completion zsh` prints the script if you would rather place it
yourself. (This is how the Go tools built on cobrakit do it.)

Tab then offers commands and options with what they do, and for values: your template
names, your calendars (once calutil has Calendar access; Tab never asks for it), time
zones, day words, durations and alarms. They are read each time, so a new template or
calendar is offered straight away.

## Development

```
swift build
swift test
```

`Sources/CalUtilCore` holds everything that can be tested without touching your calendar:
argument parsing, templates, dates, the summary, the event list and the iCalendar writer.
`Sources/calutil` is the executable and the EventKit code. `Sources/calutil/Info.plist` is
linked into the binary, because macOS won't grant calendar access to a program that doesn't
say why it wants it.

## License

Apache-2.0. See `LICENSE`.
