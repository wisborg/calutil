import CalAddCore
import Foundation

func printError(_ text: String) {
    fflush(stdout)  // keep stdout and stderr in order when both go to the terminal
    FileHandle.standardError.write(Data((text + "\n").utf8))
}

func loadTemplates(_ options: Options) throws -> (path: String, templates: [String: Template]) {
    let path = options.templatesPath ?? TemplateStore.defaultPath()
    return (path, try TemplateStore.load(from: path))
}

func listTemplates(_ options: Options) throws -> String {
    let (path, templates) = try loadTemplates(options)
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
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("cal-add", isDirectory: true)
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
        throw CalAddError("couldn't open \(file.path) in Calendar")
    }
    return file
}

func run() -> Int32 {
    do {
        let options = try Options.parse(Array(CommandLine.arguments.dropFirst()))
        switch options.command {
        case .help: print(CLI.help); return 0
        case .version: print("cal-add \(CLI.version)"); return 0
        case .listTemplates: print(try listTemplates(options)); return 0
        case .listCalendars: print(try EventKitBackend.listCalendars()); return 0
        case .run: break
        }

        var template: Template?
        if let name = options.template {
            let (path, templates) = try loadTemplates(options)
            guard let found = templates[name] else {
                let known = templates.keys.sorted().joined(separator: ", ")
                throw CalAddError("no template called '\(name)' in \(path)" + (known.isEmpty ? "" : " (available: \(known))"))
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
        return 0
    } catch let error as CalAddError {
        printError("cal-add: \(error.message)")
        return error.isUsage ? 2 : 1
    } catch {
        printError("cal-add: \(error.localizedDescription)")
        return 1
    }
}

exit(run())
