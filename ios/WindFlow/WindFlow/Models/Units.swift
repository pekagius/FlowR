import Foundation
import SwiftUI

// MARK: - Unit definitions (all internal values are SI: m/s, °C, hPa, mm, m)

enum WindUnit: String, CaseIterable, Codable, Identifiable {
    case knots, ms, kmh, mph, beaufort
    var id: String { rawValue }

    var label: String {
        switch self {
        case .knots: return "kt"
        case .ms: return "m/s"
        case .kmh: return "km/h"
        case .mph: return "mph"
        case .beaufort: return "bft"
        }
    }

    func convert(fromMS value: Double) -> Double {
        switch self {
        case .knots: return value * 1.943844
        case .ms: return value
        case .kmh: return value * 3.6
        case .mph: return value * 2.236936
        case .beaufort:
            // Beaufort scale from m/s
            let thresholds: [Double] = [0.5, 1.5, 3.3, 5.5, 7.9, 10.7, 13.8, 17.1, 20.7, 24.4, 28.4, 32.6]
            for (i, t) in thresholds.enumerated() where value < t { return Double(i) }
            return 12
        }
    }

    func format(ms value: Double) -> String {
        let v = convert(fromMS: value)
        return self == .beaufort ? String(format: "%.0f", v) : String(format: "%.0f", v.rounded())
    }
}

enum TemperatureUnit: String, CaseIterable, Codable, Identifiable {
    case celsius, fahrenheit
    var id: String { rawValue }
    var label: String { self == .celsius ? "°C" : "°F" }

    func convert(fromCelsius value: Double) -> Double {
        self == .celsius ? value : value * 9 / 5 + 32
    }

    func format(celsius value: Double) -> String {
        String(format: "%.0f°", convert(fromCelsius: value))
    }
}

enum PressureUnit: String, CaseIterable, Codable, Identifiable {
    case hPa, inHg, mmHg
    var id: String { rawValue }
    var label: String { rawValue }

    func convert(fromHPa value: Double) -> Double {
        switch self {
        case .hPa: return value
        case .inHg: return value * 0.02953
        case .mmHg: return value * 0.750062
        }
    }

    func format(hPa value: Double) -> String {
        switch self {
        case .hPa: return String(format: "%.0f hPa", value)
        case .inHg: return String(format: "%.2f inHg", convert(fromHPa: value))
        case .mmHg: return String(format: "%.0f mmHg", convert(fromHPa: value))
        }
    }
}

enum PrecipUnit: String, CaseIterable, Codable, Identifiable {
    case millimeters, inches
    var id: String { rawValue }
    var label: String { self == .millimeters ? "mm" : "in" }

    func convert(fromMM value: Double) -> Double {
        self == .millimeters ? value : value / 25.4
    }

    func format(mm value: Double) -> String {
        self == .millimeters
            ? String(format: "%.1f mm", value)
            : String(format: "%.2f in", convert(fromMM: value))
    }
}

enum HeightUnit: String, CaseIterable, Codable, Identifiable {
    case meters, feet
    var id: String { rawValue }
    var label: String { self == .meters ? "m" : "ft" }

    func convert(fromMeters value: Double) -> Double {
        self == .meters ? value : value * 3.28084
    }

    func format(meters value: Double, decimals: Int = 0) -> String {
        String(format: "%.\(decimals)f %@", convert(fromMeters: value), label)
    }
}

enum Appearance: String, CaseIterable, Codable, Identifiable {
    case system, light, dark
    var id: String { rawValue }
    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}

enum BaseMapStyle: String, CaseIterable, Codable, Identifiable {
    case standard, muted, satellite, hybrid
    var id: String { rawValue }
    var label: String {
        switch self {
        case .standard: return "Standard"
        case .muted: return "Muted"
        case .satellite: return "Satellite"
        case .hybrid: return "Hybrid"
        }
    }
}

// MARK: - Settings store

final class Settings: ObservableObject {
    @Published var windUnit: WindUnit { didSet { save(windUnit, "windUnit") } }
    @Published var temperatureUnit: TemperatureUnit { didSet { save(temperatureUnit, "temperatureUnit") } }
    @Published var pressureUnit: PressureUnit { didSet { save(pressureUnit, "pressureUnit") } }
    @Published var precipUnit: PrecipUnit { didSet { save(precipUnit, "precipUnit") } }
    @Published var heightUnit: HeightUnit { didSet { save(heightUnit, "heightUnit") } }
    @Published var appearance: Appearance { didSet { save(appearance, "appearance") } }
    @Published var baseMap: BaseMapStyle { didSet { save(baseMap, "baseMap") } }
    @Published var defaultModel: ForecastModel { didSet { save(defaultModel, "defaultModel") } }
    @Published var particlesEnabled: Bool { didSet { UserDefaults.standard.set(particlesEnabled, forKey: "particlesEnabled") } }
    @Published var particleDensity: Double { didSet { UserDefaults.standard.set(particleDensity, forKey: "particleDensity") } }
    @Published var overlayOpacity: Double { didSet { UserDefaults.standard.set(overlayOpacity, forKey: "overlayOpacity") } }
    @Published var windyWebcamsAPIKey: String { didSet { UserDefaults.standard.set(windyWebcamsAPIKey, forKey: "windyWebcamsAPIKey") } }

    init() {
        windUnit = Self.load("windUnit") ?? .knots
        temperatureUnit = Self.load("temperatureUnit") ?? .celsius
        pressureUnit = Self.load("pressureUnit") ?? .hPa
        precipUnit = Self.load("precipUnit") ?? .millimeters
        heightUnit = Self.load("heightUnit") ?? .meters
        appearance = Self.load("appearance") ?? .system
        baseMap = Self.load("baseMap") ?? .muted
        defaultModel = Self.load("defaultModel") ?? .bestMatch
        particlesEnabled = UserDefaults.standard.object(forKey: "particlesEnabled") as? Bool ?? true
        particleDensity = UserDefaults.standard.object(forKey: "particleDensity") as? Double ?? 1.0
        overlayOpacity = UserDefaults.standard.object(forKey: "overlayOpacity") as? Double ?? 0.55
        windyWebcamsAPIKey = UserDefaults.standard.string(forKey: "windyWebcamsAPIKey") ?? ""
    }

    private func save<T: Codable>(_ value: T, _ key: String) {
        if let data = try? JSONEncoder().encode(value) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    private static func load<T: Codable>(_ key: String) -> T? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }

    /// Formats a raw SI value for a given layer according to the user's units.
    func format(value: Double, for layer: WeatherLayer) -> String {
        switch layer.unitKind {
        case .windSpeed: return "\(windUnit.format(ms: value)) \(windUnit.label)"
        case .temperature: return temperatureUnit.format(celsius: value)
        case .pressure: return pressureUnit.format(hPa: value)
        case .precipitation: return precipUnit.format(mm: value)
        case .percent: return String(format: "%.0f %%", value)
        case .heightMeters: return heightUnit.format(meters: value)
        case .heightCentimeters: return heightUnit == .meters ? String(format: "%.0f cm", value) : heightUnit.format(meters: value / 100, decimals: 1)
        case .waveHeight: return heightUnit == .meters ? String(format: "%.1f m", value) : heightUnit.format(meters: value, decimals: 0)
        case .microgram: return String(format: "%.0f µg/m³", value)
        case .index: return String(format: "%.0f", value)
        case .jkg: return String(format: "%.0f J/kg", value)
        case .wm2: return String(format: "%.0f W/m²", value)
        case .kilometers: return String(format: "%.0f km", value / 1000)
        case .speedKn: return "\(windUnit.format(ms: value)) \(windUnit.label)"
        case .none: return String(format: "%.1f", value)
        }
    }
}
