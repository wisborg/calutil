import CalUtilCore
import Foundation
import MapKit

/// Finds places on the map with Apple Maps' search, the same one Calendar uses.
enum MapSearch {
    private final class Outcome: @unchecked Sendable {
        var items: [MKMapItem]?
        var error: Error?
        var done = false
    }

    /// The best matches for `query`, at most `Places.maxMatches`. Throws when the search
    /// fails (no network) or takes longer than `timeout`.
    @MainActor
    static func search(_ query: String, timeout: TimeInterval = 10) throws -> [Place] {
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = query
        let outcome = Outcome()
        let search = MKLocalSearch(request: request)
        // The answer arrives on the main thread, so keep its run loop turning until then.
        search.start { response, error in
            outcome.items = response?.mapItems
            outcome.error = error
            outcome.done = true
        }
        let deadline = Date().addingTimeInterval(timeout)
        while !outcome.done && Date() < deadline {
            RunLoop.main.run(mode: .default, before: min(deadline, Date().addingTimeInterval(0.05)))
        }
        guard outcome.done else {
            search.cancel()
            throw CalUtilError("the map search for '\(query)' took too long")
        }
        if let error = outcome.error as? MKError, error.code == .placemarkNotFound { return [] }
        if let error = outcome.error {
            throw CalUtilError("the map search for '\(query)' failed: \(error.localizedDescription)")
        }
        return (outcome.items ?? []).prefix(Places.maxMatches).map(place)
    }

    private static func place(_ item: MKMapItem) -> Place {
        let coordinate: CLLocationCoordinate2D
        let address: String?
        if #available(macOS 26, *) {
            coordinate = item.location.coordinate
            address = item.address.map { Places.query(for: $0.fullAddress) }
        } else {
            coordinate = item.placemark.coordinate
            address = item.placemark.title.map { Places.query(for: $0) }
        }
        return Place(name: item.name, address: address, latitude: coordinate.latitude, longitude: coordinate.longitude)
    }
}

extension MapSearch {
    /// Does what `event.map` asks for: a search, or coordinates as given. A failed search is
    /// a warning, not an error, unless a match was picked (the event would get the wrong one).
    @MainActor
    static func resolve(_ event: inout EventSpec) throws {
        switch event.map {
        case .none:
            return
        case .place(let place):
            Places.use(place, for: &event)
        case .search(let query, let pick):
            let matches: [Place]
            do {
                matches = try search(query)
            } catch let error as CalUtilError where pick == nil {
                event.warnings.append("\(error.message); the location is kept as text only")
                return
            }
            try Places.choose(from: matches, query: query, pick: pick, for: &event)
        }
    }
}
