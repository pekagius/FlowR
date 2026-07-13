import SwiftUI

/// Webcams near the current map center (Windy Webcams API, needs a free key).
struct WebcamListView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var settings: Settings
    @Environment(\.dismiss) private var dismiss

    @State private var webcams: [Webcam] = []
    @State private var isLoading = false
    @State private var errorText: String?

    var body: some View {
        NavigationStack {
            Group {
                if settings.windyWebcamsAPIKey.isEmpty {
                    ContentUnavailableView(
                        "API key required",
                        systemImage: "key",
                        description: Text("Enter a free Windy Webcams API key in Settings to browse webcams around the map center.")
                    )
                } else if isLoading {
                    ProgressView("Loading webcams…")
                } else if let errorText {
                    ContentUnavailableView("Couldn't load webcams", systemImage: "video.slash", description: Text(errorText))
                } else if webcams.isEmpty {
                    ContentUnavailableView("No webcams nearby", systemImage: "video.slash")
                } else {
                    List(webcams) { webcam in
                        VStack(alignment: .leading, spacing: 6) {
                            if let preview = webcam.images?.current?.preview, let url = URL(string: preview) {
                                AsyncImage(url: url) { image in
                                    image.resizable().aspectRatio(contentMode: .fill)
                                } placeholder: {
                                    Rectangle().fill(.quaternary)
                                }
                                .frame(height: 150)
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                            }
                            Text(webcam.title).font(.subheadline.weight(.semibold))
                            if let location = webcam.location {
                                Text([location.city, location.country].compactMap { $0 }.joined(separator: ", "))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.vertical, 4)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            if let lat = webcam.location?.latitude, let lon = webcam.location?.longitude {
                                dismiss()
                                appState.open(place: Place(
                                    id: "webcam-\(webcam.webcamId)",
                                    name: webcam.title,
                                    subtitle: "Webcam",
                                    latitude: lat, longitude: lon
                                ))
                            }
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("Webcams")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Reload") { Task { await load() } }
                }
            }
            .task { await load() }
        }
    }

    private func load() async {
        guard !settings.windyWebcamsAPIKey.isEmpty else { return }
        isLoading = true
        errorText = nil
        defer { isLoading = false }
        do {
            webcams = try await WebcamService.shared.webcams(
                near: appState.region.center,
                radiusKm: 120,
                apiKey: settings.windyWebcamsAPIKey
            )
        } catch {
            errorText = error.localizedDescription
        }
    }
}
