import SwiftUI
import MapKit

// MARK: - All floating controls over the map

struct MapControlsOverlay: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var settings: Settings

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top) {
                statusChip
                Spacer()
                controlColumn
            }
            .padding(.horizontal, 12)

            Spacer()

            HStack {
                Spacer()
                if appState.selectedLayer.supportsAltitude {
                    AltitudeControl()
                        .padding(.trailing, 12)
                }
            }

            bottomPanel
                .padding(.horizontal, 12)
                .padding(.bottom, 8)
        }
    }

    @ViewBuilder
    private var statusChip: some View {
        VStack(alignment: .leading, spacing: 6) {
            if appState.isLoadingGrid {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Loading \(appState.selectedLayer.title)…")
                        .font(.caption)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(.thinMaterial, in: Capsule())
            }
            if let message = appState.statusMessage {
                Text(message)
                    .font(.caption2)
                    .foregroundStyle(.red)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(.thinMaterial, in: Capsule())
            }
        }
    }

    private var controlColumn: some View {
        VStack(spacing: 10) {
            RoundMapButton(systemImage: "magnifyingglass") { appState.showSearch = true }
            RoundMapButton(systemImage: "square.3.layers.3d", isActive: true) { appState.showLayerPicker = true }
            RoundMapButton(systemImage: "video", isActive: appState.showWebcams) { appState.showWebcams = true }
            RoundMapButton(systemImage: "hurricane", isActive: appState.showStorms) {
                appState.showStorms.toggle()
                Task { await appState.loadStorms() }
            }
            RoundMapButton(systemImage: "location") { appState.centerOnUser() }
            RoundMapButton(systemImage: "gearshape") { appState.showSettings = true }
        }
    }

    private var bottomPanel: some View {
        VStack(spacing: 8) {
            HStack {
                layerBadge
                Spacer()
                modelMenu
            }
            if appState.selectedLayer.source != .rasterTiles {
                LegendView(layer: appState.selectedLayer)
            }
            TimelineBar()
        }
        .padding(12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var layerBadge: some View {
        Button { appState.showLayerPicker = true } label: {
            HStack(spacing: 6) {
                Image(systemName: appState.selectedLayer.systemImage)
                Text(appState.selectedLayer.title).fontWeight(.semibold)
                if appState.selectedLayer.supportsAltitude, appState.altitude != .surface {
                    Text(appState.altitude.shortLabel)
                        .foregroundStyle(.secondary)
                }
            }
            .font(.subheadline)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var modelMenu: some View {
        if appState.selectedLayer.source == .forecast || appState.selectedLayer.source == .computed {
            Menu {
                ForEach(ForecastModel.allCases) { model in
                    Button {
                        appState.model = model
                    } label: {
                        if appState.model == model {
                            Label("\(model.label) — \(model.detail)", systemImage: "checkmark")
                        } else {
                            Text("\(model.label) — \(model.detail)")
                        }
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "cpu")
                    Text(appState.model.label)
                }
                .font(.caption)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(.quaternary, in: Capsule())
            }
        }
    }
}

struct RoundMapButton: View {
    let systemImage: String
    var isActive: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 16, weight: .semibold))
                .frame(width: 42, height: 42)
                .background(.regularMaterial, in: Circle())
                .foregroundStyle(isActive ? Color.accentColor : Color.primary)
        }
        .shadow(color: .black.opacity(0.15), radius: 3, y: 1)
    }
}

// MARK: - Timeline (scrubber + play, like Windy's bottom bar)

struct TimelineBar: View {
    @EnvironmentObject private var appState: AppState

    private var range: ClosedRange<Date>? { appState.timelineRange }

    var body: some View {
        HStack(spacing: 10) {
            Button {
                appState.togglePlay()
            } label: {
                Image(systemName: appState.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 16, weight: .bold))
                    .frame(width: 34, height: 34)
                    .background(Color.accentColor.opacity(0.9), in: Circle())
                    .foregroundStyle(.white)
            }
            .disabled(range == nil)

            VStack(spacing: 2) {
                if let range, range.lowerBound < range.upperBound {
                    Slider(
                        value: Binding(
                            get: { appState.timelineDate.timeIntervalSince1970 },
                            set: { appState.timelineDate = Date(timeIntervalSince1970: $0) }
                        ),
                        in: range.lowerBound.timeIntervalSince1970...range.upperBound.timeIntervalSince1970
                    )
                } else {
                    ProgressView().frame(maxWidth: .infinity)
                }
                HStack {
                    Text(appState.timelineDate, format: .dateTime.weekday(.abbreviated).day().month(.abbreviated))
                    Spacer()
                    Text(appState.timelineDate, format: .dateTime.hour().minute())
                        .monospacedDigit()
                        .fontWeight(.semibold)
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - Legend (color scale bar)

struct LegendView: View {
    @EnvironmentObject private var settings: Settings
    let layer: WeatherLayer

    var body: some View {
        let scale = layer.colorScale
        VStack(spacing: 2) {
            RoundedRectangle(cornerRadius: 3)
                .fill(scale.gradient)
                .frame(height: 8)
            HStack {
                ForEach(Array(scale.legendTicks.enumerated()), id: \.offset) { item in
                    if item.offset > 0 { Spacer() }
                    Text(settings.format(value: item.element, for: layer))
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
    }
}

// MARK: - Altitude slider (pressure levels)

struct AltitudeControl: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        VStack(spacing: 4) {
            ForEach(AltitudeLevel.allCases.reversed()) { level in
                Button {
                    appState.altitude = level
                } label: {
                    Text(level.shortLabel)
                        .font(.system(size: 9, weight: appState.altitude == level ? .bold : .regular))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .frame(minWidth: 46)
                        .background(
                            appState.altitude == level ? AnyShapeStyle(Color.accentColor.opacity(0.85)) : AnyShapeStyle(.thinMaterial),
                            in: Capsule()
                        )
                        .foregroundStyle(appState.altitude == level ? .white : .primary)
                }
            }
        }
    }
}

// MARK: - Layer picker sheet (Windy's overlay menu)

struct LayerPickerView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss

    private let columns = [GridItem(.adaptive(minimum: 104), spacing: 10)]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    ForEach(LayerCategory.allCases) { category in
                        VStack(alignment: .leading, spacing: 8) {
                            Text(category.rawValue)
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(.secondary)
                            LazyVGrid(columns: columns, spacing: 10) {
                                ForEach(WeatherLayer.layers(in: category)) { layer in
                                    layerCell(layer)
                                }
                            }
                        }
                    }
                    Text("Forecast layers: Open-Meteo (ECMWF, GFS, ICON, …) · Radar & satellite: RainViewer · Storms: NOAA/NHC")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                .padding()
            }
            .navigationTitle("Layers")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func layerCell(_ layer: WeatherLayer) -> some View {
        let isSelected = appState.selectedLayer == layer
        return Button {
            appState.selectedLayer = layer
            dismiss()
        } label: {
            VStack(spacing: 6) {
                Image(systemName: layer.systemImage)
                    .font(.system(size: 20))
                    .frame(height: 24)
                Text(layer.title)
                    .font(.caption2)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
            }
            .frame(maxWidth: .infinity, minHeight: 68)
            .padding(6)
            .background(
                isSelected ? AnyShapeStyle(Color.accentColor.opacity(0.2)) : AnyShapeStyle(.quaternary.opacity(0.5)),
                in: RoundedRectangle(cornerRadius: 12)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(isSelected ? Color.accentColor : .clear, lineWidth: 1.5)
            )
        }
        .buttonStyle(.plain)
    }
}
