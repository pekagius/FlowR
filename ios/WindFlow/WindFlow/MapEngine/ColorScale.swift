import Foundation
import SwiftUI
import UIKit

/// A Windy-style color ramp: value stops (in SI units) mapped to colors,
/// linearly interpolated in between.
struct ColorScale {
    struct Stop {
        let value: Double
        let r: Double, g: Double, b: Double
        init(_ value: Double, _ hex: UInt32) {
            self.value = value
            r = Double((hex >> 16) & 0xFF) / 255
            g = Double((hex >> 8) & 0xFF) / 255
            b = Double(hex & 0xFF) / 255
        }
    }

    let stops: [Stop]

    var minValue: Double { stops.first?.value ?? 0 }
    var maxValue: Double { stops.last?.value ?? 1 }

    /// Returns RGBA components (0–1) for a value.
    func components(for value: Double) -> (Double, Double, Double) {
        guard let first = stops.first, let last = stops.last else { return (0, 0, 0) }
        if value <= first.value { return (first.r, first.g, first.b) }
        if value >= last.value { return (last.r, last.g, last.b) }
        for i in 1..<stops.count {
            let hi = stops[i]
            if value <= hi.value {
                let lo = stops[i - 1]
                let t = (value - lo.value) / max(hi.value - lo.value, .ulpOfOne)
                return (lo.r + (hi.r - lo.r) * t,
                        lo.g + (hi.g - lo.g) * t,
                        lo.b + (hi.b - lo.b) * t)
            }
        }
        return (last.r, last.g, last.b)
    }

    func uiColor(for value: Double) -> UIColor {
        let (r, g, b) = components(for: value)
        return UIColor(red: r, green: g, blue: b, alpha: 1)
    }

    func color(for value: Double) -> Color {
        let (r, g, b) = components(for: value)
        return Color(red: r, green: g, blue: b)
    }

    /// A gradient for the legend bar.
    var gradient: LinearGradient {
        let colors = stride(from: 0.0, through: 1.0, by: 1.0 / 24).map { t in
            color(for: minValue + (maxValue - minValue) * t)
        }
        return LinearGradient(colors: colors, startPoint: .leading, endPoint: .trailing)
    }

    /// Evenly spaced representative tick values for the legend.
    var legendTicks: [Double] {
        let count = 5
        return (0..<count).map { minValue + (maxValue - minValue) * Double($0) / Double(count - 1) }
    }

    // MARK: - Palettes (inspired by Windy's ramps, values in SI units)

    static let wind = ColorScale(stops: [                 // m/s
        .init(0, 0x6271B7), .init(3, 0x3961A9), .init(6, 0x4A94A9),
        .init(9, 0x4D8D7B), .init(12, 0x53A553), .init(15, 0xB6BE62),
        .init(18, 0xC79F45), .init(24, 0x9F5232), .init(30, 0x8A3A66),
        .init(38, 0x6D1D80), .init(50, 0x4F0E52),
    ])

    static let gust = ColorScale(stops: [                 // m/s
        .init(0, 0x5A6BB0), .init(5, 0x3D7BA8), .init(10, 0x4C9C68),
        .init(15, 0xB0B24E), .init(20, 0xC7833F), .init(28, 0xA33F32),
        .init(36, 0x81275F), .init(46, 0x551663),
    ])

    static let temperature = ColorScale(stops: [          // °C
        .init(-40, 0x9A9EC6), .init(-30, 0x615EA9), .init(-20, 0x4B41A0),
        .init(-10, 0x3F62B0), .init(-5, 0x3C8BB8), .init(0, 0x39A8B0),
        .init(5, 0x40B08B), .init(10, 0x59B04D), .init(15, 0x9DBB3C),
        .init(20, 0xD9C63A), .init(25, 0xE0973C), .init(30, 0xD8543C),
        .init(35, 0xB5304C), .init(45, 0x7A1E4F),
    ])

    static let seaTemperature = ColorScale(stops: [       // °C
        .init(-2, 0x3E3E8F), .init(4, 0x3B6BAF), .init(10, 0x3A98B4),
        .init(16, 0x3FAF7E), .init(22, 0x9DBB3C), .init(27, 0xE0973C),
        .init(32, 0xC44040),
    ])

    static let humidity = ColorScale(stops: [             // %
        .init(0, 0xB88A47), .init(30, 0xB8B379), .init(50, 0x86AD84),
        .init(70, 0x53A0A8), .init(85, 0x4477C4), .init(100, 0x3D50C8),
    ])

    static let rain = ColorScale(stops: [                 // mm/h
        .init(0, 0x404040), .init(0.2, 0x3E63A0), .init(1, 0x3E8CC0),
        .init(2, 0x38A894), .init(5, 0x48B04B), .init(10, 0xC0C040),
        .init(20, 0xC08040), .init(35, 0xC04040), .init(60, 0x902060),
    ])

    static let snow = ColorScale(stops: [                 // cm
        .init(0, 0x4F5A68), .init(0.5, 0x5C7DA8), .init(2, 0x6E9FD0),
        .init(5, 0x8FC0E8), .init(10, 0xB8DCF4), .init(25, 0xE8F4FC),
        .init(50, 0xE0B8F0),
    ])

    static let freezingLevel = ColorScale(stops: [        // m
        .init(0, 0xC8DCF0), .init(1000, 0x84B4DC), .init(2000, 0x53A0A8),
        .init(3000, 0x69AF5B), .init(4000, 0xC7BB4B), .init(5000, 0xC77E3F),
        .init(6000, 0xB04040),
    ])

    static let clouds = ColorScale(stops: [               // %
        .init(0, 0x2E62A0), .init(25, 0x5580AE), .init(50, 0x8CA0B4),
        .init(75, 0xB9BFC6), .init(100, 0xE9EBEC),
    ])

    static let visibility = ColorScale(stops: [           // m
        .init(0, 0x8A2F62), .init(1000, 0xB04040), .init(4000, 0xC7833F),
        .init(10000, 0xB6BE62), .init(20000, 0x53A0A8), .init(40000, 0x3961A9),
    ])

    static let uv = ColorScale(stops: [                   // index
        .init(0, 0x4E7CB4), .init(3, 0x64AC50), .init(6, 0xD9C63A),
        .init(8, 0xE0973C), .init(11, 0xC44040), .init(13, 0x8A2F8F),
    ])

    static let solar = ColorScale(stops: [                // W/m²
        .init(0, 0x35435E), .init(150, 0x5C6FA0), .init(350, 0x9C8A50),
        .init(600, 0xD9C63A), .init(850, 0xE0973C), .init(1100, 0xE05C3C),
    ])

    static let pressure = ColorScale(stops: [             // hPa
        .init(960, 0x5C2F80), .init(980, 0x4553B0), .init(1000, 0x3E8CC0),
        .init(1013, 0x60A860), .init(1025, 0xC7B33F), .init(1040, 0xC7683F),
        .init(1055, 0xB04040),
    ])

    static let cape = ColorScale(stops: [                 // J/kg
        .init(0, 0x3C4A62), .init(300, 0x4C7CA0), .init(800, 0x58A868),
        .init(1500, 0xC7C040), .init(2500, 0xE0973C), .init(3500, 0xD1503C),
        .init(5000, 0x9C2F80),
    ])

    static let waves = ColorScale(stops: [                // m
        .init(0, 0x3D50C8), .init(0.5, 0x4477C4), .init(1, 0x3E9CC0),
        .init(2, 0x40B08B), .init(3, 0x9DBB3C), .init(5, 0xE0973C),
        .init(8, 0xD1503C), .init(12, 0x8A2F62),
    ])

    static let currents = ColorScale(stops: [             // m/s
        .init(0, 0x2F4A80), .init(0.25, 0x3E8CC0), .init(0.5, 0x40B08B),
        .init(1, 0xC7C040), .init(1.5, 0xE0973C), .init(2.5, 0xD1503C),
    ])

    static let pollutantFine = ColorScale(stops: [        // µg/m³
        .init(0, 0x4E7CB4), .init(10, 0x64AC50), .init(25, 0xC7C040),
        .init(50, 0xE0973C), .init(100, 0xD1503C), .init(200, 0x8A2F8F),
    ])

    static let pollutantCoarse = ColorScale(stops: [      // µg/m³
        .init(0, 0x4E7CB4), .init(40, 0x64AC50), .init(100, 0xC7C040),
        .init(180, 0xE0973C), .init(300, 0xD1503C), .init(500, 0x8A2F8F),
    ])

    static let aod = ColorScale(stops: [
        .init(0, 0x3C4A62), .init(0.1, 0x4C7CA0), .init(0.3, 0xC7C040),
        .init(0.6, 0xE0973C), .init(1.2, 0xD1503C), .init(2, 0x8A2F62),
    ])

    static let aqi = ColorScale(stops: [                  // US AQI
        .init(0, 0x64AC50), .init(50, 0xC7C040), .init(100, 0xE0973C),
        .init(150, 0xD1503C), .init(200, 0x8A2F8F), .init(300, 0x6E1E38),
    ])
}
