import SwiftUI
import Charts

// MARK: - Ensemble forecast (uncertainty bands from ensemble members)

struct EnsembleView: View {
    let place: Place
    @EnvironmentObject private var settings: Settings

    enum Variable: String, CaseIterable, Identifiable {
        case temperature = "Temperature"
        case precipitation = "Rain"
        case wind = "Wind"
        var id: String { rawValue }
        var apiName: String {
            switch self {
            case .temperature: return "temperature_2m"
            case .precipitation: return "precipitation"
            case .wind: return "wind_speed_10m"
            }
        }
    }

    struct Band: Identifiable {
        let id = UUID()
        let date: Date
        let min: Double
        let p25: Double
        let median: Double
        let p75: Double
        let max: Double
    }

    @State private var series: HourlySeries?
    @State private var failed = false
    @State private var variable: Variable = .temperature

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Picker("Variable", selection: $variable) {
                ForEach(Variable.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)

            if let bands = bands, !bands.isEmpty {
                Chart(bands) { band in
                    AreaMark(x: .value("Time", band.date),
                             yStart: .value("Min", band.min),
                             yEnd: .value("Max", band.max))
                        .foregroundStyle(.blue.opacity(0.15))
                    AreaMark(x: .value("Time", band.date),
                             yStart: .value("P25", band.p25),
                             yEnd: .value("P75", band.p75))
                        .foregroundStyle(.blue.opacity(0.35))
                    LineMark(x: .value("Time", band.date), y: .value("Median", band.median))
                        .foregroundStyle(.blue)
                }
                .frame(height: 240)

                HStack(spacing: 12) {
                    legendSwatch(.blue.opacity(0.15), "Full member spread")
                    legendSwatch(.blue.opacity(0.35), "Middle 50 %")
                    legendSwatch(.blue, "Median")
                }

                Text("All ~30 ensemble members of one model run with slightly varied start conditions. A narrow band means a confident forecast; a wide band means genuine uncertainty.")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            } else if failed {
                ContentUnavailableView("Ensemble unavailable", systemImage: "chart.line.uptrend.xyaxis")
            } else {
                ProgressView("Loading ensemble members…")
                    .frame(maxWidth: .infinity, minHeight: 160)
            }
        }
        .task(id: place.id) {
            series = nil
            failed = false
            series = try? await OpenMeteoClient.shared.ensembleForecast(for: place)
            if series == nil { failed = true }
        }
    }

    private func legendSwatch(_ color: Color, _ text: String) -> some View {
        HStack(spacing: 4) {
            RoundedRectangle(cornerRadius: 2).fill(color).frame(width: 14, height: 8)
            Text(text).font(.caption2).foregroundStyle(.secondary)
        }
    }

    private var bands: [Band]? {
        guard let series else { return nil }
        let base = variable.apiName
        let memberKeys = series.values.keys.filter { $0 == base || $0.hasPrefix(base + "_member") }
        guard memberKeys.count > 1 else { return nil }

        func transform(_ raw: Double) -> Double {
            switch variable {
            case .temperature: return settings.temperatureUnit.convert(fromCelsius: raw)
            case .precipitation: return settings.precipUnit.convert(fromMM: raw)
            case .wind: return settings.windUnit.convert(fromMS: raw)
            }
        }

        var result: [Band] = []
        for (i, date) in series.times.enumerated() where i % 3 == 0 {
            var members: [Double] = []
            for key in memberKeys {
                if let v = series.value(key, at: i) { members.append(transform(v)) }
            }
            guard members.count > 2 else { continue }
            members.sort()
            func percentile(_ p: Double) -> Double {
                members[Swift.min(Int(p * Double(members.count - 1)), members.count - 1)]
            }
            result.append(Band(
                date: date,
                min: members.first ?? 0,
                p25: percentile(0.25),
                median: percentile(0.5),
                p75: percentile(0.75),
                max: members.last ?? 0
            ))
        }
        return result
    }
}

// MARK: - Recent weather history (observed past)

struct HistoryView: View {
    let place: Place
    @EnvironmentObject private var settings: Settings

    @State private var data: OpenMeteoClient.HistoryData?
    @State private var failed = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let data {
                let days = pastDays(data)
                summary(days)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Daily min–max temperature · \(settings.temperatureUnit.label) · last 31 days")
                        .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    Chart(days) { day in
                        BarMark(
                            x: .value("Day", day.date, unit: .day),
                            yStart: .value("Min", settings.temperatureUnit.convert(fromCelsius: day.tempMin)),
                            yEnd: .value("Max", settings.temperatureUnit.convert(fromCelsius: day.tempMax)),
                            width: .ratio(0.55)
                        )
                        .foregroundStyle(ColorScale.temperature.color(for: (day.tempMin + day.tempMax) / 2))
                        .cornerRadius(2)
                    }
                    .frame(height: 170)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("Daily precipitation · \(settings.precipUnit.label)")
                        .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    Chart(days) { day in
                        BarMark(
                            x: .value("Day", day.date, unit: .day),
                            y: .value("Rain", settings.precipUnit.convert(fromMM: day.precipSum))
                        )
                        .foregroundStyle(.blue.opacity(0.7))
                    }
                    .frame(height: 110)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("Daily max wind · \(settings.windUnit.label)")
                        .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    Chart(days) { day in
                        LineMark(
                            x: .value("Day", day.date, unit: .day),
                            y: .value("Wind", settings.windUnit.convert(fromMS: day.windMax))
                        )
                        .foregroundStyle(.green)
                    }
                    .frame(height: 110)
                }

                Text("Source: Open-Meteo — recent model analyses of what actually happened.")
                    .font(.caption2).foregroundStyle(.tertiary)
            } else if failed {
                ContentUnavailableView("History unavailable", systemImage: "clock.arrow.circlepath")
            } else {
                ProgressView("Loading last 31 days…")
                    .frame(maxWidth: .infinity, minHeight: 160)
            }
        }
        .task(id: place.id) {
            data = nil
            failed = false
            data = try? await OpenMeteoClient.shared.history(for: place)
            if data == nil { failed = true }
        }
    }

    private func pastDays(_ data: OpenMeteoClient.HistoryData) -> [DailySummary] {
        let startOfToday = Calendar.current.startOfDay(for: Date())
        return data.daily.filter { $0.date < startOfToday }
    }

    @ViewBuilder
    private func summary(_ days: [DailySummary]) -> some View {
        if let warmest = days.max(by: { $0.tempMax < $1.tempMax }),
           let coldest = days.min(by: { $0.tempMin < $1.tempMin }),
           let wettest = days.max(by: { $0.precipSum < $1.precipSum }),
           let windiest = days.max(by: { $0.windMax < $1.windMax }) {
            HStack(spacing: 8) {
                statTile("Warmest", settings.temperatureUnit.format(celsius: warmest.tempMax), warmest.date)
                statTile("Coldest", settings.temperatureUnit.format(celsius: coldest.tempMin), coldest.date)
                statTile("Wettest", settings.precipUnit.format(mm: wettest.precipSum), wettest.date)
                statTile("Windiest", "\(settings.windUnit.format(ms: windiest.windMax)) \(settings.windUnit.label)", windiest.date)
            }
        }
    }

    private func statTile(_ title: String, _ value: String, _ date: Date) -> some View {
        VStack(spacing: 2) {
            Text(title).font(.system(size: 8)).foregroundStyle(.secondary)
            Text(value).font(.caption.bold())
            Text(date, format: .dateTime.day().month(.abbreviated))
                .font(.system(size: 8)).foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 7)
        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 10))
    }
}

// MARK: - Aviation weather (METAR / TAF from NOAA AWC)

struct AviationView: View {
    let place: Place
    @EnvironmentObject private var settings: Settings

    @State private var reports: [MetarReport]?
    @State private var failed = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let reports {
                if reports.isEmpty {
                    ContentUnavailableView("No reporting airports nearby", systemImage: "airplane.circle")
                }
                ForEach(reports) { report in
                    stationCard(report)
                }
                Text("Live METAR/TAF from NOAA Aviation Weather Center. Flight categories: VFR · MVFR · IFR · LIFR.")
                    .font(.caption2).foregroundStyle(.tertiary)
            } else if failed {
                ContentUnavailableView("Aviation weather unavailable", systemImage: "airplane.circle")
            } else {
                ProgressView("Loading METARs…")
                    .frame(maxWidth: .infinity, minHeight: 160)
            }
        }
        .task(id: place.id) {
            reports = nil
            failed = false
            do {
                reports = try await AviationService.shared.metars(around: place.coordinate)
            } catch {
                failed = true
            }
        }
    }

    private func categoryColor(_ category: String?) -> Color {
        switch category?.uppercased() {
        case "VFR": return .green
        case "MVFR": return .blue
        case "IFR": return .red
        case "LIFR": return .purple
        default: return .gray
        }
    }

    private func stationCard(_ report: MetarReport) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(report.icaoId).font(.subheadline.bold().monospaced())
                if let category = report.fltCat {
                    Text(category)
                        .font(.caption2.bold())
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(categoryColor(category).opacity(0.85), in: Capsule())
                        .foregroundStyle(.white)
                }
                Spacer()
                if let temp = report.temp?.value {
                    Text(settings.temperatureUnit.format(celsius: temp)).font(.caption.bold())
                }
                if let wspd = report.wspd?.value {
                    let dir = report.wdir?.value
                    HStack(spacing: 2) {
                        if let dir {
                            Image(systemName: "arrow.up").font(.system(size: 8))
                                .rotationEffect(.degrees(dir + 180))
                        }
                        Text("\(settings.windUnit.format(ms: wspd * 0.514444)) \(settings.windUnit.label)")
                            .font(.caption)
                    }
                    .foregroundStyle(.secondary)
                }
            }
            if let name = report.name {
                Text(name).font(.caption2).foregroundStyle(.secondary)
            }
            if let raw = report.rawOb {
                Text(raw)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
            if let taf = report.rawTAF {
                DisclosureGroup {
                    Text(taf)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } label: {
                    Text("TAF").font(.caption.weight(.semibold))
                }
            }
        }
        .padding(10)
        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 12))
    }
}
