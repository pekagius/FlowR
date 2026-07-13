import Foundation
import SwiftUI
import MapKit
import Combine

@MainActor
final class AppState: ObservableObject {
    let settings: Settings
    let favorites = FavoritesStore()
    let location = LocationService()

    // Layer / model / altitude selection
    @Published var selectedLayer: WeatherLayer = .wind { didSet { layerChanged(from: oldValue) } }
    @Published var altitude: AltitudeLevel = .surface { didSet { if oldValue != altitude { refreshGrid() } } }
    @Published var model: ForecastModel { didSet { if oldValue != model { refreshGrid() } } }

    // Timeline
    @Published var timelineDate = Date()
    @Published var isPlaying = false

    // Map state
    @Published var cameraTarget: MKCoordinateRegion?    // set → map animates there once
    @Published private(set) var region = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 50.0, longitude: 10.0),
        span: MKCoordinateSpan(latitudeDelta: 18, longitudeDelta: 24)
    )
    @Published var projection: MapProjection = .zero

    // Data
    @Published private(set) var grid: WeatherGrid?
    @Published private(set) var isLoadingGrid = false
    @Published private(set) var statusMessage: String?
    @Published private(set) var rainViewer: RainViewerFrames?
    @Published private(set) var storms: [TropicalStorm] = []
    @Published var showStorms = true

    // Navigation
    @Published var selectedPlace: Place?
    @Published var showSearch = false
    @Published var showSettings = false
    @Published var showLayerPicker = false
    @Published var showWebcams = false

    private var gridTask: Task<Void, Never>?
    private var playTimer: Timer?
    private var regionDebounce: Task<Void, Never>?
    private var locationCancellable: AnyCancellable?
    private var didCenterOnUser = false

    init(settings: Settings) {
        self.settings = settings
        self.model = settings.defaultModel
        refreshGrid()
        Task { await loadStorms() }
        locationCancellable = location.$lastLocation
            .compactMap { $0 }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] loc in
                guard let self, !self.didCenterOnUser else { return }
                self.didCenterOnUser = true
                self.cameraTarget = MKCoordinateRegion(
                    center: loc.coordinate,
                    span: MKCoordinateSpan(latitudeDelta: 8, longitudeDelta: 10)
                )
            }
        location.requestLocation()
    }

    // MARK: - Layer & region changes

    private func layerChanged(from oldValue: WeatherLayer) {
        guard oldValue != selectedLayer else { return }
        if !selectedLayer.supportsAltitude { altitude = .surface }
        refreshGrid()
    }

    /// Called by the map coordinator whenever the visible region settles.
    func mapRegionChanged(_ newRegion: MKCoordinateRegion, projection: MapProjection) {
        region = newRegion
        self.projection = projection
        regionDebounce?.cancel()
        regionDebounce = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 500_000_000)
            guard !Task.isCancelled else { return }
            self?.refreshGrid()
        }
    }

    // MARK: - Grid / raster loading

    func refreshGrid() {
        gridTask?.cancel()

        if selectedLayer.source == .rasterTiles {
            grid = nil
            gridTask = Task { [weak self] in
                guard let self else { return }
                self.isLoadingGrid = true
                defer { self.isLoadingGrid = false }
                do {
                    if self.selectedLayer != .satelliteVisible {
                        let frames = try await RainViewerClient.shared.frames()
                        guard !Task.isCancelled else { return }
                        self.rainViewer = frames
                    }
                    // Clamp the timeline into the raster range.
                    if let range = self.timelineRange {
                        self.timelineDate = min(max(range.lowerBound, self.timelineDate), range.upperBound)
                    }
                    self.statusMessage = nil
                } catch {
                    self.statusMessage = "Radar unavailable: \(error.localizedDescription)"
                }
            }
            return
        }

        let request = GridService.GridRequest(
            layer: selectedLayer, altitude: altitude, model: model, region: region
        )
        gridTask = Task { [weak self] in
            guard let self else { return }
            self.isLoadingGrid = true
            defer { self.isLoadingGrid = false }
            do {
                let grid = try await GridService.shared.grid(for: request)
                guard !Task.isCancelled else { return }
                self.grid = grid
                self.statusMessage = nil
                if let range = self.timelineRange, !range.contains(self.timelineDate) {
                    self.timelineDate = max(range.lowerBound, min(Date(), range.upperBound))
                }
            } catch is CancellationError {
            } catch {
                guard !Task.isCancelled else { return }
                self.statusMessage = "Couldn't load layer: \(error.localizedDescription)"
            }
        }
    }

    func loadStorms() async {
        storms = (try? await HurricaneService.shared.activeStorms()) ?? []
    }

    // MARK: - Timeline

    var timelineRange: ClosedRange<Date>? {
        switch selectedLayer {
        case .radar:
            guard let frames = rainViewer?.allRadar, let f = frames.first, let l = frames.last,
                  f.time < l.time else { return nil }
            return f.time...l.time
        case .satellite:
            guard let frames = rainViewer?.satellite, let f = frames.first, let l = frames.last,
                  f.time < l.time else { return nil }
            return f.time...l.time
        case .satelliteVisible:
            // NASA GIBS true-color imagery: one image per day, ~8 recent days
            // (current day is usually incomplete, so end yesterday).
            let calendar = Calendar(identifier: .gregorian)
            let yesterday = calendar.startOfDay(for: Date().addingTimeInterval(-86400))
            return yesterday.addingTimeInterval(-7 * 86400)...yesterday
        default:
            return grid?.timeRange ?? Date()...Date().addingTimeInterval(7 * 86400)
        }
    }

    var fractionalTime: Double {
        grid?.timeIndex(for: timelineDate) ?? 0
    }

    /// Tile URL template for the radar/satellite frame nearest to the timeline.
    var rasterTileTemplate: String? {
        if selectedLayer == .satelliteVisible { return independentRasterTemplate }
        guard let rainViewer else { return nil }
        switch selectedLayer {
        case .radar:
            guard let frame = RainViewerFrames.closest(rainViewer.allRadar, to: timelineDate) else { return nil }
            return rainViewer.radarTileTemplate(for: frame)
        case .satellite:
            guard let frame = RainViewerFrames.closest(rainViewer.satellite, to: timelineDate) else { return nil }
            return rainViewer.satelliteTileTemplate(for: frame)
        default:
            return nil
        }
    }

    private static let gibsDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = TimeZone(identifier: "UTC")
        return f
    }()

    /// Tile template for layers that don't need the RainViewer frame index.
    var independentRasterTemplate: String? {
        guard selectedLayer == .satelliteVisible else { return nil }
        let clamped = timelineRange.map { min(max(timelineDate, $0.lowerBound), $0.upperBound) } ?? timelineDate
        let day = Self.gibsDateFormatter.string(from: clamped)
        return "https://gibs.earthdata.nasa.gov/wmts/epsg3857/best/VIIRS_SNPP_CorrectedReflectance_TrueColor/default/\(day)/GoogleMapsCompatible_Level9/{z}/{y}/{x}.jpg"
    }

    func togglePlay() {
        isPlaying ? stopPlaying() : startPlaying()
    }

    private func startPlaying() {
        guard let range = timelineRange else { return }
        isPlaying = true
        let isRaster = selectedLayer.source == .rasterTiles
        // Forecast: ~3 forecast hours per real second. Radar: one frame ≈ 10 min.
        let stepPerTick: TimeInterval = isRaster ? 5 * 60 : 9 * 60
        playTimer?.invalidate()
        playTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                var next = self.timelineDate.addingTimeInterval(stepPerTick)
                if next > range.upperBound { next = range.lowerBound }
                self.timelineDate = next
            }
        }
    }

    func stopPlaying() {
        isPlaying = false
        playTimer?.invalidate()
        playTimer = nil
    }

    // MARK: - Places

    func open(place: Place, centerMap: Bool = true) {
        selectedPlace = place
        if !place.subtitle.isEmpty && place.subtitle != "Picked location" {
            favorites.addRecent(place)
        }
        if centerMap {
            cameraTarget = MKCoordinateRegion(
                center: place.coordinate,
                span: MKCoordinateSpan(latitudeDelta: min(region.span.latitudeDelta, 6),
                                       longitudeDelta: min(region.span.longitudeDelta, 8))
            )
        }
    }

    func pickCoordinate(_ coordinate: CLLocationCoordinate2D) {
        let place = Place.fromCoordinate(coordinate)
        selectedPlace = place
        // Resolve a human-readable name asynchronously (free reverse geocoder).
        Task { [weak self] in
            guard let named = await ReverseGeocodeService.shared.name(for: coordinate) else { return }
            guard let self, self.selectedPlace?.id == place.id else { return }
            var updated = place
            updated.name = named.name
            updated.subtitle = named.subtitle
            self.selectedPlace = updated
        }
    }

    func centerOnUser() {
        location.requestLocation()
        if let loc = location.lastLocation {
            cameraTarget = MKCoordinateRegion(
                center: loc.coordinate,
                span: MKCoordinateSpan(latitudeDelta: 4, longitudeDelta: 5)
            )
        }
    }
}
