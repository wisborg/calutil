import Foundation

/// A point on the map for an event's location: found by a search, or given as coordinates.
public struct Place: Equatable, Sendable {
    public var name: String?
    /// On one line: "Bennelong Point, Sydney NSW 2000, Australia".
    public var address: String?
    public var latitude: Double
    public var longitude: Double

    public init(name: String? = nil, address: String? = nil, latitude: Double, longitude: Double) {
        self.name = trimmedNonEmpty(name)
        self.address = trimmedNonEmpty(address)
        self.latitude = latitude
        self.longitude = longitude
    }

    /// "-33.8569, 151.2153"
    public var coordinates: String {
        String(format: "%.4f, %.4f", latitude, longitude)
    }

    /// "Sydney Opera House, Bennelong Point, Sydney NSW 2000, Australia", or the coordinates.
    public var description: String {
        let parts = [name, address].compactMap { $0 }
        return parts.isEmpty ? coordinates : parts.joined(separator: ", ")
    }

    /// The location text Calendar uses for a place: the name, and the address on the next line.
    public var locationText: String {
        let parts = [name, address].compactMap { $0 }
        return parts.isEmpty ? coordinates : parts.joined(separator: "\n")
    }
}

/// What to look up on the map for an event.
public enum MapRequest: Equatable, Sendable {
    /// No location, or --no-map.
    case none
    /// Search for this text; `pick` is --map-match (1-based), nil for the best match.
    case search(String, pick: Int?)
    /// --map with coordinates: no search.
    case place(Place)
}

public enum Places {
    /// How many matches a search keeps (and the dry run lists).
    public static let maxMatches = 5

    /// "-33.8569,151.2153" or "-33.8569, 151.2153" (latitude first).
    public static func parseCoordinates(_ text: String) -> Place? {
        let parts = text.split(separator: ",", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces) }
        guard parts.count == 2,
              parts.allSatisfy({ !$0.isEmpty && $0.allSatisfy { "0123456789.-+".contains($0) } }),
              let latitude = Double(parts[0]), let longitude = Double(parts[1]),
              (-90...90).contains(latitude), (-180...180).contains(longitude)
        else { return nil }
        return Place(latitude: latitude, longitude: longitude)
    }

    /// The text to search for: the location's lines on one line.
    public static func query(for location: String) -> String {
        location.lines.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
            .joined(separator: ", ")
    }

    /// The match to use when none is picked: the first one named like the location's first
    /// line ("Sydney Opera House" rather than a car park near it), else the first.
    public static func bestMatch(_ matches: [Place], for query: String) -> Int {
        let wanted = (query.lines.first ?? query).split(separator: ",").first
            .map { $0.trimmingCharacters(in: .whitespaces) } ?? ""
        return matches.firstIndex { place in
            guard let name = place.name else { return false }
            return name.compare(wanted, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
        } ?? 0
    }

    /// Puts the chosen match on the event. With no location text, the place's name and
    /// address become the location.
    public static func choose(from matches: [Place], query: String, pick: Int?, for event: inout EventSpec) throws {
        guard !matches.isEmpty else {
            if pick != nil { throw CalUtilError("--map-match: nothing found on the map for '\(query)'") }
            event.warnings.append("nothing found on the map for '\(query)'; the location is kept as text only (try --map with other words, or coordinates)")
            return
        }
        let index: Int
        if let pick {
            guard (1...matches.count).contains(pick) else {
                let count = matches.count == 1 ? "1 match" : "\(matches.count) matches"
                throw CalUtilError("--map-match \(pick): there are only \(count) for '\(query)' (see the dry run)")
            }
            index = pick - 1
        } else {
            index = bestMatch(matches, for: query)
        }
        event.matches = matches
        use(matches[index], for: &event)
    }

    public static func use(_ place: Place, for event: inout EventSpec) {
        event.place = place
        if event.location == nil { event.location = place.locationText }
    }
}
