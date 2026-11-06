import Foundation

/// What to run, parsed from the command line: `calutil <command> [options]`.
public enum Invocation: Equatable, Sendable {
    case add(AddOptions)
    case list(ListOptions)
    case calendars(verbose: Bool)
    case templates(path: String?)
    /// Help, for one command when given.
    case help(String?)
    case version

    public static let commands = ["add", "list", "calendars", "templates", "help", "version"]

    public static func parse(_ arguments: [String]) throws -> Invocation {
        guard let command = arguments.first else { return .help(nil) }
        let rest = Array(arguments.dropFirst())
        let wantsHelp = rest.contains("-h") || rest.contains("--help")

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
            return wantsHelp ? .help("add") : .add(try AddOptions.parse(rest))
        case "list":
            return wantsHelp ? .help("list") : .list(try ListOptions.parse(rest))
        case "calendars":
            if wantsHelp { return .help("calendars") }
            var scanner = ArgumentScanner(rest, command: command)
            var verbose = false
            while scanner.next() {
                switch scanner.name {
                case "-v", "--verbose": try scanner.flag(); verbose = true
                default: throw scanner.unexpected()
                }
            }
            return .calendars(verbose: verbose)
        case "templates":
            if wantsHelp { return .help("templates") }
            var scanner = ArgumentScanner(rest, command: command)
            var path: String?
            while scanner.next() {
                switch scanner.name {
                case "--templates": path = (try scanner.single() as NSString).expandingTildeInPath
                default: throw scanner.unexpected()
                }
            }
            return .templates(path: path)
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
        while scanner.next() {
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

    public init() {}

    public static func parse(_ arguments: [String]) throws -> AddOptions {
        var options = AddOptions()
        var scanner = ArgumentScanner(arguments, command: "add")
        var actionFlag: String?

        func setAction(_ action: Action) throws {
            try scanner.flag()
            if let previous = actionFlag, previous != scanner.name {
                throw CalUtilError("\(previous) and \(scanner.name) can't be combined; pick one", usage: true)
            }
            actionFlag = scanner.name
            options.action = action
        }

        while scanner.next() {
            switch scanner.name {
            case "--save": try setAction(.save)
            case "--open": try setAction(.openICS)
            case "--ics": try setAction(.printICS)
            case "--dry-run": try setAction(.dryRun)

            case "--template": options.template = try scanner.single()
            case "--templates": options.templatesPath = (try scanner.single() as NSString).expandingTildeInPath
            case "--title": options.title = try scanner.single()
            case "--location": options.location = try scanner.single()
            case "--notes": options.notes = try scanner.single()
            case "--url": options.url = try scanner.single()
            case "--calendar": options.calendar = try scanner.single()
            case "--timezone", "--tz": options.timezone = try scanner.single()
            case "--start": options.start = try scanner.single()
            case "--end": options.end = try scanner.single()
            case "--duration": options.duration = try scanner.single()

            case "--all-day": try scanner.flag(); options.allDay = true
            case "--no-all-day": try scanner.flag(); options.allDay = false

            case "--alarm": options.alarms = (options.alarms ?? []) + [try scanner.value()]
            case "--add-alarm": options.addAlarms.append(try scanner.value())
            case "--no-alarms": try scanner.flag(); options.noAlarms = true

            default:
                if scanner.isOption { throw scanner.unexpected() }
                throw CalUtilError(
                    "unexpected argument '\(scanner.argument)': values are given with named options, e.g. --title \"\(scanner.argument)\"",
                    usage: true)
            }
        }

        if options.noAlarms && options.alarms != nil {
            throw CalUtilError("--no-alarms and --alarm can't be combined (--alarm already replaces the template's alarms)", usage: true)
        }
        return options
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
    /// The option name (`--title` for `--title=x`), or the positional argument.
    private(set) var name = ""
    private(set) var inline: String?

    init(_ arguments: [String], command: String) {
        self.arguments = arguments
        self.command = command
    }

    var isOption: Bool { argument.hasPrefix("-") && argument.count > 1 }

    mutating func next() -> Bool {
        index += 1
        guard index < arguments.count else { return false }
        argument = arguments[index]
        name = argument
        inline = nil
        if argument.hasPrefix("--"), let eq = argument.firstIndex(of: "=") {
            name = String(argument[..<eq])
            inline = String(argument[argument.index(after: eq)...])
        }
        return true
    }

    /// The option's value: after `=`, or the next argument.
    mutating func value() throws -> String {
        if let inline { return inline }
        guard index + 1 < arguments.count, !arguments[index + 1].hasPrefix("--") else {
            throw CalUtilError("\(name) needs a value", usage: true)
        }
        index += 1
        return arguments[index]
    }

    /// Like `value()`, for options that may be given only once.
    mutating func single() throws -> String {
        guard seen.insert(name).inserted else {
            throw CalUtilError("\(name) was given more than once", usage: true)
        }
        return try value()
    }

    func flag() throws {
        guard inline == nil else { throw CalUtilError("\(name) does not take a value", usage: true) }
    }

    func unexpected() -> CalUtilError {
        if isOption {
            return CalUtilError("unknown option \(name) for 'calutil \(command)' (see calutil help \(command))", usage: true)
        }
        return CalUtilError("unexpected argument '\(argument)' for 'calutil \(command)' (see calutil help \(command))", usage: true)
    }
}
