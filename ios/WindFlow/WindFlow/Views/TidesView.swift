import SwiftUI
import Charts

// MARK: - Tide extremes from the sea-level curve

struct TideEvent: Identifiable {
    let id = UUID()
    let date: Date
    let height: Double     // m relative to mean sea level
    let isHigh: Bool
}

/// Finds high/low water in the hourly sea-level series. Extremes are refined
/// with parabolic interpolation, so timing is better than the 1 h sampling.
func extractTideEvents(times: [Date], values: [Double?]) -> [TideEvent] {
    guard times.count >= 3 else { return [] }
    let dt = times[1].timeIntervalSince(times[0])
    var events: [TideEvent] = []
    for i in 1..<(times.count - 1) {
        guard let prev = values[i - 1], let cur = values[i], let next = values[i + 1] else { continue }
        let isMax = cur >= prev && cur > next
        let isMin = cur <= prev && cur < next
        guard isMax || isMin else { continue }
        let denom = prev - 2 * cur + next
        var offset = 0.0
        if abs(denom) > 1e-9 { offset = min(max(0.5 * (prev - next) / denom, -1), 1) }
        let date = times[i].addingTimeInterval(offset * dt)
        let height = cur - 0.25 * (prev - next) * offset
        events.append(TideEvent(date: date, height: height, isHigh: isMax))
    }
    return events
}

// MARK: - Tides tab

struct TidesView: View {
    let marine: MarineForecast
    let timeZone: TimeZone
    let place: Place

    @EnvironmentObject private var settings: Settings
    @State private var gauge: GaugeReading?
    @State private var gaugeFailed = false

    private var seaLevels: [TimedValue] {
        let hourly = marine.hourly
        guard let start = hourly.index(closestTo: Date().addingTimeInterval(-6 * 3600)) else { return [] }
        let values = hourly.series("sea_level_height_msl")
        let end = min(start + 78, hourly.times.count)   // ~6 h back + 3 days ahead
        return (start..<end).compactMap { i in
            values[i].map { TimedValue(date: hourly.times[i], value: $0) }
        }
    }

    private var events: [TideEvent] {
        extractTideEvents(times: marine.hourly.times,
                          values: marine.hourly.series("sea_level_height_msl"))
    }

    private var upcomingEvents: [TideEvent] {
        events.filter { $0.date > Date().addingTimeInterval(-30 * 60) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if seaLevels.isEmpty {
                ContentUnavailableView(
                    "No tide data here",
                    systemImage: "water.waves.slash",
                    description: Text("Sea level forecasts are only available for coastal waters.")
                )
            } else {
                summaryTiles
                tideChart
                eventList
                gaugeSection
                Text("Tide curve: Open-Meteo sea level forecast (incl. tides). Live gauge: PEGELONLINE / WSV (cm above gauge datum PNP). For safety-critical decisions always check official BSH tide tables.")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .task(id: place.id) {
            gauge = nil
            gaugeFailed = false
            do {
                gauge = try await PegelOnlineService.shared.nearestReading(to: place.coordinate)
                if gauge == nil { gaugeFailed = true }
            } catch {
                gaugeFailed = true
            }
        }
    }

    // MARK: pieces

    private var timeFormat: Date.FormatStyle {
        var f = Date.FormatStyle.dateTime.hour().minute()
        f.timeZone = timeZone
        return f
    }

    private var dayTimeFormat: Date.FormatStyle {
        var f = Date.FormatStyle.dateTime.weekday(.abbreviated).hour().minute()
        f.timeZone = timeZone
        return f
    }

    @ViewBuilder
    private var summaryTiles: some View {
        let nextHigh = upcomingEvents.first { $0.isHigh }
        let nextLow = upcomingEvents.first { !$0.isHigh }
        let range = tidalRange

        HStack(spacing: 10) {
            tile(
                title: "Next high water",
                value: nextHigh.map { $0.date.formatted(timeFormat) } ?? "—",
                sub: nextHigh.map { String(format: "%+.1f m · %@", $0.height, countdown(to: $0.date)) },
                icon: "arrow.up.to.line", color: .blue
            )
            tile(
                title: "Next low water",
                value: nextLow.map { $0.date.formatted(timeFormat) } ?? "—",
                sub: nextLow.map { String(format: "%+.1f m · %@", $0.height, countdown(to: $0.date)) },
                icon: "arrow.down.to.line", color: .teal
            )
            tile(
                title: "Tidal range",
                value: range.map { String(format: "%.1f m", $0) } ?? "—",
                sub: "high ↔ low",
                icon: "arrow.up.and.down", color: .indigo
            )
        }
    }

    /// Range between the next pair of consecutive high/low events.
    private var tidalRange: Double? {
        let upcoming = upcomingEvents
        guard upcoming.count >= 2 else { return nil }
        return abs(upcoming[0].height - upcoming[1].height)
    }

    private func countdown(to date: Date) -> String {
        let minutes = max(Int(date.timeIntervalSince(Date()) / 60), 0)
        return minutes >= 60 ? "in \(minutes / 60) h \(minutes % 60) min" : "in \(minutes) min"
    }

    private func tile(title: String, value: String, sub: String?, icon: String, color: Color) -> some View {
        VStack(spacing: 3) {
            Image(systemName: icon).font(.caption).foregroundStyle(color)
            Text(title).font(.system(size: 8)).foregroundStyle(.secondary)
            Text(value).font(.subheadline.bold()).monospacedDigit()
            if let sub {
                Text(sub).font(.system(size: 8)).foregroundStyle(.tertiary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 10))
    }

    private var tideChart: some View {
        let chartEvents = upcomingEvents.filter { event in
            guard let first = seaLevels.first?.date, let last = seaLevels.last?.date else { return false }
            return event.date >= first && event.date <= last
        }
        return VStack(alignment: .leading, spacing: 4) {
            Text("Sea level · m above MSL").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            Chart {
                ForEach(seaLevels) {
                    AreaMark(x: .value("Time", $0.date), y: .value("Level", $0.value))
                        .foregroundStyle(.blue.opacity(0.25))
                        .interpolationMethod(.catmullRom)
                    LineMark(x: .value("Time", $0.date), y: .value("Level", $0.value))
                        .foregroundStyle(.blue)
                        .interpolationMethod(.catmullRom)
                }
                RuleMark(x: .value("Now", Date()))
                    .foregroundStyle(.red.opacity(0.6))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                ForEach(chartEvents) { event in
                    PointMark(x: .value("Time", event.date), y: .value("Level", event.height))
                        .foregroundStyle(event.isHigh ? .blue : .teal)
                        .annotation(position: event.isHigh ? .top : .bottom) {
                            Text(event.date.formatted(timeFormat))
                                .font(.system(size: 8))
                                .foregroundStyle(.secondary)
                        }
                }
            }
            .frame(height: 190)
        }
    }

    private var eventList: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Upcoming tides").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            VStack(spacing: 0) {
                ForEach(upcomingEvents.prefix(10)) { event in
                    HStack {
                        Image(systemName: event.isHigh ? "arrow.up.to.line" : "arrow.down.to.line")
                            .font(.caption)
                            .foregroundStyle(event.isHigh ? .blue : .teal)
                            .frame(width: 22)
                        Text(event.isHigh ? "High water" : "Low water")
                            .font(.caption)
                        Spacer()
                        Text(event.date, format: dayTimeFormat)
                            .font(.caption.monospacedDigit())
                        Text(String(format: "%+.1f m", event.height))
                            .font(.caption.bold().monospacedDigit())
                            .frame(width: 56, alignment: .trailing)
                            .foregroundStyle(event.isHigh ? .blue : .teal)
                    }
                    .padding(.vertical, 5)
                    Divider()
                }
            }
        }
    }

    @ViewBuilder
    private var gaugeSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Live gauge (PEGELONLINE)").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            if let gauge {
                HStack {
                    Image(systemName: "gauge.with.dots.needle.50percent")
                        .foregroundStyle(.blue)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(gauge.stationName).font(.subheadline.weight(.semibold))
                        Text(String(format: "%.0f km away", gauge.distanceKm))
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 1) {
                        Text(String(format: "%.0f cm", gauge.valueCm))
                            .font(.title3.bold()).monospacedDigit()
                        if let ts = gauge.timestamp {
                            Text(ts, format: timeFormat)
                                .font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(10)
                .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 12))
            } else if gaugeFailed {
                Text("No live gauge nearby (German waters only).")
                    .font(.caption2).foregroundStyle(.tertiary)
            } else {
                ProgressView().controlSize(.small)
            }
        }
    }
}
