import Foundation

/// What to run, parsed from the command line: `calutil <command> [options]`.
public enum Invocation: Equatable, Sendable {
    case add(AddOptions)
    case list(ListOptions)
    case search(SearchOptions)
    case edit(EditOptions)
    case delete(DeleteOptions)
    case calendars(verbose: Bool)
    case templates(path: String?, json: Bool)
    /// Help, for one command when given.
    case help(String?)
    case version

    public static let commands = ["add", "list", "search", "edit", "delete", "calendars", "templates", "help", "version"]

    public static func parse(_ arguments: [String]) throws -> Invocation {
        guard let command = arguments.first else { return .help(nil) }
        let rest = Array(arguments.dropFirst())

        switch command {
        case "-h", "--help":
            return .help(nil)
        case "help":
            guard let topic = rest.first else { return .help(nil) }
            guard Help.text(for: topic) != nil else {
                throw CalUtilError("no help for '\(topic)' (commands: \(commands.joined(separator: ", ")))", usage: true)
            }
            return .help(topic)
        case "version", "--version":
            return .version
        case "add":
            return try helpOr("add") { .add(try AddOptions.parse(rest)) }
        case "list":
            return try helpOr("list") { .list(try ListOptions.parse(rest)) }
        case "search":
            return try helpOr("search") { .search(try SearchOptions.parse(rest)) }
        case "edit":
            return try helpOr("edit") { .edit(try EditOptions.parse(rest)) }
        case "delete":
            return try helpOr("delete") { .delete(try DeleteOptions.parse(rest)) }
        case "calendars":
            return try helpOr("calendars") {
                var scanner = ArgumentScanner(rest, command: command)
                var verbose = false
                while try scanner.next() {
                    switch scanner.name {
                    case "-v", "--verbose": try scanner.flag(); verbose = true
                    default: throw scanner.unexpected()
                    }
                }
                return .calendars(verbose: verbose)
            }
        case "templates":
            return try helpOr("templates") {
                var scanner = ArgumentScanner(rest, command: command)
                var path: String?
                var json = false
                while try scanner.next() {
                    switch scanner.name {
                    case "--templates": path = (try scanner.single() as NSString).expandingTildeInPath
                    case "--json": try scanner.flag(); json = true
                    default: throw scanner.unexpected()
                    }
                }
                return .templates(path: path, json: json)
            }
        default:
            if command.hasPrefix("-") {
                throw CalUtilError("put the command first, e.g. calutil add \(command) … (see calutil help)", usage: true)
            }
            throw CalUtilError("unknown command '\(command)' (commands: \(commands.joined(separator: ", ")))", usage: true)
        }
    }
}

/// `calutil list [DAY] [--days N] [--calendar NAME]... [--verbose]`
public struct ListOptions: Equatable, Sendable {
    /// Nil means today.
    public var day: String?
    public var days = 1
    /// Empty means all calendars.
    public var calendars: [String] = []
    public var verbose = false

    public init() {}

    public static let maxDays = 1_000

    public static func parse(_ arguments: [String]) throws -> ListOptions {
        var options = ListOptions()
        var scanner = ArgumentScanner(arguments, command: "list")
        while try scanner.next() {
            switch scanner.name {
            case "--days":
                let text = try scanner.single()
                guard let days = Int(text), (1...maxDays).contains(days) else {
                    throw CalUtilError("--days takes a number from 1 to \(maxDays), not '\(text)'", usage: true)
                }
                options.days = days
            case "--calendar": options.calendars.append(try scanner.value())
            case "-v", "--verbose": try scanner.flag(); options.verbose = true
            default:
                if scanner.isOption { throw scanner.unexpected() }
                guard options.day == nil else {
                    throw CalUtilError("give one day to list (use --days for more than one)", usage: true)
                }
                options.day = scanner.argument
            }
        }
        return options
    }
}

/// Thrown by the scanner when `-h`/`--help` appears where an option is expected.
struct HelpRequested: Error {}

/// Runs a command's parser, turning a help request anywhere in it into `.help(command)`.
private func helpOr(_ command: String, _ parse: () throws -> Invocation) throws -> Invocation {
    do { return try parse() } catch is HelpRequested { return .help(command) }
}

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

/// `calutil add` as given, before templates and defaults are applied.
public struct AddOptions: Equatable, Sendable {
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
    /// `--map`: search text or coordinates for the map, instead of the location text.
    public var map: String?
    /// `--map-match`: which of the search's matches to use (1-based).
    public var mapMatch: Int?
    public var noMap = false

    public init() {}

    public static func parse(_ arguments: [String]) throws -> AddOptions {
        var options = AddOptions()
        var scanner = ArgumentScanner(arguments, command: "add", aliases: ["--tz": "--timezone"])
        var actionFlag: String?

        func setAction(_ action: Action) throws {
            try scanner.flag()
            if let previous = actionFlag, previous != scanner.name {
                throw CalUtilError("\(previous) and \(scanner.typed) can't be combined; pick one", usage: true)
            }
            actionFlag = scanner.name
            options.action = action
        }

        while try scanner.next() {
            switch scanner.name {
            case "--save": try setAction(.save)
            case "--open": try setAction(.openICS)
            case "--ics": try setAction(.printICS)
            case "--dry-run": try setAction(.dryRun)

            case "--template": options.template = trimmedNonEmpty(try scanner.single())  // "" = none
            case "--templates": options.templatesPath = (try scanner.single() as NSString).expandingTildeInPath

            default:
                if try options.takeField(&scanner) { continue }
                if scanner.isOption { throw scanner.unexpected() }
                throw CalUtilError(
                    "unexpected argument '\(scanner.argument)': values are given with named options, e.g. --title \"\(scanner.argument)\"",
                    usage: true)
            }
        }
        try options.checkFields()
        return options
    }

    /// The event's settings, shared with `edit`: true when the scanner's option was one.
    mutating func takeField(_ scanner: inout ArgumentScanner) throws -> Bool {
        switch scanner.name {
        case "--title": title = try scanner.single()
        case "--location": location = try scanner.single()
        case "--notes": notes = try scanner.single()
        case "--url": url = try scanner.single()
        case "--calendar": calendar = try scanner.single()
        case "--timezone": timezone = try scanner.single()
        case "--start": start = try scanner.single()
        case "--end": end = try scanner.single()
        case "--duration": duration = try scanner.single()

        case "--all-day": try scanner.flag(); allDay = true
        case "--no-all-day": try scanner.flag(); allDay = false

        case "--alarm": alarms = (alarms ?? []) + [try scanner.value()]
        case "--add-alarm": addAlarms.append(try scanner.value())
        case "--no-alarms": try scanner.flag(); noAlarms = true

        case "--map": map = try scanner.single()
        case "--map-match":
            let text = try scanner.single()
            guard let n = Int(text), (1...Places.maxMatches).contains(n) else {
                throw CalUtilError("--map-match takes a number from 1 to \(Places.maxMatches), not '\(text)'", usage: true)
            }
            mapMatch = n
        case "--no-map": try scanner.flag(); noMap = true
        default: return false
        }
        return true
    }

    func checkFields() throws {
        if noAlarms && alarms != nil {
            throw CalUtilError("--no-alarms and --alarm can't be combined (--alarm already replaces the template's alarms)", usage: true)
        }
        if noMap && (map != nil || mapMatch != nil) {
            throw CalUtilError("--no-map can't be combined with --map or --map-match", usage: true)
        }
        if end != nil && duration != nil {
            throw CalUtilError("use either --end or --duration, not both", usage: true)
        }
    }
}

/// Walks the arguments of one command: `--name value`, `--name=value`, flags, and
/// positional arguments.
struct ArgumentScanner {
    let command: String
    private let arguments: [String]
    private var index = -1
    private var seen: Set<String> = []

    /// The argument as typed.
    private(set) var argument = ""
    /// The option's main name (`--title` for `--title=x`, `--timezone` for `--tz`), or the
    /// positional argument. For matching; messages use `typed`.
    private(set) var name = ""
    /// The option name as typed (`--tz`).
    private(set) var typed = ""
    private(set) var inline: String?
    /// Other spellings of this command's options, mapped to their main name.
    private let aliases: [String: String]

    init(_ arguments: [String], command: String, aliases: [String: String] = [:]) {
        self.arguments = arguments
        self.command = command
        self.aliases = aliases
    }

    var isOption: Bool { argument.hasPrefix("-") && argument.count > 1 }

    /// Moves to the next argument. Throws `HelpRequested` for `-h`/`--help`.
    mutating func next() throws -> Bool {
        index += 1
        guard index < arguments.count else { return false }
        argument = arguments[index]
        name = argument
        inline = nil
        if argument.hasPrefix("--"), let eq = argument.firstIndex(of: "=") {
            name = String(argument[..<eq])
            inline = String(argument[argument.index(after: eq)...])
        }
        typed = name
        name = aliases[name] ?? name
        if name == "-h" || name == "--help" { throw HelpRequested() }
        return true
    }

    /// The option's value: after `=`, or the next argument.
    mutating func value() throws -> String {
        if let inline { return inline }
        guard index + 1 < arguments.count, !arguments[index + 1].hasPrefix("--") else {
            throw CalUtilError("\(typed) needs a value", usage: true)
        }
        index += 1
        return arguments[index]
    }

    /// Like `value()`, for options that may be given only once.
    mutating func single() throws -> String {
        guard seen.insert(name).inserted else {
            let spellings = [name] + aliases.filter { $0.value == name }.keys.sorted()
            throw CalUtilError("\(spellings.joined(separator: " / ")) was given more than once", usage: true)
        }
        return try value()
    }

    func flag() throws {
        guard inline == nil else { throw CalUtilError("\(typed) does not take a value", usage: true) }
    }

    func unexpected() -> CalUtilError {
        if isOption {
            return CalUtilError("unknown option \(typed) for 'calutil \(command)' (see calutil help \(command))", usage: true)
        }
        return CalUtilError("unexpected argument '\(argument)' for 'calutil \(command)' (see calutil help \(command))", usage: true)
    }
}
