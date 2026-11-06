import CalUtilCore
import Foundation

func printError(_ text: String) {
    fflush(stdout)  // keep stdout and stderr in order when both go to the terminal
    FileHandle.standardError.write(Data((text + "\n").utf8))
}

func loadTemplates(_ path: String?) throws -> (path: String, templates: [String: Template]) {
    let path = path ?? TemplateStore.defaultPath()
    return (path, try TemplateStore.load(from: path))
}

func listTemplates(_ path: String?) throws -> String {
    let (path, templates) = try loadTemplates(path)
    guard !templates.isEmpty else { return "No templates in \(path)." }
    var lines = ["Templates in \(path):"]
    for name in templates.keys.sorted() {
        let t = templates[name]!
        var parts: [String] = []
        if let title = t.title { parts.append("title \"\(title)\"") }
        if t.allDay == true { parts.append("all day") }
        if let time = t.time { parts.append("at \(time)") }
        if let duration = t.duration { parts.append("for \(duration)") }
        if let alarms = t.alarms { parts.append(alarms.isEmpty ? "no alarms" : "alarms \(alarms.joined(separator: ", "))") }
        if let calendar = t.calendar { parts.append("calendar \"\(calendar)\"") }
        if let zone = t.timezone { parts.append(zone) }
        lines.append("  \(name)" + (parts.isEmpty ? "" : ": " + parts.joined(separator: ", ")))
    }
    return lines.joined(separator: "\n")
}

/// Writes the .ics to a temporary file and hands it to Calendar, which shows its import dialog.
func openInCalendar(_ spec: EventSpec) throws -> URL {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("calutil", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let slug = spec.title.lowercased().map { $0.isLetter || $0.isNumber ? String($0) : "-" }.joined()
        .split(separator: "-").joined(separator: "-").prefix(40)
    let file = directory.appendingPathComponent("\(slug.isEmpty ? "event" : String(slug))-\(UUID().uuidString.prefix(8)).ics")
    try Data(ICS.render(spec).utf8).write(to: file)

    let open = Process()
    open.executableURL = URL(fileURLWithPath: "/usr/bin/open")
    open.arguments = ["-a", "Calendar", file.path]
    try open.run()
    open.waitUntilExit()
    guard open.terminationStatus == 0 else {
        throw CalUtilError("couldn't open \(file.path) in Calendar")
    }
    return file
}

/// Commands that use EventKit run as their own responsible process, so the Calendar
/// permission is calutil's rather than the terminal's (see Responsibility.swift).
func needsCalendarAccess(_ invocation: Invocation) -> Bool {
    switch invocation {
    case .calendars: true
    case .add(let options): options.action == .save
    case .templates, .help, .version: false
    }
}

func run() -> Int32 {
    do {
        let invocation = try Invocation.parse(Array(CommandLine.arguments.dropFirst()))
        if needsCalendarAccess(invocation), let status = relaunchAsOwnResponsibleProcess() {
            return status
        }
        switch invocation {
        case .help(let topic):
            print(Help.text(for: topic) ?? Help.text(for: nil)!)
        case .version:
            print("calutil \(Help.version)")
        case .templates(let path):
            print(try listTemplates(path))
        case .calendars(let verbose):
            print(try EventKitBackend.listCalendars(verbose: verbose))
        case .add(let options):
            try add(options)
        }
        return 0
    } catch let error as CalUtilError {
        printError("calutil: \(error.message)")
        return error.isUsage ? 2 : 1
    } catch {
        printError("calutil: \(error.localizedDescription)")
        return 1
    }
}

func add(_ options: AddOptions) throws {
    var template: Template?
    if let name = options.template {
        let (path, templates) = try loadTemplates(options.templatesPath)
        guard let found = templates[name] else {
            let known = templates.keys.sorted().joined(separator: ", ")
            throw CalUtilError("no template called '\(name)' in \(path)" + (known.isEmpty ? "" : " (available: \(known))"))
        }
        template = found
    }

    var spec = try Resolver.resolve(options: options, template: template)
    if options.action == .openICS, spec.calendarName != nil {
        spec.warnings.append("--open can't choose the calendar; pick it in Calendar's import dialog")
    }
    for warning in spec.warnings { printError("warning: \(warning)") }

    switch options.action {
    case .dryRun:
        print(Summary.render(spec))
        printError("\nDry run: nothing was added. Add --save to put it in Calendar, or --open to import it as an .ics file.")
    case .printICS:
        FileHandle.standardOutput.write(Data(ICS.render(spec).utf8))
    case .openICS:
        let file = try openInCalendar(spec)
        print(Summary.render(spec))
        print("\nOpened \(file.path) in Calendar; confirm the import there.")
    case .save:
        let calendar = try EventKitBackend.save(spec)
        spec.calendarName = calendar.title
        print(Summary.render(spec))
        print("\nAdded to \(EventKitBackend.qualifiedName(calendar)).")
    }
}

exit(run())
