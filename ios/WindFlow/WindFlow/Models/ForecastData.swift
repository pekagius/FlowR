import Foundation

/// A generic hourly time series keyed by variable name, holding raw API values.
struct HourlySeries {
    let times: [Date]
    let values: [String: [Double?]]

    func series(_ variable: String) -> [Double?] {
        values[variable] ?? Array(repeating: nil, count: times.count)
    }

    func value(_ variable: String, at index: Int) -> Double? {
        guard let arr = values[variable], index >= 0, index < arr.count else { return nil }
        return arr[index]
    }

    /// Index of the time step closest to `date`.
    func index(closestTo date: Date) -> Int? {
        guard !times.isEmpty else { return nil }
        var best = 0
        var bestDist = abs(times[0].timeIntervalSince(date))
        for (i, t) in times.enumerated() {
            let d = abs(t.timeIntervalSince(date))
            if d < bestDist { best = i; bestDist = d }
        }
        return best
    }
}

/// Daily summary values, like Windy's 10-day strip.
struct DailySummary: Identifiable {
    let id = UUID()
    let date: Date
    let weatherCode: Int
    let tempMax: Double
    let tempMin: Double
    let precipSum: Double
    let windMax: Double        // m/s
    let gustMax: Double        // m/s
    let windDirection: Double  // degrees
    let sunrise: Date?
    let sunset: Date?
    let uvIndexMax: Double?
}

/// Complete point forecast bundle for the detail sheet.
struct PointForecast {
    let place: Place
    let model: ForecastModel
    let elevation: Double?
    let utcOffsetSeconds: Int
    let hourly: HourlySeries
    let daily: [DailySummary]

    var timeZone: TimeZone {
        TimeZone(secondsFromGMT: utcOffsetSeconds) ?? .current
    }
}

/// Marine forecast for coastal points.
struct MarineForecast {
    let hourly: HourlySeries
}

/// Air quality forecast.
struct AirQualityForecast {
    let hourly: HourlySeries
}

/// WMO weather interpretation codes → SF Symbol + text.
enum WeatherCode {
    static func symbol(_ code: Int, isDay: Bool = true) -> String {
        switch code {
        case 0: return isDay ? "sun.max.fill" : "moon.stars.fill"
        case 1, 2: return isDay ? "cloud.sun.fill" : "cloud.moon.fill"
        case 3: return "cloud.fill"
        case 45, 48: return "cloud.fog.fill"
        case 51, 53, 55, 56, 57: return "cloud.drizzle.fill"
        case 61, 63, 65, 66, 67: return "cloud.rain.fill"
        case 71, 73, 75, 77: return "cloud.snow.fill"
        case 80, 81, 82: return "cloud.heavyrain.fill"
        case 85, 86: return "cloud.sleet.fill"
        case 95, 96, 99: return "cloud.bolt.rain.fill"
        default: return "cloud.fill"
        }
    }

    static func text(_ code: Int) -> String {
        switch code {
        case 0: return "Clear sky"
        case 1: return "Mainly clear"
        case 2: return "Partly cloudy"
        case 3: return "Overcast"
        case 45, 48: return "Fog"
        case 51, 53, 55: return "Drizzle"
        case 56, 57: return "Freezing drizzle"
        case 61: return "Light rain"
        case 63: return "Rain"
        case 65: return "Heavy rain"
        case 66, 67: return "Freezing rain"
        case 71: return "Light snow"
        case 73: return "Snow"
        case 75: return "Heavy snow"
        case 77: return "Snow grains"
        case 80, 81: return "Rain showers"
        case 82: return "Violent showers"
        case 85, 86: return "Snow showers"
        case 95: return "Thunderstorm"
        case 96, 99: return "Thunderstorm w/ hail"
        default: return "—"
        }
    }
}

/// All hourly variables requested for the point forecast detail.
enum PointVariables {
    static let surface: [String] = [
        "temperature_2m", "apparent_temperature", "dew_point_2m", "relative_humidity_2m",
        "precipitation", "precipitation_probability", "rain", "showers", "snowfall",
        "weather_code", "cloud_cover", "cloud_cover_low", "cloud_cover_mid", "cloud_cover_high",
        "pressure_msl", "wind_speed_10m", "wind_direction_10m", "wind_gusts_10m",
        "cape", "visibility", "freezing_level_height", "uv_index", "is_day",
    ]

    static let pressureLevels: [Int] = [950, 925, 900, 850, 800, 700, 600, 500, 400, 300, 250, 200]

    static var upperAir: [String] {
        pressureLevels.flatMap { level in
            ["temperature_\(level)hPa", "relative_humidity_\(level)hPa",
             "wind_speed_\(level)hPa", "wind_direction_\(level)hPa",
             "geopotential_height_\(level)hPa"]
        }
    }

    static let marine: [String] = [
        "wave_height", "wave_direction", "wave_period",
        "wind_wave_height", "wind_wave_direction", "wind_wave_period",
        "swell_wave_height", "swell_wave_direction", "swell_wave_period",
        "sea_surface_temperature", "ocean_current_velocity", "ocean_current_direction",
        "sea_level_height_msl",
    ]

    static let airQuality: [String] = [
        "pm2_5", "pm10", "nitrogen_dioxide", "ozone", "sulphur_dioxide",
        "carbon_monoxide", "dust", "aerosol_optical_depth", "us_aqi", "european_aqi",
    ]
}
