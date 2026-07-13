import SwiftUI

/// Location search with favorites and recents, like Windy's search panel.
struct SearchView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var favorites: FavoritesStore
    @Environment(\.dismiss) private var dismiss

    @State private var query = ""
    @State private var results: [Place] = []
    @State private var isSearching = false
    @State private var searchTask: Task<Void, Never>?

    var body: some View {
        NavigationStack {
            List {
                if !query.isEmpty {
                    Section("Results") {
                        if isSearching && results.isEmpty {
                            ProgressView()
                        }
                        ForEach(results) { place in
                            row(place)
                        }
                        if !isSearching && results.isEmpty {
                            Text("No places found").foregroundStyle(.secondary)
                        }
                    }
                }

                if !favorites.favorites.isEmpty {
                    Section("Favorites") {
                        ForEach(favorites.favorites) { place in
                            row(place)
                        }
                        .onDelete { favorites.removeFavorites(at: $0) }
                    }
                }

                if !favorites.recents.isEmpty {
                    Section("Recent") {
                        ForEach(favorites.recents) { place in
                            row(place)
                        }
                    }
                }
            }
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search place, city, spot…")
            .onChange(of: query) { _, newValue in
                search(newValue)
            }
            .navigationTitle("Search")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
    }

    private func row(_ place: Place) -> some View {
        Button {
            dismiss()
            appState.open(place: place)
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(place.name).foregroundStyle(.primary)
                    if !place.subtitle.isEmpty {
                        Text(place.subtitle).font(.caption).foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Button {
                    favorites.toggleFavorite(place)
                } label: {
                    Image(systemName: favorites.isFavorite(place) ? "star.fill" : "star")
                        .foregroundStyle(.yellow)
                }
                .buttonStyle(.borderless)
            }
        }
    }

    private func search(_ text: String) {
        searchTask?.cancel()
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard trimmed.count >= 2 else {
            results = []
            return
        }
        searchTask = Task {
            isSearching = true
            defer { isSearching = false }
            try? await Task.sleep(nanoseconds: 300_000_000)   // debounce
            guard !Task.isCancelled else { return }
            let found = (try? await OpenMeteoClient.shared.search(trimmed)) ?? []
            guard !Task.isCancelled else { return }
            results = found
        }
    }
}
