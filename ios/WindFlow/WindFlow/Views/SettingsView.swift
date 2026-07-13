import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var settings: Settings
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("Units") {
                    Picker("Wind speed", selection: $settings.windUnit) {
                        ForEach(WindUnit.allCases) { Text($0.label).tag($0) }
                    }
                    Picker("Temperature", selection: $settings.temperatureUnit) {
                        ForEach(TemperatureUnit.allCases) { Text($0.label).tag($0) }
                    }
                    Picker("Pressure", selection: $settings.pressureUnit) {
                        ForEach(PressureUnit.allCases) { Text($0.label).tag($0) }
                    }
                    Picker("Precipitation", selection: $settings.precipUnit) {
                        ForEach(PrecipUnit.allCases) { Text($0.label).tag($0) }
                    }
                    Picker("Heights", selection: $settings.heightUnit) {
                        ForEach(HeightUnit.allCases) { Text($0.label).tag($0) }
                    }
                }

                Section("Forecast") {
                    Picker("Default model", selection: $settings.defaultModel) {
                        ForEach(ForecastModel.allCases) { Text($0.label).tag($0) }
                    }
                    .onChange(of: settings.defaultModel) { _, newValue in
                        appState.model = newValue
                    }
                }

                Section("Map") {
                    Picker("Base map", selection: $settings.baseMap) {
                        ForEach(BaseMapStyle.allCases) { Text($0.label).tag($0) }
                    }
                    Picker("Appearance", selection: $settings.appearance) {
                        ForEach(Appearance.allCases) { Text($0.rawValue.capitalized).tag($0) }
                    }
                    VStack(alignment: .leading) {
                        Text("Overlay opacity")
                        Slider(value: $settings.overlayOpacity, in: 0.2...0.9)
                    }
                }

                Section("Wind animation") {
                    Toggle("Animated particles", isOn: $settings.particlesEnabled)
                    VStack(alignment: .leading) {
                        Text("Particle density")
                        Slider(value: $settings.particleDensity, in: 0.3...2.0)
                    }
                    .disabled(!settings.particlesEnabled)
                }

                Section {
                    TextField("Windy Webcams API key", text: $settings.windyWebcamsAPIKey)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                } header: {
                    Text("Webcams")
                } footer: {
                    Text("Get a free key at api.windy.com to browse 60,000+ webcams near any point on the map.")
                }

                Section("About") {
                    LabeledContent("Forecast data", value: "Open-Meteo.com")
                    LabeledContent("Radar & satellite", value: "RainViewer")
                    LabeledContent("Storm tracks", value: "NOAA / NHC")
                    LabeledContent("Warnings", value: "US NWS")
                    Text("WindFlow is an independent app inspired by Windy.com. Not affiliated with Windyty SE.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
