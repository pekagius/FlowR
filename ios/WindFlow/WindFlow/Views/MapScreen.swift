import SwiftUI
import MapKit

// MARK: - MKMapView wrapper

struct WeatherMapView: UIViewRepresentable {
    @ObservedObject var appState: AppState
    @ObservedObject var settings: Settings

    func makeUIView(context: Context) -> MKMapView {
        let map = MKMapView()
        map.delegate = context.coordinator
        map.isRotateEnabled = false
        map.isPitchEnabled = false
        map.showsCompass = false
        map.showsUserLocation = true
        map.pointOfInterestFilter = .excludingAll
        map.setRegion(appState.region, animated: false)

        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleTap(_:)))
        tap.delegate = context.coordinator
        map.addGestureRecognizer(tap)

        context.coordinator.mapView = map
        DispatchQueue.main.async {
            appState.mapRegionChanged(map.region, projection: MapProjection(mapView: map))
        }
        return map
    }

    func updateUIView(_ map: MKMapView, context: Context) {
        let coordinator = context.coordinator
        coordinator.appState = appState

        syncBaseMap(map)
        syncCamera(map)
        coordinator.syncHeatmap()
        coordinator.syncRaster(template: appState.selectedLayer.source == .rasterTiles ? appState.rasterTileTemplate : nil)
        coordinator.syncStorms(appState.showStorms ? appState.storms : [])
    }

    private func syncBaseMap(_ map: MKMapView) {
        switch settings.baseMap {
        case .standard:
            let config = MKStandardMapConfiguration(elevationStyle: .flat, emphasisStyle: .default)
            config.pointOfInterestFilter = .excludingAll
            map.preferredConfiguration = config
        case .muted:
            let config = MKStandardMapConfiguration(elevationStyle: .flat, emphasisStyle: .muted)
            config.pointOfInterestFilter = .excludingAll
            map.preferredConfiguration = config
        case .satellite:
            map.preferredConfiguration = MKImageryMapConfiguration(elevationStyle: .flat)
        case .hybrid:
            map.preferredConfiguration = MKHybridMapConfiguration(elevationStyle: .flat)
        }
    }

    private func syncCamera(_ map: MKMapView) {
        guard let target = appState.cameraTarget else { return }
        DispatchQueue.main.async {
            appState.cameraTarget = nil
            map.setRegion(target, animated: true)
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(appState: appState)
    }

    // MARK: Coordinator

    final class Coordinator: NSObject, MKMapViewDelegate, UIGestureRecognizerDelegate {
        var appState: AppState
        weak var mapView: MKMapView?

        private var heatmapOverlay: HeatmapOverlay?
        private var heatmapRenderer: HeatmapRenderer?
        private var tileOverlay: MKTileOverlay?
        private var tileTemplate: String?
        private var heatmapAlpha: CGFloat = -1
        private var stormAnnotations: [StormAnnotation] = []

        init(appState: AppState) {
            self.appState = appState
        }

        // MARK: overlay sync

        func syncHeatmap() {
            guard let map = mapView else { return }
            let desiredGrid = appState.selectedLayer.source == .rasterTiles ? nil : appState.grid

            let desiredAlpha = CGFloat(appState.settings.overlayOpacity)
            if heatmapOverlay?.grid.id != desiredGrid?.id || heatmapAlpha != desiredAlpha {
                if let old = heatmapOverlay { map.removeOverlay(old) }
                heatmapOverlay = nil
                heatmapRenderer = nil
                heatmapAlpha = desiredAlpha
                if let grid = desiredGrid {
                    let overlay = HeatmapOverlay(
                        grid: grid,
                        alpha: desiredAlpha,
                        fractionalTime: appState.fractionalTime
                    )
                    map.addOverlay(overlay, level: .aboveRoads)
                    heatmapOverlay = overlay
                }
            } else if let overlay = heatmapOverlay {
                let time = appState.fractionalTime
                if abs(overlay.fractionalTime - time) > 0.01 {
                    overlay.fractionalTime = time
                    heatmapRenderer?.setNeedsDisplay()
                }
            }
        }

        func syncRaster(template: String?) {
            guard let map = mapView else { return }
            guard template != tileTemplate else { return }
            if let old = tileOverlay { map.removeOverlay(old) }
            tileOverlay = nil
            tileTemplate = template
            if let template {
                let overlay = MKTileOverlay(urlTemplate: template)
                overlay.canReplaceMapContent = false
                overlay.maximumZ = 12
                map.addOverlay(overlay, level: .aboveRoads)
                tileOverlay = overlay
            }
        }

        func syncStorms(_ storms: [TropicalStorm]) {
            guard let map = mapView else { return }
            let currentIDs = Set(stormAnnotations.map(\.storm.id))
            let desiredIDs = Set(storms.map(\.id))
            guard currentIDs != desiredIDs else { return }
            map.removeAnnotations(stormAnnotations)
            stormAnnotations = storms.map(StormAnnotation.init)
            map.addAnnotations(stormAnnotations)
        }

        // MARK: MKMapViewDelegate

        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            if let heatmap = overlay as? HeatmapOverlay {
                let renderer = HeatmapRenderer(overlay: heatmap)
                heatmapRenderer = renderer
                return renderer
            }
            if let tile = overlay as? MKTileOverlay {
                let renderer = MKTileOverlayRenderer(tileOverlay: tile)
                renderer.alpha = 0.75
                return renderer
            }
            return MKOverlayRenderer(overlay: overlay)
        }

        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            guard let storm = annotation as? StormAnnotation else { return nil }
            let id = "storm"
            let view = mapView.dequeueReusableAnnotationView(withIdentifier: id)
                ?? MKAnnotationView(annotation: storm, reuseIdentifier: id)
            view.annotation = storm
            let config = UIImage.SymbolConfiguration(pointSize: 26, weight: .bold)
            view.image = UIImage(systemName: "hurricane", withConfiguration: config)?
                .withTintColor(.systemRed, renderingMode: .alwaysOriginal)
            view.canShowCallout = true
            return view
        }

        func mapView(_ mapView: MKMapView, didSelect view: MKAnnotationView) {
            guard let storm = (view.annotation as? StormAnnotation)?.storm else { return }
            let place = Place(
                id: "storm-\(storm.id)",
                name: "\(storm.classificationText) \(storm.name)",
                subtitle: "Tropical system",
                latitude: storm.latitude,
                longitude: storm.longitude
            )
            Task { @MainActor in appState.open(place: place, centerMap: false) }
        }

        func mapViewDidChangeVisibleRegion(_ mapView: MKMapView) {
            // Keep the particle projection glued to the map while panning.
            let projection = MapProjection(mapView: mapView)
            Task { @MainActor in appState.projection = projection }
        }

        func mapView(_ mapView: MKMapView, regionDidChangeAnimated animated: Bool) {
            let region = mapView.region
            let projection = MapProjection(mapView: mapView)
            Task { @MainActor in appState.mapRegionChanged(region, projection: projection) }
        }

        // MARK: tap → point forecast

        @objc func handleTap(_ gesture: UITapGestureRecognizer) {
            guard let map = mapView, gesture.state == .ended else { return }
            let point = gesture.location(in: map)
            // Ignore taps on annotation views.
            if map.hitTest(point, with: nil) is MKAnnotationView { return }
            let coordinate = map.convert(point, toCoordinateFrom: map)
            Task { @MainActor in appState.pickCoordinate(coordinate) }
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                               shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
            true
        }
    }
}

final class StormAnnotation: NSObject, MKAnnotation {
    let storm: TropicalStorm
    var coordinate: CLLocationCoordinate2D { storm.coordinate }
    var title: String? { "\(storm.classificationText) \(storm.name)" }
    var subtitle: String? {
        var parts: [String] = []
        if let wind = storm.intensityKt { parts.append("\(Int(wind)) kt") }
        if let pressure = storm.pressureMb { parts.append("\(Int(pressure)) mb") }
        return parts.joined(separator: " · ")
    }
    init(storm: TropicalStorm) { self.storm = storm }
}

// MARK: - Root screen

struct RootView: View {
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var settings: Settings

    var body: some View {
        ZStack {
            WeatherMapView(appState: appState, settings: settings)
                .ignoresSafeArea()

            ParticleCanvas(
                grid: appState.selectedLayer.source == .rasterTiles ? nil : appState.grid,
                projection: appState.projection,
                fractionalTime: appState.fractionalTime,
                density: settings.particleDensity,
                enabled: settings.particlesEnabled
            )
            .ignoresSafeArea()

            MapControlsOverlay()
        }
        .sheet(item: $appState.selectedPlace) { place in
            PointForecastSheet(place: place)
                .presentationDetents([.fraction(0.45), .large])
                .presentationBackgroundInteraction(.enabled(upThrough: .fraction(0.45)))
        }
        .sheet(isPresented: $appState.showSearch) {
            SearchView()
        }
        .sheet(isPresented: $appState.showSettings) {
            SettingsView()
        }
        .sheet(isPresented: $appState.showLayerPicker) {
            LayerPickerView()
                .presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $appState.showWebcams) {
            WebcamListView()
        }
    }
}
