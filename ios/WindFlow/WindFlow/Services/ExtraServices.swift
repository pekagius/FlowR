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

// MARK: - Weather alerts (US NWS + German DWD via Bright Sky)

struct AlertsService {
    static let shared = AlertsService()

    /// Combined severe-weather warnings: NWS covers the US, Bright Sky (DWD)
    /// covers Germany. Both are free, keyless, official-data APIs.
    func alerts(for coordinate: CLLocationCoordinate2D) async throws -> [WeatherWarning] {
        async let us = nwsAlerts(for: coordinate)
        async let de = BrightSkyService.shared.alerts(for: coordinate)
        let combined = ((try? await us) ?? []) + ((try? await de) ?? [])
        return combined.sorted { $0.severityRank > $1.severityRank }
    }

    private func nwsAlerts(for coordinate: CLLocationCoordinate2D) async throws -> [WeatherWarning] {
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

// MARK: - Bright Sky (DWD open data: German warnings + station observations)

/// Latest measured conditions from the nearest DWD weather station.
struct ObservedWeather {
    let stationName: String
    let distanceKm: Double
    let timestamp: Date?
    let temperature: Double?       // °C
    let windSpeedMS: Double?       // m/s
    let gustMS: Double?
    let windDirection: Double?
    let pressureHPa: Double?
    let humidity: Double?
    let condition: String?
}

struct BrightSkyService {
    static let shared = BrightSkyService()

    private var wantsGerman: Bool {
        Locale.current.language.languageCode?.identifier == "de"
    }

    func alerts(for coordinate: CLLocationCoordinate2D) async throws -> [WeatherWarning] {
        struct Alert: Decodable {
            let id: Int?
            let severity: String?
            let onset: String?
            let expires: String?
            let event_en: String?
            let event_de: String?
            let headline_en: String?
            let headline_de: String?
            let description_en: String?
            let description_de: String?
        }
        struct Response: Decodable { let alerts: [Alert]? }

        var components = URLComponents(string: "https://api.brightsky.dev/alerts")!
        components.queryItems = [
            .init(name: "lat", value: String(format: "%.4f", coordinate.latitude)),
            .init(name: "lon", value: String(format: "%.4f", coordinate.longitude)),
        ]
        let (data, response) = try await URLSession.shared.data(from: components.url!)
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            return []   // outside DWD coverage
        }
        let decoded = try JSONDecoder().decode(Response.self, from: data)
        let iso = ISO8601DateFormatter()
        let german = wantsGerman
        return (decoded.alerts ?? []).map { alert in
            WeatherWarning(
                id: "dwd-\(alert.id ?? Int.random(in: 0..<1_000_000))",
                event: (german ? alert.event_de : alert.event_en) ?? alert.event_en ?? "Warning",
                severity: (alert.severity ?? "unknown").capitalized,
                headline: (german ? alert.headline_de : alert.headline_en) ?? "",
                description: (german ? alert.description_de : alert.description_en) ?? "",
                areaDesc: "DWD warning area",
                effective: alert.onset.flatMap { iso.date(from: $0) },
                expires: alert.expires.flatMap { iso.date(from: $0) }
            )
        }
    }

    func currentObservation(for coordinate: CLLocationCoordinate2D) async throws -> ObservedWeather? {
        struct Weather: Decodable {
            let timestamp: String?
            let temperature: Double?
            let wind_speed_10: Double?      // km/h (DWD units)
            let wind_gust_speed_10: Double?
            let wind_direction_10: Double?
            let pressure_msl: Double?
            let relative_humidity: Double?
            let condition: String?
        }
        struct Source: Decodable {
            let station_name: String?
            let distance: Double?           // meters
        }
        struct Response: Decodable {
            let weather: Weather?
            let sources: [Source]?
        }

        var components = URLComponents(string: "https://api.brightsky.dev/current_weather")!
        components.queryItems = [
            .init(name: "lat", value: String(format: "%.4f", coordinate.latitude)),
            .init(name: "lon", value: String(format: "%.4f", coordinate.longitude)),
        ]
        let (data, response) = try await URLSession.shared.data(from: components.url!)
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            return nil   // no DWD station in range
        }
        let decoded = try JSONDecoder().decode(Response.self, from: data)
        guard let weather = decoded.weather else { return nil }
        let source = decoded.sources?.first
        let iso = ISO8601DateFormatter()
        return ObservedWeather(
            stationName: (source?.station_name ?? "DWD station").capitalized,
            distanceKm: (source?.distance ?? 0) / 1000,
            timestamp: weather.timestamp.flatMap { iso.date(from: $0) },
            temperature: weather.temperature,
            windSpeedMS: weather.wind_speed_10.map { $0 / 3.6 },
            gustMS: weather.wind_gust_speed_10.map { $0 / 3.6 },
            windDirection: weather.wind_direction_10,
            pressureHPa: weather.pressure_msl,
            humidity: weather.relative_humidity,
            condition: weather.condition
        )
    }
}

// MARK: - Reverse geocoding for tapped map points (BigDataCloud, free, keyless)

struct ReverseGeocodeService {
    static let shared = ReverseGeocodeService()

    func name(for coordinate: CLLocationCoordinate2D) async -> (name: String, subtitle: String)? {
        struct Response: Decodable {
            let city: String?
            let locality: String?
            let principalSubdivision: String?
            let countryName: String?
        }
        var components = URLComponents(string: "https://api.bigdatacloud.net/data/reverse-geocode-client")!
        components.queryItems = [
            .init(name: "latitude", value: String(format: "%.4f", coordinate.latitude)),
            .init(name: "longitude", value: String(format: "%.4f", coordinate.longitude)),
            .init(name: "localityLanguage", value: Locale.current.language.languageCode?.identifier ?? "en"),
        ]
        guard let (data, response) = try? await URLSession.shared.data(from: components.url!),
              let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode),
              let decoded = try? JSONDecoder().decode(Response.self, from: data) else { return nil }
        let name = [decoded.city, decoded.locality].compactMap { $0 }.first { !$0.isEmpty }
        let subtitle = [decoded.principalSubdivision, decoded.countryName]
            .compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: ", ")
        guard let name, !name.isEmpty else { return nil }
        return (name, subtitle)
    }
}

// MARK: - Aviation weather: METAR / TAF (NOAA aviationweather.gov, free, keyless)

/// Decodes numbers that the AWC API sometimes returns as strings ("VRB", "10+").
struct FlexibleDouble: Decodable {
    let value: Double?
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let d = try? container.decode(Double.self) {
            value = d
        } else if let s = try? container.decode(String.self) {
            value = Double(s.filter { "0123456789.-".contains($0) })
        } else {
            value = nil
        }
    }
}

struct MetarReport: Identifiable, Decodable {
    let icaoId: String
    let name: String?
    let reportTime: String?
    let temp: FlexibleDouble?
    let dewp: FlexibleDouble?
    let wdir: FlexibleDouble?
    let wspd: FlexibleDouble?      // knots
    let visib: FlexibleDouble?     // statute miles
    let altim: FlexibleDouble?     // hPa
    let rawOb: String?
    let lat: Double?
    let lon: Double?
    let fltCat: String?            // VFR / MVFR / IFR / LIFR

    var id: String { icaoId }
    var rawTAF: String?

    enum CodingKeys: String, CodingKey {
        case icaoId, name, reportTime, temp, dewp, wdir, wspd, visib, altim, rawOb, lat, lon, fltCat
    }
}

struct AviationService {
    static let shared = AviationService()

    func metars(around coordinate: CLLocationCoordinate2D) async throws -> [MetarReport] {
        let d = 1.6
        let bbox = String(format: "%.2f,%.2f,%.2f,%.2f",
                          coordinate.latitude - d, coordinate.longitude - d,
                          coordinate.latitude + d, coordinate.longitude + d)
        var components = URLComponents(string: "https://aviationweather.gov/api/data/metar")!
        components.queryItems = [
            .init(name: "bbox", value: bbox),
            .init(name: "format", value: "json"),
        ]
        let (data, response) = try await URLSession.shared.data(from: components.url!)
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            throw OpenMeteoError.httpError(http.statusCode)
        }
        var reports = try JSONDecoder().decode([MetarReport].self, from: data)

        // Sort by distance and keep the closest few.
        let here = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        reports.sort { a, b in
            distance(from: here, to: a) < distance(from: here, to: b)
        }
        reports = Array(reports.prefix(6))

        // Attach TAFs in one batch request.
        if !reports.isEmpty {
            let tafs = (try? await tafsByStation(ids: reports.map(\.icaoId))) ?? [:]
            for i in reports.indices {
                reports[i].rawTAF = tafs[reports[i].icaoId]
            }
        }
        return reports
    }

    private func distance(from here: CLLocation, to report: MetarReport) -> Double {
        guard let lat = report.lat, let lon = report.lon else { return .greatestFiniteMagnitude }
        return here.distance(from: CLLocation(latitude: lat, longitude: lon))
    }

    private func tafsByStation(ids: [String]) async throws -> [String: String] {
        struct TAF: Decodable {
            let icaoId: String?
            let rawTAF: String?
        }
        var components = URLComponents(string: "https://aviationweather.gov/api/data/taf")!
        components.queryItems = [
            .init(name: "ids", value: ids.joined(separator: ",")),
            .init(name: "format", value: "json"),
        ]
        let (data, _) = try await URLSession.shared.data(from: components.url!)
        let tafs = (try? JSONDecoder().decode([TAF].self, from: data)) ?? []
        var result: [String: String] = [:]
        for taf in tafs {
            if let id = taf.icaoId, let raw = taf.rawTAF { result[id] = raw }
        }
        return result
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
    let waterTempC: Double?      // measured water temperature, if the gauge has a WT sensor
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
            let waterTemp = station.timeseries?
                .first(where: { $0.shortname == "WT" })?
                .currentMeasurement?.value
            return GaugeReading(
                stationName: (station.longname ?? station.shortname ?? "Gauge").capitalized,
                valueCm: value,
                timestamp: series.currentMeasurement?.timestamp.flatMap { iso.date(from: $0) },
                distanceKm: distance,
                latitude: lat,
                longitude: lon,
                waterTempC: waterTemp
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
