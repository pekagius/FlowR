import Foundation
import CoreLocation

// MARK: - RainViewer (weather radar + IR satellite tiles, free, no key)

struct RainViewerFrames {
    struct Frame: Identifiable {
        let time: Date
        let path: String
        var id: String { path }
    }
    let host: String
    let radarPast: [Frame]
    let radarNowcast: [Frame]
    let satellite: [Frame]

    var allRadar: [Frame] { radarPast + radarNowcast }

    func radarTileTemplate(for frame: Frame) -> String {
        "\(host)\(frame.path)/256/{z}/{x}/{y}/2/1_1.png"
    }

    func satelliteTileTemplate(for frame: Frame) -> String {
        "\(host)\(frame.path)/256/{z}/{x}/{y}/0/0_0.png"
    }

    static func closest(_ frames: [Frame], to date: Date) -> Frame? {
        frames.min { abs($0.time.timeIntervalSince(date)) < abs($1.time.timeIntervalSince(date)) }
    }
}

struct RainViewerClient {
    static let shared = RainViewerClient()

    func frames() async throws -> RainViewerFrames {
        struct APIFrame: Decodable { let time: Double; let path: String }
        struct Radar: Decodable { let past: [APIFrame]?; let nowcast: [APIFrame]? }
        struct Satellite: Decodable { let infrared: [APIFrame]? }
        struct Response: Decodable {
            let host: String
            let radar: Radar?
            let satellite: Satellite?
        }

        let url = URL(string: "https://api.rainviewer.com/public/weather-maps.json")!
        let (data, _) = try await URLSession.shared.data(from: url)
        let response = try JSONDecoder().decode(Response.self, from: data)

        func map(_ frames: [APIFrame]?) -> [RainViewerFrames.Frame] {
            (frames ?? []).map { .init(time: Date(timeIntervalSince1970: $0.time), path: $0.path) }
        }
        return RainViewerFrames(
            host: response.host,
            radarPast: map(response.radar?.past),
            radarNowcast: map(response.radar?.nowcast),
            satellite: map(response.satellite?.infrared)
        )
    }
}

// MARK: - NHC tropical storms (hurricane tracker)

struct HurricaneService {
    static let shared = HurricaneService()

    func activeStorms() async throws -> [TropicalStorm] {
        struct APIStorm: Decodable {
            let id: String?
            let binNumber: String?
            let name: String?
            let classification: String?
            let intensity: String?
            let pressure: String?
            let latitudeNumeric: Double?
            let longitudeNumeric: Double?
            let movementDir: Double?
            let movementSpeed: Double?
            let lastUpdate: String?
        }
        struct Response: Decodable { let activeStorms: [APIStorm]? }

        let url = URL(string: "https://www.nhc.noaa.gov/CurrentStorms.json")!
        var request = URLRequest(url: url)
        request.setValue("WindFlow iOS", forHTTPHeaderField: "User-Agent")
        let (data, _) = try await URLSession.shared.data(for: request)
        let response = try JSONDecoder().decode(Response.self, from: data)

        return (response.activeStorms ?? []).compactMap { storm in
            guard let lat = storm.latitudeNumeric, let lon = storm.longitudeNumeric else { return nil }
            return TropicalStorm(
                id: storm.id ?? storm.binNumber ?? UUID().uuidString,
                name: storm.name ?? "Unnamed",
                classification: storm.classification ?? "",
                intensityKt: storm.intensity.flatMap(Double.init),
                pressureMb: storm.pressure.flatMap(Double.init),
                latitude: lat,
                longitude: lon,
                movementDir: storm.movementDir,
                movementSpeedKt: storm.movementSpeed,
                lastUpdate: storm.lastUpdate
            )
        }
    }
}

// MARK: - NWS weather alerts (US coverage)

struct AlertsService {
    static let shared = AlertsService()

    func alerts(for coordinate: CLLocationCoordinate2D) async throws -> [WeatherWarning] {
        struct Properties: Decodable {
            let id: String?
            let event: String?
            let severity: String?
            let headline: String?
            let description: String?
            let areaDesc: String?
            let effective: String?
            let expires: String?
        }
        struct Feature: Decodable { let properties: Properties }
        struct Response: Decodable { let features: [Feature]? }

        var components = URLComponents(string: "https://api.weather.gov/alerts/active")!
        components.queryItems = [
            .init(name: "point", value: String(format: "%.4f,%.4f", coordinate.latitude, coordinate.longitude)),
        ]
        var request = URLRequest(url: components.url!)
        request.setValue("(WindFlow iOS, contact: app@windflow.example)", forHTTPHeaderField: "User-Agent")
        request.setValue("application/geo+json", forHTTPHeaderField: "Accept")

        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            return []  // outside NWS coverage (non-US) or service hiccup
        }
        let decoded = try JSONDecoder().decode(Response.self, from: data)
        let iso = ISO8601DateFormatter()
        return (decoded.features ?? []).compactMap { feature in
            let p = feature.properties
            return WeatherWarning(
                id: p.id ?? UUID().uuidString,
                event: p.event ?? "Alert",
                severity: p.severity ?? "Unknown",
                headline: p.headline ?? "",
                description: p.description ?? "",
                areaDesc: p.areaDesc ?? "",
                effective: p.effective.flatMap { iso.date(from: $0) },
                expires: p.expires.flatMap { iso.date(from: $0) }
            )
        }
        .sorted { $0.severityRank > $1.severityRank }
    }
}

// MARK: - Windy Webcams API (requires a free API key entered in Settings)

struct WebcamService {
    static let shared = WebcamService()

    func webcams(near coordinate: CLLocationCoordinate2D, radiusKm: Int = 100, apiKey: String) async throws -> [Webcam] {
        guard !apiKey.isEmpty else { return [] }
        struct Response: Decodable { let webcams: [Webcam]? }
        var components = URLComponents(string: "https://api.windy.com/webcams/api/v3/webcams")!
        components.queryItems = [
            .init(name: "nearby", value: String(format: "%.4f,%.4f,%d", coordinate.latitude, coordinate.longitude, radiusKm)),
            .init(name: "include", value: "images,location"),
            .init(name: "limit", value: "30"),
        ]
        var request = URLRequest(url: components.url!)
        request.setValue(apiKey, forHTTPHeaderField: "x-windy-api-key")
        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            throw OpenMeteoError.httpError(http.statusCode)
        }
        return try JSONDecoder().decode(Response.self, from: data).webcams ?? []
    }
}

// MARK: - PEGELONLINE (WSV) — official German live water-level gauges, open data

struct GaugeReading {
    let stationName: String
    let valueCm: Double          // above gauge datum (PNP)
    let timestamp: Date?
    let distanceKm: Double
    let latitude: Double
    let longitude: Double
}

struct PegelOnlineService {
    static let shared = PegelOnlineService()

    /// Nearest water-level gauge with a current measurement, within `radiusKm`.
    func nearestReading(to coordinate: CLLocationCoordinate2D, radiusKm: Double = 60) async throws -> GaugeReading? {
        struct Station: Decodable {
            let shortname: String?
            let longname: String?
            let latitude: Double?
            let longitude: Double?
            let timeseries: [Series]?

            struct Series: Decodable {
                let shortname: String?
                let unit: String?
                let currentMeasurement: Measurement?
                struct Measurement: Decodable {
                    let timestamp: String?
                    let value: Double?
                }
            }
        }

        var components = URLComponents(string: "https://www.pegelonline.wsv.de/webservices/rest-api/v2/stations.json")!
        components.queryItems = [
            .init(name: "latitude", value: String(format: "%.4f", coordinate.latitude)),
            .init(name: "longitude", value: String(format: "%.4f", coordinate.longitude)),
            .init(name: "radius", value: String(Int(radiusKm))),
            .init(name: "includeTimeseries", value: "true"),
            .init(name: "includeCurrentMeasurement", value: "true"),
            .init(name: "timeseries", value: "W"),
        ]
        let (data, response) = try await URLSession.shared.data(from: components.url!)
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            return nil   // outside Germany / service hiccup — feature degrades gracefully
        }
        let stations = try JSONDecoder().decode([Station].self, from: data)
        let here = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        let iso = ISO8601DateFormatter()

        let candidates: [GaugeReading] = stations.compactMap { station in
            guard let lat = station.latitude, let lon = station.longitude,
                  let series = station.timeseries?.first(where: { $0.shortname == "W" }),
                  let value = series.currentMeasurement?.value else { return nil }
            let distance = here.distance(from: CLLocation(latitude: lat, longitude: lon)) / 1000
            return GaugeReading(
                stationName: (station.longname ?? station.shortname ?? "Gauge").capitalized,
                valueCm: value,
                timestamp: series.currentMeasurement?.timestamp.flatMap { iso.date(from: $0) },
                distanceKm: distance,
                latitude: lat,
                longitude: lon
            )
        }
        return candidates.min { $0.distanceKm < $1.distanceKm }
    }
}

// MARK: - Device location

final class LocationService: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published var lastLocation: CLLocation?
    @Published var authorized = false

    private let manager = CLLocationManager()

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyKilometer
    }

    func requestLocation() {
        switch manager.authorizationStatus {
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        case .authorizedWhenInUse, .authorizedAlways:
            manager.requestLocation()
        default:
            break
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        authorized = status == .authorizedWhenInUse || status == .authorizedAlways
        if authorized { manager.requestLocation() }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        lastLocation = locations.last
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        // Non-fatal: the map simply stays where it is.
    }
}
