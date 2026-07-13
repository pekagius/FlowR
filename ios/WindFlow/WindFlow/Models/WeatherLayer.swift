import Foundation
import SwiftUI

// MARK: - Forecast models (like Windy's model picker)

enum ForecastModel: String, CaseIterable, Codable, Identifiable {
    case bestMatch = "best_match"
    case ecmwf = "ecmwf_ifs025"
    case gfs = "gfs_seamless"
    case icon = "icon_seamless"
    case iconEU = "icon_eu"
    case iconD2 = "icon_d2"
    case gem = "gem_seamless"
    case meteoFrance = "meteofrance_seamless"
    case ukmo = "ukmo_seamless"
    case jma = "jma_seamless"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .bestMatch: return "Best match"
        case .ecmwf: return "ECMWF"
        case .gfs: return "GFS"
        case .icon: return "ICON"
        case .iconEU: return "ICON-EU"
        case .iconD2: return "ICON-D2"
        case .gem: return "GEM"
        case .meteoFrance: return "AROME/ARPEGE"
        case .ukmo: return "UKMO"
        case .jma: return "JMA"
        }
    }

    var detail: String {
        switch self {
        case .bestMatch: return "Best model per region"
        case .ecmwf: return "Global · 25 km · 6 h updates"
        case .gfs: return "Global · 13 km · hourly"
        case .icon: return "DWD · global + nests"
        case .iconEU: return "DWD · Europe · 7 km"
        case .iconD2: return "DWD · Central Europe · 2 km"
        case .gem: return "Canada · global 15 km"
        case .meteoFrance: return "Météo-France · 1–25 km"
        case .ukmo: return "UK Met Office · 2–10 km"
        case .jma: return "Japan · 5–55 km"
        }
    }

    /// A short list used in the model comparison screen.
    static var comparable: [ForecastModel] { [.ecmwf, .gfs, .icon, .gem, .meteoFrance, .ukmo] }
}

// MARK: - Altitude levels (surface → stratosphere, like Windy's altitude slider)

enum AltitudeLevel: String, CaseIterable, Codable, Identifiable {
    case surface
    case h950, h925, h900, h850, h800, h700, h600, h500, h400, h300, h250, h200

    var id: String { rawValue }

    var hPa: Int? {
        switch self {
        case .surface: return nil
        case .h950: return 950
        case .h925: return 925
        case .h900: return 900
        case .h850: return 850
        case .h800: return 800
        case .h700: return 700
        case .h600: return 600
        case .h500: return 500
        case .h400: return 400
        case .h300: return 300
        case .h250: return 250
        case .h200: return 200
        }
    }

    /// Approximate geometric altitude, used for display like Windy (m / FL).
    var approxMeters: Int {
        switch self {
        case .surface: return 0
        case .h950: return 600
        case .h925: return 800
        case .h900: return 1000
        case .h850: return 1500
        case .h800: return 2000
        case .h700: return 3000
        case .h600: return 4200
        case .h500: return 5600
        case .h400: return 7200
        case .h300: return 9200
        case .h250: return 10400
        case .h200: return 11800
        }
    }

    var label: String {
        guard let hPa else { return "Surface" }
        let fl = Int((Double(approxMeters) * 3.28084 / 100).rounded())
        return "\(approxMeters) m · FL\(String(format: "%03d", fl)) · \(hPa) hPa"
    }

    var shortLabel: String {
        guard hPa != nil else { return "SFC" }
        return approxMeters >= 1000
            ? String(format: "%.1f km", Double(approxMeters) / 1000)
            : "\(approxMeters) m"
    }

    /// Suffix used to build Open-Meteo variable names, e.g. "850hPa".
    var variableSuffix: String? { hPa.map { "\($0)hPa" } }
}

// MARK: - Layer catalogue (Windy's overlay list)

enum LayerCategory: String, CaseIterable, Identifiable {
    case wind = "Wind"
    case temperature = "Temperature"
    case rain = "Rain & Snow"
    case clouds = "Clouds & Sky"
    case pressure = "Pressure & Thermo"
    case sea = "Waves & Sea"
    case airQuality = "Air Quality"
    case radar = "Radar & Satellite"
    var id: String { rawValue }
}

enum UnitKind {
    case windSpeed, temperature, pressure, precipitation, percent
    case heightMeters, heightCentimeters, waveHeight, microgram, index, jkg, wm2, kilometers, speedKn
    case none
}

enum LayerSource {
    case forecast      // Open-Meteo forecast API
    case marine        // Open-Meteo marine API
    case airQuality    // Open-Meteo air quality API
    case rasterTiles   // RainViewer tile server (radar / satellite)
    case computed      // derived client-side (e.g. rain accumulation)
}

enum WeatherLayer: String, CaseIterable, Codable, Identifiable {
    // Wind
    case wind, gust, windAccumulation
    // Temperature
    case temperature, feelsLike, dewPoint, humidity
    // Rain & snow
    case rain, rainAccumulation, snowfall, snowDepth, freezingLevel
    // Clouds & sky
    case clouds, cloudsLow, cloudsMid, cloudsHigh, visibility, uvIndex, solarRadiation
    // Pressure & thermodynamics
    case pressure, cape
    // Sea
    case waves, windWaves, swell1, swell2, currents, seaTemperature, seaLevel
    // Air quality
    case pm25, pm10, no2, ozone, so2, co, dust, aod, usAQI, grassPollen, birchPollen
    // Raster
    case radar, satellite, satelliteVisible

    var id: String { rawValue }

    var title: String {
        switch self {
        case .wind: return "Wind"
        case .gust: return "Wind gusts"
        case .windAccumulation: return "Wind at altitude"
        case .temperature: return "Temperature"
        case .feelsLike: return "Feels like"
        case .dewPoint: return "Dew point"
        case .humidity: return "Humidity"
        case .rain: return "Rain, thunder"
        case .rainAccumulation: return "Rain accumulation"
        case .snowfall: return "New snow"
        case .snowDepth: return "Snow depth"
        case .freezingLevel: return "Freezing altitude"
        case .clouds: return "Clouds"
        case .cloudsLow: return "Low clouds"
        case .cloudsMid: return "Medium clouds"
        case .cloudsHigh: return "High clouds"
        case .visibility: return "Visibility"
        case .uvIndex: return "UV index"
        case .solarRadiation: return "Solar radiation"
        case .pressure: return "Pressure"
        case .cape: return "CAPE index"
        case .waves: return "Waves"
        case .windWaves: return "Wind waves"
        case .swell1: return "Swell"
        case .swell2: return "Secondary swell"
        case .currents: return "Currents"
        case .seaTemperature: return "Sea temperature"
        case .seaLevel: return "Sea level (tide)"
        case .pm25: return "PM2.5"
        case .pm10: return "PM10"
        case .no2: return "NO₂"
        case .ozone: return "Ozone O₃"
        case .so2: return "SO₂"
        case .co: return "CO"
        case .dust: return "Dust mass"
        case .aod: return "Aerosol optical depth"
        case .usAQI: return "Air quality index"
        case .grassPollen: return "Grass pollen"
        case .birchPollen: return "Birch pollen"
        case .radar: return "Weather radar"
        case .satellite: return "Satellite (IR)"
        case .satelliteVisible: return "Satellite (visible)"
        }
    }

    var systemImage: String {
        switch self {
        case .wind, .windAccumulation: return "wind"
        case .gust: return "wind.circle"
        case .temperature, .feelsLike: return "thermometer.medium"
        case .dewPoint: return "drop.degreesign"
        case .humidity: return "humidity"
        case .rain: return "cloud.rain"
        case .rainAccumulation: return "cloud.heavyrain"
        case .snowfall, .snowDepth: return "snowflake"
        case .freezingLevel: return "thermometer.snowflake"
        case .clouds, .cloudsLow, .cloudsMid, .cloudsHigh: return "cloud"
        case .visibility: return "eye"
        case .uvIndex: return "sun.max"
        case .solarRadiation: return "sun.haze"
        case .pressure: return "gauge.with.needle"
        case .cape: return "bolt.fill"
        case .waves, .windWaves, .swell1, .swell2: return "water.waves"
        case .currents: return "arrow.trianglehead.swap"
        case .seaTemperature: return "thermometer.and.liquid.waves"
        case .seaLevel: return "arrow.up.and.down.circle"
        case .pm25, .pm10, .dust, .aod: return "aqi.medium"
        case .no2, .ozone, .so2, .co: return "carbon.monoxide.cloud"
        case .usAQI: return "leaf"
        case .grassPollen, .birchPollen: return "allergens"
        case .radar: return "dot.radiowaves.left.and.right"
        case .satellite: return "globe.europe.africa"
        case .satelliteVisible: return "globe.americas"
        }
    }

    var category: LayerCategory {
        switch self {
        case .wind, .gust, .windAccumulation: return .wind
        case .temperature, .feelsLike, .dewPoint, .humidity: return .temperature
        case .rain, .rainAccumulation, .snowfall, .snowDepth, .freezingLevel: return .rain
        case .clouds, .cloudsLow, .cloudsMid, .cloudsHigh, .visibility, .uvIndex, .solarRadiation: return .clouds
        case .pressure, .cape: return .pressure
        case .waves, .windWaves, .swell1, .swell2, .currents, .seaTemperature, .seaLevel: return .sea
        case .pm25, .pm10, .no2, .ozone, .so2, .co, .dust, .aod, .usAQI, .grassPollen, .birchPollen: return .airQuality
        case .radar, .satellite, .satelliteVisible: return .radar
        }
    }

    var source: LayerSource {
        switch self {
        case .waves, .windWaves, .swell1, .swell2, .currents, .seaTemperature, .seaLevel: return .marine
        case .pm25, .pm10, .no2, .ozone, .so2, .co, .dust, .aod, .usAQI, .grassPollen, .birchPollen: return .airQuality
        case .radar, .satellite, .satelliteVisible: return .rasterTiles
        case .rainAccumulation: return .computed
        default: return .forecast
        }
    }

    var unitKind: UnitKind {
        switch self {
        case .wind, .gust, .windAccumulation: return .windSpeed
        case .temperature, .feelsLike, .dewPoint, .seaTemperature: return .temperature
        case .humidity, .clouds, .cloudsLow, .cloudsMid, .cloudsHigh: return .percent
        case .rain, .rainAccumulation: return .precipitation
        case .snowfall: return .heightCentimeters
        case .snowDepth: return .heightCentimeters
        case .freezingLevel: return .heightMeters
        case .visibility: return .kilometers
        case .uvIndex: return .index
        case .solarRadiation: return .wm2
        case .pressure: return .pressure
        case .cape: return .jkg
        case .waves, .windWaves, .swell1, .swell2, .seaLevel: return .waveHeight
        case .currents: return .speedKn
        case .pm25, .pm10, .no2, .ozone, .so2, .co, .dust: return .microgram
        case .aod: return .none
        case .usAQI: return .index
        case .grassPollen, .birchPollen: return .index
        case .radar, .satellite, .satelliteVisible: return .none
        }
    }

    /// True when the layer supports the altitude slider (pressure levels).
    var supportsAltitude: Bool {
        switch self {
        case .wind, .windAccumulation, .temperature, .humidity: return true
        default: return false
        }
    }

    /// True when the map should show a directional vector field (particles use it too).
    var isVectorField: Bool {
        switch self {
        case .wind, .gust, .windAccumulation, .currents, .waves, .windWaves, .swell1, .swell2: return true
        default: return false
        }
    }

    /// Open-Meteo hourly variable for the scalar heatmap. `altitude` only applies
    /// when `supportsAltitude` is true.
    func scalarVariable(altitude: AltitudeLevel) -> String? {
        let suffix = supportsAltitude ? altitude.variableSuffix : nil
        switch self {
        case .wind, .windAccumulation: return suffix.map { "wind_speed_\($0)" } ?? "wind_speed_10m"
        case .gust: return "wind_gusts_10m"
        case .temperature: return suffix.map { "temperature_\($0)" } ?? "temperature_2m"
        case .feelsLike: return "apparent_temperature"
        case .dewPoint: return "dew_point_2m"
        case .humidity: return suffix.map { "relative_humidity_\($0)" } ?? "relative_humidity_2m"
        case .rain, .rainAccumulation: return "precipitation"
        case .snowfall: return "snowfall"
        case .snowDepth: return "snow_depth"
        case .freezingLevel: return "freezing_level_height"
        case .clouds: return "cloud_cover"
        case .cloudsLow: return "cloud_cover_low"
        case .cloudsMid: return "cloud_cover_mid"
        case .cloudsHigh: return "cloud_cover_high"
        case .visibility: return "visibility"
        case .uvIndex: return "uv_index"
        case .solarRadiation: return "shortwave_radiation"
        case .pressure: return "pressure_msl"
        case .cape: return "cape"
        case .waves: return "wave_height"
        case .windWaves: return "wind_wave_height"
        case .swell1: return "swell_wave_height"
        case .swell2: return "secondary_swell_wave_height"
        case .currents: return "ocean_current_velocity"
        case .seaTemperature: return "sea_surface_temperature"
        case .seaLevel: return "sea_level_height_msl"
        case .pm25: return "pm2_5"
        case .pm10: return "pm10"
        case .no2: return "nitrogen_dioxide"
        case .ozone: return "ozone"
        case .so2: return "sulphur_dioxide"
        case .co: return "carbon_monoxide"
        case .dust: return "dust"
        case .aod: return "aerosol_optical_depth"
        case .usAQI: return "us_aqi"
        case .grassPollen: return "grass_pollen"
        case .birchPollen: return "birch_pollen"
        case .radar, .satellite, .satelliteVisible: return nil
        }
    }

    /// Direction variable (meteorological degrees) for vector layers other than wind.
    func directionVariable(altitude: AltitudeLevel) -> String? {
        switch self {
        case .wind, .windAccumulation:
            return altitude.variableSuffix.map { "wind_direction_\($0)" } ?? "wind_direction_10m"
        case .gust: return "wind_direction_10m"
        case .waves: return "wave_direction"
        case .windWaves: return "wind_wave_direction"
        case .swell1: return "swell_wave_direction"
        case .swell2: return "secondary_swell_wave_direction"
        case .currents: return "ocean_current_direction"
        default: return nil
        }
    }

    /// A snapshot conversion of the raw API value to the SI unit the color
    /// scales expect (m/s, °C, hPa, mm, %, m, …).
    func toSI(_ raw: Double) -> Double {
        switch self {
        case .snowDepth: return raw * 100      // API: meters → cm
        case .currents: return raw / 3.6       // marine API returns km/h → m/s
        default: return raw
        }
    }

    var colorScale: ColorScale {
        switch self {
        case .wind, .windAccumulation: return .wind
        case .gust: return .gust
        case .temperature, .feelsLike, .dewPoint: return .temperature
        case .seaTemperature: return .seaTemperature
        case .humidity: return .humidity
        case .rain, .rainAccumulation: return .rain
        case .snowfall, .snowDepth: return .snow
        case .freezingLevel: return .freezingLevel
        case .clouds, .cloudsLow, .cloudsMid, .cloudsHigh: return .clouds
        case .visibility: return .visibility
        case .uvIndex: return .uv
        case .solarRadiation: return .solar
        case .pressure: return .pressure
        case .cape: return .cape
        case .waves, .windWaves, .swell1, .swell2: return .waves
        case .currents: return .currents
        case .seaLevel: return .seaLevel
        case .pm25, .pm10, .no2, .so2: return .pollutantFine
        case .ozone, .co, .dust: return .pollutantCoarse
        case .aod: return .aod
        case .usAQI: return .aqi
        case .grassPollen, .birchPollen: return .pollen
        case .radar, .satellite, .satelliteVisible: return .clouds
        }
    }

    static func layers(in category: LayerCategory) -> [WeatherLayer] {
        allCases.filter { $0.category == category && $0 != .windAccumulation }
    }
}
