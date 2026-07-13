import SwiftUI
import Charts

/// Detail sheet shown when tapping the map or opening a favorite —
/// Windy's point forecast with basic table, meteogram, airgram, sounding,
/// waves, air quality, model comparison and warnings.
struct PointForecastSheet: View {
    let place: Place

    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var settings: Settings
    @EnvironmentObject private var favorites: FavoritesStore
    @Environment(\.dismiss) private var dismiss

    enum Tab: String, CaseIterable {
        case forecast = "Forecast"
        case meteogram = "Meteogram"
        case airgram = "Airgram"
        case sounding = "Sounding"
        case waves = "Waves"
        case tides = "Tides"
        case airQuality = "Air quality"
        case ensemble = "Ensemble"
        case compare = "Compare"
        case history = "History"
        case aviation = "Aviation"
        case alerts = "Warnings"
    }

    @State private var tab: Tab = .forecast
    @State private var forecast: PointForecast?
    @State private var marine: MarineForecast?
    @State private var airQuality: AirQualityForecast?
    @State private var warnings: [WeatherWarning] = []
    @State private var comparison: [ForecastModel: HourlySeries] = [:]
    @State private var observation: ObservedWeather?
    @State private var loadError: String?

    private var availableTabs: [Tab] {
        var tabs: [Tab] = [.forecast, .meteogram, .airgram, .sounding]
        if marine != nil { tabs.append(.waves) }
        if hasTideData { tabs.append(.tides) }
        if airQuality != nil { tabs.append(.airQuality) }
        tabs.append(contentsOf: [.ensemble, .compare, .history, .aviation])
        if !warnings.isEmpty { tabs.append(.alerts) }
        return tabs
    }

    private var hasTideData: Bool {
        guard let marine else { return false }
        return marine.hourly.series("sea_level_height_msl").contains { $0 != nil }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
                .padding(.horizontal)
                .padding(.top, 14)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(availableTabs, id: \.self) { item in
                        tabChip(item)
                    }
                }
                .padding(.horizontal)
                .padding(.vertical, 8)
            }

            Divider()

            ScrollView {
                content
                    .padding()
            }
        }
        .task(id: place.id) { await load() }
    }

    private func tabChip(_ item: Tab) -> some View {
        Button {
            tab = item
        } label: {
            HStack(spacing: 4) {
                if item == .alerts {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                }
                Text(item.rawValue)
            }
            .font(.caption.weight(tab == item ? .bold : .regular))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                tab == item ? AnyShapeStyle(Color.accentColor.opacity(0.2)) : AnyShapeStyle(.quaternary.opacity(0.4)),
                in: Capsule()
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: header

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                Text(place.name).font(.headline)
                HStack(spacing: 6) {
                    if !place.subtitle.isEmpty {
                        Text(place.subtitle)
                    }
                    if let elevation = forecast?.elevation {
                        Text("⛰ \(Int(elevation)) m")
                    }
                    Text(appState.model.label)
                        .padding(.horizontal, 5)
                        .background(.quaternary, in: Capsule())
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Spacer()
            currentConditions
            Button {
                favorites.toggleFavorite(place)
            } label: {
                Image(systemName: favorites.isFavorite(place) ? "star.fill" : "star")
                    .foregroundStyle(.yellow)
            }
            .buttonStyle(.plain)
        }
    }

    @ViewBuilder
    private var currentConditions: some View {
        if let forecast, let index = forecast.hourly.index(closestTo: Date()) {
            let temp = forecast.hourly.value("temperature_2m", at: index)
            let wind = forecast.hourly.value("wind_speed_10m", at: index)
            let code = forecast.hourly.value("weather_code", at: index).map(Int.init) ?? 3
            let isDay = (forecast.hourly.value("is_day", at: index) ?? 1) > 0
            HStack(spacing: 8) {
                Image(systemName: WeatherCode.symbol(code, isDay: isDay))
                    .symbolRenderingMode(.multicolor)
                    .font(.title2)
                VStack(alignment: .leading, spacing: 0) {
                    if let temp { Text(settings.temperatureUnit.format(celsius: temp)).font(.title3.bold()) }
                    if let wind {
                        Text("\(settings.windUnit.format(ms: wind)) \(settings.windUnit.label)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(.trailing, 6)
        }
    }

    // MARK: content switch

    @ViewBuilder
    private var content: some View {
        if let error = loadError {
            ContentUnavailableView("Couldn't load forecast", systemImage: "wifi.exclamationmark", description: Text(error))
        } else if forecast == nil {
            ProgressView("Loading forecast…")
                .frame(maxWidth: .infinity, minHeight: 160)
        } else if let forecast {
            switch tab {
            case .forecast: ForecastTab(forecast: forecast, observation: observation)
            case .meteogram: MeteogramView(forecast: forecast)
            case .airgram: AirgramView(forecast: forecast)
            case .sounding: SoundingView(forecast: forecast)
            case .waves: if let marine { WavesView(marine: marine) }
            case .tides: if let marine { TidesView(marine: marine, timeZone: forecast.timeZone, place: place) }
            case .airQuality: if let airQuality { AirQualityView(airQuality: airQuality) }
            case .ensemble: EnsembleView(place: place)
            case .compare: CompareModelsView(place: place, comparison: comparison)
            case .history: HistoryView(place: place)
            case .aviation: AviationView(place: place)
            case .alerts: WarningsView(warnings: warnings)
            }
        }
    }

    // MARK: loading

    private func load() async {
        forecast = nil
        loadError = nil
        marine = nil
        airQuality = nil
        warnings = []
        observation = nil
        do {
            async let forecastTask = OpenMeteoClient.shared.pointForecast(for: place, model: appState.model)
            async let marineTask = OpenMeteoClient.shared.marineForecast(for: place)
            async let airTask = OpenMeteoClient.shared.airQualityForecast(for: place)
            async let warningsTask = AlertsService.shared.alerts(for: place.coordinate)
            async let comparisonTask = OpenMeteoClient.shared.compareModels(for: place, models: ForecastModel.comparable)
            async let observationTask = BrightSkyService.shared.currentObservation(for: place.coordinate)

            forecast = try await forecastTask
            marine = (try? await marineTask) ?? nil
            airQuality = (try? await airTask) ?? nil
            warnings = (try? await warningsTask) ?? []
            comparison = (try? await comparisonTask) ?? [:]
            observation = (try? await observationTask) ?? nil
        } catch {
            loadError = error.localizedDescription
        }
    }
}

// MARK: - Forecast tab: daily strip + hourly table

struct ForecastTab: View {
    let forecast: PointForecast
    var observation: ObservedWeather?
    @EnvironmentObject private var settings: Settings

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let observation {
                observedCard(observation)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(forecast.daily) { day in
                        dailyCard(day)
                    }
                }
            }

            sunMoonCard

            Text("Hourly")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)

            VStack(spacing: 0) {
                ForEach(hourlyIndices, id: \.self) { index in
                    hourlyRow(index)
                    Divider()
                }
            }
        }
    }

    /// Latest measured values from the nearest DWD station (Bright Sky).
    private func observedCard(_ obs: ObservedWeather) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "dot.scope")
                .foregroundStyle(.green)
            VStack(alignment: .leading, spacing: 1) {
                Text("Observed now · \(obs.stationName)")
                    .font(.caption.weight(.semibold))
                Text(String(format: "%.0f km away · DWD station", obs.distanceKm))
                    .font(.system(size: 9)).foregroundStyle(.secondary)
            }
            Spacer()
            if let temp = obs.temperature {
                Text(settings.temperatureUnit.format(celsius: temp))
                    .font(.callout.bold())
            }
            if let wind = obs.windSpeedMS {
                HStack(spacing: 2) {
                    if let dir = obs.windDirection {
                        Image(systemName: "arrow.up").font(.system(size: 8))
                            .rotationEffect(.degrees(dir + 180))
                    }
                    Text("\(settings.windUnit.format(ms: wind)) \(settings.windUnit.label)")
                        .font(.caption)
                }
                .foregroundStyle(.secondary)
            }
            if let pressure = obs.pressureHPa {
                Text(settings.pressureUnit.format(hPa: pressure))
                    .font(.caption2).foregroundStyle(.tertiary)
            }
        }
        .padding(10)
        .background(.green.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
    }

    private var sunTimeFormat: Date.FormatStyle {
        var f = Date.FormatStyle.dateTime.hour().minute()
        f.timeZone = forecast.timeZone
        return f
    }

    /// Sunrise/sunset from the forecast plus a locally computed moon phase.
    @ViewBuilder
    private var sunMoonCard: some View {
        if let today = forecast.daily.first(where: { Calendar.current.isDate($0.date, inSameDayAs: Date()) }) ?? forecast.daily.first {
            let timeFormat = sunTimeFormat
            HStack(spacing: 12) {
                if let sunrise = today.sunrise {
                    HStack(spacing: 4) {
                        Image(systemName: "sunrise.fill").symbolRenderingMode(.multicolor)
                        Text(sunrise, format: timeFormat).font(.caption.monospacedDigit())
                    }
                }
                if let sunset = today.sunset {
                    HStack(spacing: 4) {
                        Image(systemName: "sunset.fill").symbolRenderingMode(.multicolor)
                        Text(sunset, format: timeFormat).font(.caption.monospacedDigit())
                    }
                }
                if let sunrise = today.sunrise, let sunset = today.sunset {
                    let hours = sunset.timeIntervalSince(sunrise) / 3600
                    Text(String(format: "%.0f h %02.0f min daylight", hours.rounded(.down), (hours.truncatingRemainder(dividingBy: 1)) * 60))
                        .font(.caption2).foregroundStyle(.secondary)
                }
                Spacer()
                HStack(spacing: 4) {
                    Image(systemName: MoonPhase.symbol(for: Date()))
                    VStack(alignment: .leading, spacing: 0) {
                        Text(MoonPhase.name(for: Date())).font(.system(size: 9))
                        Text("\(Int(MoonPhase.illumination(for: Date()) * 100)) %")
                            .font(.system(size: 8)).foregroundStyle(.secondary)
                    }
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 12))
        }
    }

    private var hourlyIndices: [Int] {
        guard let start = forecast.hourly.index(closestTo: Date()) else { return [] }
        let end = min(start + 48, forecast.hourly.times.count)
        return Array(start..<end)
    }

    private func dailyCard(_ day: DailySummary) -> some View {
        VStack(spacing: 4) {
            Text(day.date, format: .dateTime.weekday(.abbreviated))
                .font(.caption2.weight(.semibold))
            Image(systemName: WeatherCode.symbol(day.weatherCode))
                .symbolRenderingMode(.multicolor)
                .font(.title3)
                .frame(height: 22)
            Text(settings.temperatureUnit.format(celsius: day.tempMax)).font(.caption.bold())
            Text(settings.temperatureUnit.format(celsius: day.tempMin))
                .font(.caption2)
                .foregroundStyle(.secondary)
            HStack(spacing: 2) {
                Image(systemName: "arrow.up")
                    .font(.system(size: 7))
                    .rotationEffect(.degrees(day.windDirection + 180))
                Text(settings.windUnit.format(ms: day.windMax))
                    .font(.system(size: 9))
            }
            .foregroundStyle(.secondary)
            if day.precipSum > 0.1 {
                Text(settings.precipUnit.format(mm: day.precipSum))
                    .font(.system(size: 8))
                    .foregroundStyle(.blue)
            }
        }
        .frame(width: 62)
        .padding(.vertical, 8)
        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 10))
    }

    private func hourlyRow(_ index: Int) -> some View {
        let hourly = forecast.hourly
        let time = hourly.times[index]
        let code = hourly.value("weather_code", at: index).map(Int.init) ?? 3
        let isDay = (hourly.value("is_day", at: index) ?? 1) > 0
        let temp = hourly.value("temperature_2m", at: index)
        let precip = hourly.value("precipitation", at: index) ?? 0
        let precipProb = hourly.value("precipitation_probability", at: index)
        let wind = hourly.value("wind_speed_10m", at: index)
        let gust = hourly.value("wind_gusts_10m", at: index)
        let dir = hourly.value("wind_direction_10m", at: index) ?? 0

        var timeFormat = Date.FormatStyle.dateTime.hour(.twoDigits(amPM: .abbreviated))
        timeFormat.timeZone = forecast.timeZone
        var dayFormat = Date.FormatStyle.dateTime.weekday(.abbreviated)
        dayFormat.timeZone = forecast.timeZone

        return HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 0) {
                Text(time, format: timeFormat).font(.caption.monospacedDigit())
                Text(time, format: dayFormat).font(.system(size: 8)).foregroundStyle(.tertiary)
            }
            .frame(width: 52, alignment: .leading)

            Image(systemName: WeatherCode.symbol(code, isDay: isDay))
                .symbolRenderingMode(.multicolor)
                .frame(width: 26)

            Text(temp.map { settings.temperatureUnit.format(celsius: $0) } ?? "—")
                .font(.callout.weight(.semibold))
                .frame(width: 44, alignment: .trailing)
                .foregroundStyle(temp.map { ColorScale.temperature.color(for: $0) } ?? .primary)

            VStack(alignment: .leading, spacing: 0) {
                if precip > 0.05 {
                    Text(settings.precipUnit.format(mm: precip))
                        .font(.caption2)
                        .foregroundStyle(.blue)
                }
                if let precipProb, precipProb >= 5 {
                    Text("\(Int(precipProb)) %")
                        .font(.system(size: 8))
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 54, alignment: .leading)

            Spacer()

            Image(systemName: "arrow.up")
                .font(.caption2)
                .rotationEffect(.degrees(dir + 180))
                .foregroundStyle(.secondary)
            VStack(alignment: .trailing, spacing: 0) {
                Text(wind.map { "\(settings.windUnit.format(ms: $0)) \(settings.windUnit.label)" } ?? "—")
                    .font(.caption)
                    .foregroundStyle(wind.map { ColorScale.wind.color(for: $0) } ?? .primary)
                if let gust {
                    Text("G \(settings.windUnit.format(ms: gust))")
                        .font(.system(size: 8))
                        .foregroundStyle(.tertiary)
                }
            }
            .frame(width: 60, alignment: .trailing)
        }
        .padding(.vertical, 5)
    }
}

// MARK: - Warnings tab

struct WarningsView: View {
    let warnings: [WeatherWarning]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if warnings.isEmpty {
                ContentUnavailableView("No active warnings", systemImage: "checkmark.shield")
            }
            ForEach(warnings) { warning in
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(warning.severityRank >= 3 ? .red : .orange)
                        Text(warning.event).font(.subheadline.bold())
                        Spacer()
                        Text(warning.severity)
                            .font(.caption2)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(.quaternary, in: Capsule())
                    }
                    if !warning.headline.isEmpty {
                        Text(warning.headline).font(.caption.weight(.medium))
                    }
                    Text(warning.areaDesc).font(.caption2).foregroundStyle(.secondary)
                    Text(warning.description)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(8)
                }
                .padding(10)
                .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 12))
            }
            Text("Warnings: US National Weather Service (US coverage only).")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }
}
