import Foundation

/// Shell completion: the zsh and bash scripts, and the suggestions they ask
/// `calutil __complete WORDS...` for as you type, so templates, calendars and time zones
/// are offered as they are now rather than as they were when the script was written.
public enum Completion {
    /// What an option's value is, which decides what is offered for it.
    public enum Kind: Equatable, Sendable {
        case flag, text, template, file, directory, calendar, timeZone, day, dateTime, duration, alarm, shell
        case number([String])
    }

    public struct Option: Sendable {
        public var name: String
        public var kind: Kind
        public var help: String
    }

    public struct Candidate: Equatable, Sendable {
        public var value: String
        public var help: String
        public init(_ value: String, _ help: String = "") {
            self.value = value
            self.help = help
        }
    }

    public enum Reply: Equatable, Sendable {
        case values([Candidate])
        case files
        case directories
    }

    /// Where dynamic values come from: the templates file, Calendar, the system's zones.
    public struct Source: Sendable {
        public var templates: @Sendable (_ path: String?) -> [String]
        public var calendars: @Sendable () -> [Candidate]
        public var timeZones: @Sendable () -> [String]

        public init(templates: @escaping @Sendable (String?) -> [String],
                    calendars: @escaping @Sendable () -> [Candidate],
                    timeZones: @escaping @Sendable () -> [String] = { TimeZone.knownTimeZoneIdentifiers }) {
            self.templates = templates
            self.calendars = calendars
            self.timeZones = timeZones
        }
    }

    // MARK: - The options of each command

    static let help = Option(name: "--help", kind: .flag, help: "show this command's help")

    static let fields: [Option] = [
        Option(name: "--title", kind: .text, help: "event title"),
        Option(name: "--location", kind: .text, help: "where (looked up on the map)"),
        Option(name: "--notes", kind: .text, help: "notes"),
        Option(name: "--url", kind: .text, help: "a link"),
        Option(name: "--calendar", kind: .calendar, help: "calendar to put it in"),
        Option(name: "--timezone", kind: .timeZone, help: "time zone the times are in"),
        Option(name: "--tz", kind: .timeZone, help: "same as --timezone"),
        Option(name: "--start", kind: .dateTime, help: "when it starts"),
        Option(name: "--end", kind: .dateTime, help: "when it ends (or a time)"),
        Option(name: "--duration", kind: .duration, help: "length instead of --end"),
        Option(name: "--all-day", kind: .flag, help: "make it an all-day event"),
        Option(name: "--no-all-day", kind: .flag, help: "make it a timed event"),
        Option(name: "--alarm", kind: .alarm, help: "set an alarm, replacing the others"),
        Option(name: "--add-alarm", kind: .alarm, help: "add an alarm"),
        Option(name: "--no-alarms", kind: .flag, help: "no alarms"),
        Option(name: "--map", kind: .text, help: "search text or LAT,LON for the map"),
        Option(name: "--map-match", kind: .number(["1", "2", "3", "4", "5"]), help: "use the Nth map match"),
        Option(name: "--no-map", kind: .flag, help: "keep the location as text only"),
    ]

    static let selection: [Option] = [
        Option(name: "--id", kind: .text, help: "the event's id (search --verbose shows it)"),
        Option(name: "--match", kind: .text, help: "find it by title, location or notes"),
        Option(name: "--match-title", kind: .text, help: "find it by title"),
        Option(name: "--match-location", kind: .text, help: "find it by location"),
        Option(name: "--match-notes", kind: .text, help: "find it by notes"),
        Option(name: "--match-calendar", kind: .calendar, help: "only in this calendar"),
        Option(name: "--on", kind: .day, help: "the day it is on"),
        Option(name: "--from", kind: .day, help: "first day to search"),
        Option(name: "--to", kind: .day, help: "last day to search"),
        Option(name: "--future", kind: .flag, help: "also the later occurrences"),
    ]

    static let options: [String: [Option]] = [
        "add": [
            Option(name: "--save", kind: .flag, help: "add it to Calendar"),
            Option(name: "--open", kind: .flag, help: "import it in Calendar as an .ics file"),
            Option(name: "--ics", kind: .flag, help: "print it as iCalendar"),
            Option(name: "--dry-run", kind: .flag, help: "only show it (the default)"),
            Option(name: "--template", kind: .template, help: "start from a template"),
            Option(name: "--templates", kind: .file, help: "template file"),
        ] + fields + [help],
        "list": [
            Option(name: "--days", kind: .number(["7", "14", "30"]), help: "how many days"),
            Option(name: "--calendar", kind: .calendar, help: "only this calendar"),
            Option(name: "--timezone", kind: .timeZone, help: "show the times in this zone"),
            Option(name: "--tz", kind: .timeZone, help: "same as --timezone"),
            Option(name: "--verbose", kind: .flag, help: "show more of each event"),
            help,
        ],
        "search": [
            Option(name: "--title", kind: .text, help: "look in the title only"),
            Option(name: "--location", kind: .text, help: "look in the location only"),
            Option(name: "--notes", kind: .text, help: "look in the notes only"),
            Option(name: "--from", kind: .day, help: "first day (default today)"),
            Option(name: "--to", kind: .day, help: "last day (default a year ahead)"),
            Option(name: "--calendar", kind: .calendar, help: "only this calendar"),
            Option(name: "--timezone", kind: .timeZone, help: "show the times in this zone"),
            Option(name: "--tz", kind: .timeZone, help: "same as --timezone"),
            Option(name: "--verbose", kind: .flag, help: "show more of each event"),
            help,
        ],
        "edit": selection + fields + [
            Option(name: "--keep-time", kind: .flag, help: "with --timezone: keep the moment, not the clock time"),
            Option(name: "--save", kind: .flag, help: "make the change"),
            Option(name: "--dry-run", kind: .flag, help: "only show the change (the default)"),
            help,
        ],
        "delete": selection + [
            Option(name: "--yes", kind: .flag, help: "delete it"),
            Option(name: "--dry-run", kind: .flag, help: "only show it (the default)"),
            help,
        ],
        "calendars": [Option(name: "--verbose", kind: .flag, help: "ids, colours and contents"), help],
        "templates": [
            Option(name: "--templates", kind: .file, help: "template file"),
            Option(name: "--json", kind: .flag, help: "print them as JSON"),
            help,
        ],
        "completion install": [
            Option(name: "--shell", kind: .shell, help: "zsh, bash, all or auto"),
            Option(name: "--dir", kind: .directory, help: "install into this directory"),
            Option(name: "--dry-run", kind: .flag, help: "say where, write nothing"),
            help,
        ],
    ]

    static let commandHelp: [(String, String)] = [
        ("add", "add an event"), ("list", "show the events on a day"), ("search", "find events"),
        ("edit", "change an event"), ("delete", "delete an event"), ("calendars", "list your calendars"),
        ("templates", "list the templates"), ("completion", "shell completion"), ("help", "show help"),
        ("version", "show the version"),
    ]

    static let dayWords = ["today", "tomorrow", "yesterday", "monday", "tuesday", "wednesday", "thursday",
                           "friday", "saturday", "sunday"]

    // MARK: - Suggestions

    /// The options and values of the command being typed. `words` are the words after
    /// `calutil`, the last being the one being completed (possibly empty).
    static func context(_ words: [String]) -> (command: String?, options: [Option]) {
        guard words.count > 1 else { return (nil, []) }
        var command = words[0]
        if command == "completion", words.count > 2, words[1] == "install" { command = "completion install" }
        return (command, options[command] ?? [])
    }

    /// The kind of value being typed, when it is an option's value.
    static func valueKind(_ words: [String]) -> (kind: Kind, prefix: String)? {
        let (_, options) = context(words)
        let current = words.last ?? ""
        if current.hasPrefix("--"), let eq = current.firstIndex(of: "=") {
            let name = String(current[..<eq])
            guard let option = options.first(where: { $0.name == name }), option.kind != .flag else { return nil }
            return (option.kind, name + "=")
        }
        guard words.count >= 2, let option = options.first(where: { $0.name == words[words.count - 2] }),
              option.kind != .flag else { return nil }
        return (option.kind, "")
    }

    /// True when the suggestions need Calendar (calendar names), so calutil must run as
    /// its own process to read them.
    public static func needsCalendars(_ words: [String]) -> Bool {
        valueKind(words)?.kind == .calendar
    }

    public static func reply(for words: [String], source: Source) -> Reply {
        let current = words.last ?? ""
        guard words.count > 1 else {
            return .values(commandHelp.map { Candidate($0.0, $0.1) })
        }
        let (command, options) = context(words)

        if let (kind, prefix) = valueKind(words) {
            func values(_ list: [String]) -> Reply { .values(list.map { Candidate(prefix + $0) }) }
            switch kind {
            case .flag, .text: return .values([])
            case .file: return prefix.isEmpty ? .files : .values([])
            case .directory: return prefix.isEmpty ? .directories : .values([])
            case .template:
                let path = templatesPath(in: words)
                return values(source.templates(path).sorted())
            case .calendar:
                return .values(source.calendars().map { Candidate(prefix + $0.value, $0.help) })
            case .timeZone: return values(source.timeZones())
            case .day, .dateTime: return values(dayWords)
            case .duration: return values(["30m", "1h", "1h30m", "2h", "3h", "1d"])
            case .alarm: return values(["0", "15m", "30m", "1h", "2h", "1d", "2d", "1w", "09:00"])
            case .shell: return values(["zsh", "bash", "all", "auto"])
            case .number(let list): return values(list)
            }
        }

        if current.hasPrefix("-") {
            return .values(options.map { Candidate($0.name, $0.help) })
        }
        switch command {
        case "help": return words.count == 2 ? .values(commandHelp.filter { $0.0 != "version" }.map { Candidate($0.0, $0.1) }) : .values([])
        case "list": return .values(dayWords.map { Candidate($0) })
        case "completion":
            return words.count == 2
                ? .values([Candidate("zsh", "print the zsh script"), Candidate("bash", "print the bash script"),
                           Candidate("install", "install it where your shell reads it")])
                : .values([])
        default: return .values([])
        }
    }

    /// A --templates given earlier on the line.
    static func templatesPath(in words: [String]) -> String? {
        for (index, word) in words.dropLast().enumerated() {
            if word == "--templates", index + 1 < words.count - 1 { return words[index + 1] }
            if word.hasPrefix("--templates=") { return String(word.dropFirst("--templates=".count)) }
        }
        return nil
    }

    /// What `__complete` prints: `:files`, `:dirs`, or a line per value, a tab before its help.
    public static func render(_ reply: Reply) -> String {
        switch reply {
        case .files: ":files"
        case .directories: ":dirs"
        case .values(let candidates):
            candidates.map { $0.help.isEmpty ? $0.value : "\($0.value)\t\($0.help)" }.joined(separator: "\n")
        }
    }

    // MARK: - Scripts

    public static let shells = ["zsh", "bash"]

    /// The file name the shell looks for: zsh autoloads `_calutil` from its fpath, bash-completion
    /// loads `calutil` from its completions directory.
    public static func fileName(for shell: String) -> String {
        shell == "zsh" ? "_calutil" : "calutil"
    }

    public static func script(for shell: String) -> String? {
        switch shell {
        case "zsh": zshScript
        case "bash": bashScript
        default: nil
        }
    }

    static let zshScript = #"""
    #compdef calutil
    # zsh completion for calutil. Suggestions come from 'calutil __complete', so templates,
    # calendars and time zones are offered as they are now.

    _calutil() {
      local -a reply candidates
      local line value description
      reply=("${(@f)$(calutil __complete "${(@)words[2,CURRENT]}" 2>/dev/null)}")
      case "${reply[1]}" in
        :files) _files; return ;;
        :dirs) _files -/; return ;;
      esac
      for line in "${reply[@]}"; do
        [[ -z "$line" ]] && continue
        value="${line%%$'\t'*}"
        value="${value//:/\\:}"
        if [[ "$line" == *$'\t'* ]]; then
          description="${line#*$'\t'}"
          candidates+=("$value:$description")
        else
          candidates+=("$value")
        fi
      done
      (( ${#candidates} )) && _describe -t values calutil candidates
    }

    if [[ "${funcstack[1]}" == "_calutil" ]]; then
      _calutil "$@"
    else
      compdef _calutil calutil
    fi

    """#

    static let bashScript = #"""
    # bash completion for calutil. Suggestions come from 'calutil __complete', so templates,
    # calendars and time zones are offered as they are now.

    _calutil() {
      local cur="${COMP_WORDS[COMP_CWORD]}" reply line value
      reply="$(calutil __complete "${COMP_WORDS[@]:1:COMP_CWORD}" 2>/dev/null)"
      COMPREPLY=()
      case "$reply" in
        :files) COMPREPLY=($(compgen -f -- "$cur")); compopt -o filenames 2>/dev/null; return ;;
        :dirs) COMPREPLY=($(compgen -d -- "$cur")); compopt -o filenames 2>/dev/null; return ;;
      esac
      while IFS= read -r line; do
        value="${line%%$'\t'*}"
        [[ -n "$value" && "$value" == "$cur"* ]] && COMPREPLY+=("$(printf '%q' "$value")")
      done <<< "$reply"
    }

    complete -F _calutil calutil

    """#
}

public enum CompletionInstall {
    /// How good a directory on zsh's fpath is for the script; 0 means don't use it. As in
    /// cobrakit: a "cache" directory is refused (oh-my-zsh empties its own, so a script there
    /// works until it silently doesn't); site-functions beats completions; and one under your
    /// home beats a system one, needing no privileges and surviving upgrades.
    public static func score(_ dir: String, home: String) -> Int {
        if dir.contains("/cache/") || dir.hasSuffix("/cache") { return 0 }
        var score: Int
        if dir.hasSuffix("site-functions") {
            score = 2
        } else if dir.hasSuffix("completions") {
            score = 1
        } else {
            return 0  // a framework's function library: not a place for completion scripts
        }
        if !home.isEmpty && dir.hasPrefix(home + "/") { score += 10 }
        return score
    }
}
