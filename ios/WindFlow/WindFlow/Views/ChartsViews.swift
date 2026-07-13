import SwiftUI
import Charts

// MARK: - Shared helpers

struct TimedValue: Identifiable {
    let id = UUID()
    let date: Date
    let value: Double
    var series: String = ""
}

private func timedValues(_ hourly: HourlySeries, _ variable: String,
                         from start: Date = Date(), hours: Int, stride strideBy: Int = 1,
                         transform: (Double) -> Double = { $0 }) -> [TimedValue] {
    guard let startIndex = hourly.index(closestTo: start) else { return [] }
    let end = min(startIndex + hours, hourly.times.count)
    var result: [TimedValue] = []
    var i = startIndex
    while i < end {
        if let v = hourly.value(variable, at: i) {
            result.append(TimedValue(date: hourly.times[i], value: transform(v)))
        }
        i += strideBy
    }
    return result
}

/// Magnus formula dew point from temperature (°C) and relative humidity (%).
func dewPoint(temperature: Double, relativeHumidity: Double) -> Double {
    let a = 17.62, b = 243.12
    let rh = max(relativeHumidity, 0.1)
    let gamma = log(rh / 100) + a * temperature / (b + temperature)
    return b * gamma / (a - gamma)
}

// MARK: - Meteogram (multi-panel chart like Windy's)

struct MeteogramView: View {
    let forecast: PointForecast
    @EnvironmentObject private var settings: Settings

    private let hours = 120

    var body: some View {
        let hourly = forecast.hourly
        let tempUnit = settings.temperatureUnit
        let temp = timedValues(hourly, "temperature_2m", hours: hours) { tempUnit.convert(fromCelsius: $0) }
        let dew = timedValues(hourly, "dew_point_2m", hours: hours) { tempUnit.convert(fromCelsius: $0) }
        let clouds = timedValues(hourly, "cloud_cover", hours: hours)
        let precip = timedValues(hourly, "precipitation", hours: hours) { settings.precipUnit.convert(fromMM: $0) }
        let wind = timedValues(hourly, "wind_speed_10m", hours: hours) { settings.windUnit.convert(fromMS: $0) }
        let gust = timedValues(hourly, "wind_gusts_10m", hours: hours) { settings.windUnit.convert(fromMS: $0) }

        VStack(alignment: .leading, spacing: 14) {
            chartSection("Cloud cover · %") {
                Chart(clouds) {
                    AreaMark(x: .value("Time", $0.date), y: .value("Clouds", $0.value))
                        .foregroundStyle(.gray.opacity(0.5))
                }
                .chartYScale(domain: 0...100)
            }

            chartSection("Temperature / dew point · \(tempUnit.label)") {
                Chart {
                    ForEach(temp) {
                        LineMark(x: .value("Time", $0.date), y: .value("T", $0.value))
                            .foregroundStyle(.red)
                            .interpolationMethod(.catmullRom)
                    }
                    ForEach(dew) {
                        LineMark(x: .value("Time", $0.date), y: .value("Td", $0.value))
                            .foregroundStyle(.teal)
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                            .interpolationMethod(.catmullRom)
                    }
                }
            }

            chartSection("Precipitation · \(settings.precipUnit.label)") {
                Chart(precip) {
                    BarMark(x: .value("Time", $0.date), y: .value("Rain", $0.value))
                        .foregroundStyle(.blue.opacity(0.7))
                }
            }

            chartSection("Wind / gusts · \(settings.windUnit.label)") {
                Chart {
                    ForEach(wind) {
                        LineMark(x: .value("Time", $0.date), y: .value("Wind", $0.value))
                            .foregroundStyle(.green)
                    }
                    ForEach(gust) {
                        LineMark(x: .value("Time", $0.date), y: .value("Gust", $0.value))
                            .foregroundStyle(.orange)
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                    }
                }
            }
        }
    }

    @ViewBuilder
    func chartSection(_ title: String, @ViewBuilder chart: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            chart().frame(height: 110)
        }
    }
}

// MARK: - Airgram (wind at altitude over time)

struct AirgramView: View {
    let forecast: PointForecast
    @EnvironmentObject private var settings: Settings

    private let levels = PointVariables.pressureLevels   // high pressure = low altitude
    private let stepHours = 3
    private let steps = 24                               // 72 h

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Wind speed and direction at altitude · next 72 h · shaded = likely clouds (RH > 75 %)")
                .font(.caption2)
                .foregroundStyle(.secondary)

            HStack(alignment: .top, spacing: 4) {
                VStack(spacing: 0) {
                    ForEach(levels.sorted(), id: \.self) { level in
                        Text(AltitudeLevel.allCases.first { $0.hPa == level }?.shortLabel ?? "\(level)")
                            .font(.system(size: 8))
                            .foregroundStyle(.secondary)
                            .frame(maxHeight: .infinity)
                    }
                }
                .frame(width: 40, height: 260)

                Canvas { context, size in
                    drawAirgram(context: context, size: size)
                }
                .frame(height: 260)
            }

            LegendView(layer: .wind)
        }
    }

    private func drawAirgram(context: GraphicsContext, size: CGSize) {
        let hourly = forecast.hourly
        guard let startIndex = hourly.index(closestTo: Date()) else { return }
        let sortedLevels = levels.sorted()                // 200 → 950: top row = high altitude
        let cellW = size.width / CGFloat(steps)
        let cellH = size.height / CGFloat(sortedLevels.count)

        for (row, level) in sortedLevels.enumerated() {
            for col in 0..<steps {
                let index = startIndex + col * stepHours
                guard index < hourly.times.count else { continue }
                let rect = CGRect(x: CGFloat(col) * cellW, y: CGFloat(row) * cellH,
                                  width: cellW + 0.5, height: cellH + 0.5)

                if let speed = hourly.value("wind_speed_\(level)hPa", at: index) {
                    let color = ColorScale.wind.color(for: speed)
                    context.fill(Path(rect), with: .color(color.opacity(0.85)))

                    if let direction = hourly.value("wind_direction_\(level)hPa", at: index), col % 2 == 0 {
                        let angle = (direction + 180) * .pi / 180   // pointing where wind goes
                        let cx = rect.midX, cy = rect.midY
                        let len = min(cellW, cellH) * 0.35
                        var arrow = Path()
                        arrow.move(to: CGPoint(x: cx - sin(angle) * len, y: cy + cos(angle) * len))
                        arrow.addLine(to: CGPoint(x: cx + sin(angle) * len, y: cy - cos(angle) * len))
                        context.stroke(arrow, with: .color(.white.opacity(0.8)), lineWidth: 1)
                        context.fill(
                            Path(ellipseIn: CGRect(x: cx + sin(angle) * len - 1.5, y: cy - cos(angle) * len - 1.5, width: 3, height: 3)),
                            with: .color(.white.opacity(0.9))
                        )
                    }
                }

                if let rh = hourly.value("relative_humidity_\(level)hPa", at: index), rh > 75 {
                    context.fill(Path(rect), with: .color(.white.opacity(0.25 + 0.3 * min((rh - 75) / 25, 1))))
                }
            }
        }
    }
}

// MARK: - Sounding (vertical profile)

struct SoundingView: View {
    let forecast: PointForecast
    @EnvironmentObject private var settings: Settings

    @State private var hourOffset: Double = 0

    struct ProfilePoint: Identifiable {
        let id = UUID()
        let heightKm: Double
        let value: Double
        let series: String
    }

    var body: some View {
        let points = profile()
        VStack(alignment: .leading, spacing: 10) {
            Text("Vertical temperature / dew point profile")
                .font(.caption2)
                .foregroundStyle(.secondary)

            Chart(points) { point in
                LineMark(
                    x: .value("Temp", point.value),
                    y: .value("Height", point.heightKm)
                )
                .foregroundStyle(by: .value("Series", point.series))
            }
            .chartForegroundStyleScale(["Temperature": Color.red, "Dew point": Color.teal])
            .chartXAxisLabel("°\(settings.temperatureUnit == .celsius ? "C" : "F")")
            .chartYAxisLabel("km")
            .frame(height: 320)

            VStack(spacing: 2) {
                Slider(value: $hourOffset, in: 0...96, step: 3)
                Text(selectedDate, format: dateFormat)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private var dateFormat: Date.FormatStyle {
        var f = Date.FormatStyle.dateTime.weekday(.abbreviated).day().hour()
        f.timeZone = forecast.timeZone
        return f
    }

    private var selectedDate: Date {
        Date().addingTimeInterval(hourOffset * 3600)
    }

    private func profile() -> [ProfilePoint] {
        let hourly = forecast.hourly
        guard let index = hourly.index(closestTo: selectedDate) else { return [] }
        var result: [ProfilePoint] = []
        for level in PointVariables.pressureLevels {
            guard let t = hourly.value("temperature_\(level)hPa", at: index),
                  let h = hourly.value("geopotential_height_\(level)hPa", at: index) else { continue }
            let heightKm = h / 1000
            result.append(ProfilePoint(heightKm: heightKm,
                                       value: settings.temperatureUnit.convert(fromCelsius: t),
                                       series: "Temperature"))
            if let rh = hourly.value("relative_humidity_\(level)hPa", at: index) {
                let td = dewPoint(temperature: t, relativeHumidity: rh)
                result.append(ProfilePoint(heightKm: heightKm,
                                           value: settings.temperatureUnit.convert(fromCelsius: td),
                                           series: "Dew point"))
            }
        }
        return result.sorted { $0.heightKm < $1.heightKm }
    }
}

// MARK: - Waves tab

struct WavesView: View {
    let marine: MarineForecast
    @EnvironmentObject private var settings: Settings

    var body: some View {
        let hourly = marine.hourly
        let waves = timedValues(hourly, "wave_height", hours: 120)
        let swell = timedValues(hourly, "swell_wave_height", hours: 120)
        let windWaves = timedValues(hourly, "wind_wave_height", hours: 120)

        VStack(alignment: .leading, spacing: 14) {
            if let index = hourly.index(closestTo: Date()) {
                HStack(spacing: 14) {
                    statTile("Waves", hourly.value("wave_height", at: index).map { String(format: "%.1f m", $0) } ?? "—",
                             sub: hourly.value("wave_period", at: index).map { String(format: "%.0f s", $0) })
                    statTile("Swell", hourly.value("swell_wave_height", at: index).map { String(format: "%.1f m", $0) } ?? "—",
                             sub: hourly.value("swell_wave_period", at: index).map { String(format: "%.0f s", $0) })
                    statTile("Sea temp", hourly.value("sea_surface_temperature", at: index).map { settings.temperatureUnit.format(celsius: $0) } ?? "—", sub: nil)
                    statTile("Current", hourly.value("ocean_current_velocity", at: index).map { String(format: "%.1f kn", $0 / 1.852) } ?? "—", sub: nil)
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Wave / swell height · m").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                Chart {
                    ForEach(waves) {
                        AreaMark(x: .value("Time", $0.date), y: .value("Waves", $0.value))
                            .foregroundStyle(.blue.opacity(0.35))
                    }
                    ForEach(swell) {
                        LineMark(x: .value("Time", $0.date), y: .value("Swell", $0.value))
                            .foregroundStyle(.purple)
                    }
                    ForEach(windWaves) {
                        LineMark(x: .value("Time", $0.date), y: .value("Wind waves", $0.value))
                            .foregroundStyle(.teal)
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                    }
                }
                .frame(height: 160)
                HStack(spacing: 12) {
                    label(color: .blue.opacity(0.5), text: "Total")
                    label(color: .purple, text: "Swell")
                    label(color: .teal, text: "Wind waves")
                }
            }
        }
    }

    private func statTile(_ title: String, _ value: String, sub: String?) -> some View {
        VStack(spacing: 2) {
            Text(title).font(.system(size: 9)).foregroundStyle(.secondary)
            Text(value).font(.callout.bold())
            if let sub { Text(sub).font(.system(size: 9)).foregroundStyle(.tertiary) }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 10))
    }

    private func label(color: Color, text: String) -> some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 7, height: 7)
            Text(text).font(.caption2).foregroundStyle(.secondary)
        }
    }
}

// MARK: - Air quality tab

struct AirQualityView: View {
    let airQuality: AirQualityForecast
    @EnvironmentObject private var settings: Settings

    private let pollutants: [(String, String)] = [
        ("pm2_5", "PM2.5"), ("pm10", "PM10"), ("nitrogen_dioxide", "NO₂"),
        ("ozone", "O₃"), ("sulphur_dioxide", "SO₂"), ("carbon_monoxide", "CO"),
        ("dust", "Dust"),
    ]

    var body: some View {
        let hourly = airQuality.hourly
        let pm = timedValues(hourly, "pm2_5", hours: 72)

        VStack(alignment: .leading, spacing: 14) {
            if let index = hourly.index(closestTo: Date()) {
                if let aqi = hourly.value("us_aqi", at: index) {
                    HStack {
                        Text("US AQI").font(.subheadline.weight(.semibold))
                        Spacer()
                        Text("\(Int(aqi)) — \(aqiText(aqi))")
                            .font(.subheadline.bold())
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(ColorScale.aqi.color(for: aqi).opacity(0.8), in: Capsule())
                            .foregroundStyle(.white)
                    }
                }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 76), spacing: 8)], spacing: 8) {
                    ForEach(pollutants, id: \.0) { item in
                        VStack(spacing: 2) {
                            Text(item.1).font(.system(size: 9)).foregroundStyle(.secondary)
                            Text(hourly.value(item.0, at: index).map { String(format: "%.0f", $0) } ?? "—")
                                .font(.callout.bold())
                            Text("µg/m³").font(.system(size: 8)).foregroundStyle(.tertiary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 10))
                    }
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("PM2.5 · next 72 h").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                Chart(pm) {
                    AreaMark(x: .value("Time", $0.date), y: .value("PM2.5", $0.value))
                        .foregroundStyle(.orange.opacity(0.5))
                }
                .frame(height: 130)
            }
        }
    }

    private func aqiText(_ aqi: Double) -> String {
        switch aqi {
        case ..<51: return "Good"
        case ..<101: return "Moderate"
        case ..<151: return "Unhealthy for sensitive"
        case ..<201: return "Unhealthy"
        case ..<301: return "Very unhealthy"
        default: return "Hazardous"
        }
    }
}

// MARK: - Model comparison tab

struct CompareModelsView: View {
    let place: Place
    let comparison: [ForecastModel: HourlySeries]
    @EnvironmentObject private var settings: Settings

    enum Variable: String, CaseIterable, Identifiable {
        case temperature = "Temperature"
        case wind = "Wind"
        case gusts = "Gusts"
        case precipitation = "Rain"
        var id: String { rawValue }

        var apiName: String {
            switch self {
            case .temperature: return "temperature_2m"
            case .wind: return "wind_speed_10m"
            case .gusts: return "wind_gusts_10m"
            case .precipitation: return "precipitation"
            }
        }
    }

    @State private var variable: Variable = .temperature

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Picker("Variable", selection: $variable) {
                ForEach(Variable.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)

            if comparison.isEmpty {
                ProgressView("Loading models…")
                    .frame(maxWidth: .infinity, minHeight: 120)
            } else {
                Chart(chartData) { item in
                    if variable == .precipitation {
                        LineMark(x: .value("Time", item.date), y: .value("Value", item.value))
                            .foregroundStyle(by: .value("Model", item.series))
                            .interpolationMethod(.stepStart)
                    } else {
                        LineMark(x: .value("Time", item.date), y: .value("Value", item.value))
                            .foregroundStyle(by: .value("Model", item.series))
                            .interpolationMethod(.catmullRom)
                    }
                }
                .frame(height: 260)

                Text("Independent runs of the world's leading global models — where they agree, confidence is high.")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private var chartData: [TimedValue] {
        var result: [TimedValue] = []
        for (model, series) in comparison.sorted(by: { $0.key.label < $1.key.label }) {
            let transform: (Double) -> Double = { raw in
                switch self.variable {
                case .temperature: return self.settings.temperatureUnit.convert(fromCelsius: raw)
                case .wind, .gusts: return self.settings.windUnit.convert(fromMS: raw)
                case .precipitation: return self.settings.precipUnit.convert(fromMM: raw)
                }
            }
            let values = timedValues(series, variable.apiName, hours: 120, transform: transform)
            result.append(contentsOf: values.map {
                TimedValue(date: $0.date, value: $0.value, series: model.label)
            })
        }
        return result
    }
}
