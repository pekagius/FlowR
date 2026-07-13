import Foundation
import CoreLocation

// MARK: - Dynamic-key JSON decoding for Open-Meteo hourly/daily blocks

private struct AnyKey: CodingKey {
    var stringValue: String
    var intValue: Int? { nil }
    init?(stringValue: String) { self.stringValue = stringValue }
    init?(intValue: Int) { return nil }
}

/// Decodes an Open-Meteo "hourly"/"daily" object: a "time" array plus any
/// number of variable arrays (numbers or strings, possibly null).
struct OMTimeBlock: Decodable {
    let time: [Double]                 // unix seconds (we always request timeformat=unixtime)
    let numeric: [String: [Double?]]
    let textual: [String: [String?]]

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: AnyKey.self)
        var time: [Double] = []
        var numeric: [String: [Double?]] = [:]
        var textual: [String: [String?]] = [:]
        for key in container.allKeys {
            if key.stringValue == "time" {
                time = try container.decode([Double].self, forKey: key)
            } else if let values = try? container.decode([Double?].self, forKey: key) {
                numeric[key.stringValue] = values
            } else if let values = try? container.decode([String?].self, forKey: key) {
                textual[key.stringValue] = values
            }
        }
        self.time = time
        self.numeric = numeric
        self.textual = textual
    }

    var dates: [Date] { time.map { Date(timeIntervalSince1970: $0) } }
}

struct OMResponse: Decodable {
    let latitude: Double
    let longitude: Double
    let elevation: Double?
    let utc_offset_seconds: Int?
    let hourly: OMTimeBlock?
    let daily: OMTimeBlock?
}

enum OpenMeteoError: LocalizedError {
    case badURL
    case httpError(Int)
    case emptyResponse

    var errorDescription: String? {
        switch self {
        case .badURL: return "Invalid request URL."
        case .httpError(let code): return "Weather server returned HTTP \(code)."
        case .emptyResponse: return "The weather server returned no data."
        }
    }
}

// MARK: - Client

struct OpenMeteoClient {
    static let shared = OpenMeteoClient()

    private let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.requestCachePolicy = .returnCacheDataElseLoad
        config.urlCache = URLCache(memoryCapacity: 20_000_000, diskCapacity: 100_000_000)
        return URLSession(configuration: config)
    }()

    // MARK: Point forecast (surface + upper air, one model)

    func pointForecast(for place: Place, model: ForecastModel) async throws -> PointForecast {
        do {
            return try await pointForecast(for: place, model: model, includeUpperAir: true)
        } catch {
            // Some models don't provide pressure-level variables — retry surface-only.
            return try await pointForecast(for: place, model: model, includeUpperAir: false)
        }
    }

    private func pointForecast(for place: Place, model: ForecastModel, includeUpperAir: Bool) async throws -> PointForecast {
        let variables = PointVariables.surface + (includeUpperAir ? PointVariables.upperAir : [])
        var components = URLComponents(string: "https://api.open-meteo.com/v1/forecast")!
        components.queryItems = [
            .init(name: "latitude", value: String(place.latitude)),
            .init(name: "longitude", value: String(place.longitude)),
            .init(name: "hourly", value: variables.joined(separator: ",")),
            .init(name: "daily", value: "weather_code,temperature_2m_max,temperature_2m_min,precipitation_sum,wind_speed_10m_max,wind_gusts_10m_max,wind_direction_10m_dominant,sunrise,sunset,uv_index_max"),
            .init(name: "models", value: model.rawValue),
            .init(name: "wind_speed_unit", value: "ms"),
            .init(name: "timeformat", value: "unixtime"),
            .init(name: "timezone", value: "auto"),
            .init(name: "forecast_days", value: "10"),
        ]
        let response = try await fetchSingle(components)
        guard let hourlyBlock = response.hourly else { throw OpenMeteoError.emptyResponse }

        let hourly = HourlySeries(times: hourlyBlock.dates, values: hourlyBlock.numeric)
        let daily = Self.parseDaily(response.daily)

        return PointForecast(
            place: place,
            model: model,
            elevation: response.elevation,
            utcOffsetSeconds: response.utc_offset_seconds ?? 0,
            hourly: hourly,
            daily: daily
        )
    }

    private static func parseDaily(_ block: OMTimeBlock?) -> [DailySummary] {
        guard let block else { return [] }
        let dates = block.dates
        func num(_ name: String, _ i: Int) -> Double? {
            guard let arr = block.numeric[name], i < arr.count else { return nil }
            return arr[i]
        }
        return dates.indices.map { i in
            DailySummary(
                date: dates[i],
                weatherCode: Int(num("weather_code", i) ?? 3),
                tempMax: num("temperature_2m_max", i) ?? 0,
                tempMin: num("temperature_2m_min", i) ?? 0,
                precipSum: num("precipitation_sum", i) ?? 0,
                windMax: num("wind_speed_10m_max", i) ?? 0,
                gustMax: num("wind_gusts_10m_max", i) ?? 0,
                windDirection: num("wind_direction_10m_dominant", i) ?? 0,
                sunrise: num("sunrise", i).map { Date(timeIntervalSince1970: $0) },
                sunset: num("sunset", i).map { Date(timeIntervalSince1970: $0) },
                uvIndexMax: num("uv_index_max", i)
            )
        }
    }

    // MARK: Model comparison — same variables across several models

    /// Returns per-model hourly series for a small set of comparison variables.
    func compareModels(for place: Place, models: [ForecastModel]) async throws -> [ForecastModel: HourlySeries] {
        try await withThrowingTaskGroup(of: (ForecastModel, HourlySeries?).self) { group in
            for model in models {
                group.addTask {
                    var components = URLComponents(string: "https://api.open-meteo.com/v1/forecast")!
                    components.queryItems = [
                        .init(name: "latitude", value: String(place.latitude)),
                        .init(name: "longitude", value: String(place.longitude)),
                        .init(name: "hourly", value: "temperature_2m,precipitation,wind_speed_10m,wind_gusts_10m"),
                        .init(name: "models", value: model.rawValue),
                        .init(name: "wind_speed_unit", value: "ms"),
                        .init(name: "timeformat", value: "unixtime"),
                        .init(name: "timezone", value: "auto"),
                        .init(name: "forecast_days", value: "7"),
                    ]
                    guard let response = try? await self.fetchSingle(components),
                          let hourly = response.hourly else { return (model, nil) }
                    return (model, HourlySeries(times: hourly.dates, values: hourly.numeric))
                }
            }
            var result: [ForecastModel: HourlySeries] = [:]
            for try await (model, series) in group {
                if let series { result[model] = series }
            }
            return result
        }
    }

    // MARK: Marine + air quality point forecasts

    func marineForecast(for place: Place) async throws -> MarineForecast? {
        var components = URLComponents(string: "https://marine-api.open-meteo.com/v1/marine")!
        components.queryItems = [
            .init(name: "latitude", value: String(place.latitude)),
            .init(name: "longitude", value: String(place.longitude)),
            .init(name: "hourly", value: PointVariables.marine.joined(separator: ",")),
            .init(name: "timeformat", value: "unixtime"),
            .init(name: "timezone", value: "auto"),
            .init(name: "forecast_days", value: "7"),
        ]
        guard let response = try? await fetchSingle(components), let hourly = response.hourly else {
            return nil  // inland points have no marine data
        }
        let series = HourlySeries(times: hourly.dates, values: hourly.numeric)
        // If everything is null this is an inland point.
        let hasData = PointVariables.marine.contains { name in
            series.series(name).contains { $0 != nil }
        }
        return hasData ? MarineForecast(hourly: series) : nil
    }

    func airQualityForecast(for place: Place) async throws -> AirQualityForecast? {
        var components = URLComponents(string: "https://air-quality-api.open-meteo.com/v1/air-quality")!
        components.queryItems = [
            .init(name: "latitude", value: String(place.latitude)),
            .init(name: "longitude", value: String(place.longitude)),
            .init(name: "hourly", value: PointVariables.airQuality.joined(separator: ",")),
            .init(name: "timeformat", value: "unixtime"),
            .init(name: "timezone", value: "auto"),
            .init(name: "forecast_days", value: "5"),
        ]
        guard let response = try? await fetchSingle(components), let hourly = response.hourly else { return nil }
        return AirQualityForecast(hourly: HourlySeries(times: hourly.dates, values: hourly.numeric))
    }

    // MARK: Geocoding search

    struct GeocodingResult: Decodable {
        let id: Int
        let name: String
        let latitude: Double
        let longitude: Double
        let elevation: Double?
        let country: String?
        let admin1: String?

        var place: Place {
            Place(
                id: "geo-\(id)",
                name: name,
                subtitle: [admin1, country].compactMap { $0 }.joined(separator: ", "),
                latitude: latitude,
                longitude: longitude,
                elevation: elevation
            )
        }
    }

    func search(_ query: String) async throws -> [Place] {
        guard query.count >= 2 else { return [] }
        var components = URLComponents(string: "https://geocoding-api.open-meteo.com/v1/search")!
        components.queryItems = [
            .init(name: "name", value: query),
            .init(name: "count", value: "20"),
            .init(name: "language", value: Locale.current.language.languageCode?.identifier ?? "en"),
        ]
        struct SearchResponse: Decodable { let results: [GeocodingResult]? }
        let data = try await fetchData(components)
        let response = try JSONDecoder().decode(SearchResponse.self, from: data)
        return (response.results ?? []).map(\.place)
    }

    // MARK: Shared plumbing

    private func fetchSingle(_ components: URLComponents) async throws -> OMResponse {
        let data = try await fetchData(components)
        return try JSONDecoder().decode(OMResponse.self, from: data)
    }

    func fetchData(_ components: URLComponents) async throws -> Data {
        guard let url = components.url else { throw OpenMeteoError.badURL }
        let (data, response) = try await session.data(from: url)
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            throw OpenMeteoError.httpError(http.statusCode)
        }
        return data
    }
}
