import SwiftUI

@main
struct WindFlowApp: App {
    @StateObject private var settings: Settings
    @StateObject private var appState: AppState

    init() {
        let settings = Settings()
        _settings = StateObject(wrappedValue: settings)
        _appState = StateObject(wrappedValue: AppState(settings: settings))
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(settings)
                .environmentObject(appState)
                .environmentObject(appState.favorites)
                .preferredColorScheme(settings.appearance.colorScheme)
        }
    }
}
