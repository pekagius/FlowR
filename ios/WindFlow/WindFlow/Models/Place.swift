import Foundation
import CoreLocation

/// A named location: search result, favorite, or a raw map tap.
struct Place: Identifiable, Codable, Hashable {
    var id: String
    var name: String
    var subtitle: String
    var latitude: Double
    var longitude: Double
    var elevation: Double?
    var isFavorite: Bool = false

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    static func fromCoordinate(_ coordinate: CLLocationCoordinate2D) -> Place {
        Place(
            id: String(format: "pt-%.3f-%.3f", coordinate.latitude, coordinate.longitude),
            name: String(format: "%.3f°, %.3f°", coordinate.latitude, coordinate.longitude),
            subtitle: "Picked location",
            latitude: coordinate.latitude,
            longitude: coordinate.longitude
        )
    }
}

/// Persists favorites and recent searches, like Windy's favorites list.
@MainActor
final class FavoritesStore: ObservableObject {
    @Published private(set) var favorites: [Place] = []
    @Published private(set) var recents: [Place] = []

    private let favoritesKey = "favorites.v1"
    private let recentsKey = "recents.v1"

    init() {
        favorites = Self.load(favoritesKey)
        recents = Self.load(recentsKey)
    }

    func isFavorite(_ place: Place) -> Bool {
        favorites.contains { $0.id == place.id }
    }

    func toggleFavorite(_ place: Place) {
        if let index = favorites.firstIndex(where: { $0.id == place.id }) {
            favorites.remove(at: index)
        } else {
            var p = place
            p.isFavorite = true
            favorites.append(p)
        }
        Self.save(favorites, favoritesKey)
    }

    func addRecent(_ place: Place) {
        recents.removeAll { $0.id == place.id }
        recents.insert(place, at: 0)
        if recents.count > 12 { recents.removeLast(recents.count - 12) }
        Self.save(recents, recentsKey)
    }

    func removeFavorites(at offsets: IndexSet) {
        favorites.remove(atOffsets: offsets)
        Self.save(favorites, favoritesKey)
    }

    private static func load(_ key: String) -> [Place] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let places = try? JSONDecoder().decode([Place].self, from: data) else { return [] }
        return places
    }

    private static func save(_ places: [Place], _ key: String) {
        if let data = try? JSONEncoder().encode(places) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }
}
