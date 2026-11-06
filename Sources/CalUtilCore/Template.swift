import Foundation

/// Defaults for an event. Every field is optional; the command line wins over the template.
/// Values are kept as text here and validated when an event is built from them.
public struct Template: Equatable, Sendable {
    public var name: String
    public var title: String?
    public var location: String?
    public var notes: String?
    public var url: String?
    public var calendar: String?
    public var timezone: String?
    /// Default start time (`19:30`), used when `--start` is a date only.
    public var time: String?
    public var duration: String?
    public var allDay: Bool?
    public var alarms: [String]?

    public init(name: String, title: String? = nil, location: String? = nil, notes: String? = nil,
                url: String? = nil, calendar: String? = nil, timezone: String? = nil, time: String? = nil,
                duration: String? = nil, allDay: Bool? = nil, alarms: [String]? = nil) {
        self.name = name
        self.title = title
        self.location = location
        self.notes = notes
        self.url = url
        self.calendar = calendar
        self.timezone = timezone
        self.time = time
        self.duration = duration
        self.allDay = allDay
        self.alarms = alarms
    }

    static let stringKeys = ["title", "location", "notes", "url", "calendar", "timezone", "time", "duration"]
    static let allKeys = stringKeys + ["allDay", "alarms"]
}

public enum TemplateStore {
    /// `$CALUTIL_TEMPLATES`, else `$XDG_CONFIG_HOME/calutil/templates.json`,
    /// else `~/.config/calutil/templates.json`.
    public static func defaultPath(environment: [String: String] = ProcessInfo.processInfo.environment) -> String {
        if let path = environment["CALUTIL_TEMPLATES"], !path.isEmpty {
            return (path as NSString).expandingTildeInPath
        }
        let configHome = environment["XDG_CONFIG_HOME"].flatMap { $0.isEmpty ? nil : $0 }
            ?? (NSHomeDirectory() as NSString).appendingPathComponent(".config")
        return (configHome as NSString).appendingPathComponent("calutil/templates.json")
    }

    public static func load(from path: String) throws -> [String: Template] {
        guard FileManager.default.fileExists(atPath: path) else {
            throw CalUtilError("no template file at \(path) (create it, or point --templates or $CALUTIL_TEMPLATES at one)")
        }
        let data: Data
        do { data = try Data(contentsOf: URL(fileURLWithPath: path)) } catch {
            throw CalUtilError("can't read \(path): \(error.localizedDescription)")
        }
        return try parse(data, source: path)
    }

    /// Parses the template file: a JSON object of name → object. JSON5 conveniences
    /// (comments, trailing commas, unquoted keys) are allowed.
    public static func parse(_ data: Data, source: String) throws -> [String: Template] {
        let root: Any
        do {
            root = try JSONSerialization.jsonObject(with: data, options: [.json5Allowed])
        } catch {
            let detail = (error as NSError).userInfo[NSDebugDescriptionErrorKey] as? String ?? error.localizedDescription
            throw CalUtilError("\(source) is not valid JSON: \(detail)")
        }
        guard let object = root as? [String: Any] else {
            throw CalUtilError("\(source) must contain a JSON object mapping template names to settings")
        }

        var templates: [String: Template] = [:]
        for (name, value) in object {
            let where_ = "\(source): template '\(name)'"
            guard let fields = value as? [String: Any] else {
                throw CalUtilError("\(where_) must be an object, e.g. { \"duration\": \"2h\" }")
            }
            var template = Template(name: name)
            for (key, value) in fields {
                switch key {
                case _ where Template.stringKeys.contains(key):
                    guard let text = value as? String else {
                        throw CalUtilError("\(where_): \"\(key)\" must be a string")
                    }
                    switch key {
                    case "title": template.title = text
                    case "location": template.location = text
                    case "notes": template.notes = text
                    case "url": template.url = text
                    case "calendar": template.calendar = text
                    case "timezone": template.timezone = text
                    case "time": template.time = text
                    default: template.duration = text
                    }
                case "allDay":
                    guard let number = value as? NSNumber, CFGetTypeID(number) == CFBooleanGetTypeID() else {
                        throw CalUtilError("\(where_): \"allDay\" must be true or false")
                    }
                    template.allDay = number.boolValue
                case "alarms":
                    if let one = value as? String {
                        template.alarms = [one]
                    } else if let list = value as? [Any], let strings = list as? [String], strings.count == list.count {
                        template.alarms = strings
                    } else {
                        throw CalUtilError("\(where_): \"alarms\" must be a list of strings, e.g. [\"1d\", \"2h\"]")
                    }
                default:
                    throw CalUtilError("\(where_): unknown setting \"\(key)\" (known: \(Template.allKeys.joined(separator: ", ")))")
                }
            }
            templates[name] = template
        }
        return templates
    }
}
