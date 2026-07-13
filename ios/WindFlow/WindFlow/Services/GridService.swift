import Foundation
import MapKit

/// Fetches a grid of forecast values covering a map region by querying
/// Open-Meteo with a batch of grid-point coordinates.
actor GridService {
    static let shared = GridService()

    private var cache: [String: WeatherGrid] = [:]
    private var cacheOrder: [String] = []

    struct GridRequest {
        let layer: WeatherLayer
        let altitude: AltitudeLevel
        let model: ForecastModel
        let region: MKCoordinateRegion
    }

    func grid(for request: GridRequest) async throws -> WeatherGrid? {
        guard request.layer.source != .rasterTiles else { return nil }

        let key = cacheKey(request)
        if let cached = cache[key] { return cached }

        let grid = try await fetch(request)
        if let grid {
            cache[key] = grid
            cacheOrder.append(key)
            if cacheOrder.count > 8 {
                let evicted = cacheOrder.removeFirst()
                cache[evicted] = nil
            }
        }
        return grid
    }

    private func cacheKey(_ r: GridRequest) -> String {
        let b = paddedBounds(r.region)
        // Round bounds so tiny pans hit the cache.
        return String(
            format: "%@|%@|%@|%.1f|%.1f|%.1f|%.1f",
            r.layer.rawValue, r.altitude.rawValue, r.model.rawValue,
            b.latMin, b.latMax, b.lonMin, b.lonMax
        )
    }

    private struct Bounds { let latMin, latMax, lonMin, lonMax: Double }

    private func paddedBounds(_ region: MKCoordinateRegion) -> Bounds {
        let padLat = region.span.latitudeDelta * 0.35
        let padLon = region.span.longitudeDelta * 0.35
        var latMin = region.center.latitude - region.span.latitudeDelta / 2 - padLat
        var latMax = region.center.latitude + region.span.latitudeDelta / 2 + padLat
        var lonMin = region.center.longitude - region.span.longitudeDelta / 2 - padLon
        var lonMax = region.center.longitude + region.span.longitudeDelta / 2 + padLon
        latMin = max(latMin, -80); latMax = min(latMax, 80)
        lonMin = max(lonMin, -179.5); lonMax = min(lonMax, 179.5)
        // Snap to a 0.1° raster for cache friendliness.
        latMin = (latMin * 10).rounded(.down) / 10
        latMax = (latMax * 10).rounded(.up) / 10
        lonMin = (lonMin * 10).rounded(.down) / 10
        lonMax = (lonMax * 10).rounded(.up) / 10
        return Bounds(latMin: latMin, latMax: latMax, lonMin: lonMin, lonMax: lonMax)
    }

    private func fetch(_ request: GridRequest) async throws -> WeatherGrid? {
        let layer = request.layer
        guard let scalarVar = layer.scalarVariable(altitude: request.altitude) else { return nil }
        let directionVar = layer.directionVariable(altitude: request.altitude)

        let bounds = paddedBounds(request.region)
        let cols = 18, rows = 13

        var lats: [String] = []
        var lons: [String] = []
        lats.reserveCapacity(rows * cols)
        lons.reserveCapacity(rows * cols)
        for row in 0..<rows {
            let lat = bounds.latMin + (bounds.latMax - bounds.latMin) * Double(row) / Double(rows - 1)
            for col in 0..<cols {
                let lon = bounds.lonMin + (bounds.lonMax - bounds.lonMin) * Double(col) / Double(cols - 1)
                lats.append(String(format: "%.3f", lat))
                lons.append(String(format: "%.3f", lon))
            }
        }

        var variables = [scalarVar]
        if let directionVar { variables.append(directionVar) }

        var components: URLComponents
        switch layer.source {
        case .marine:
            components = URLComponents(string: "https://marine-api.open-meteo.com/v1/marine")!
            components.queryItems = commonItems(lats: lats, lons: lons, variables: variables)
                + [.init(name: "forecast_days", value: "5")]
        case .airQuality:
            components = URLComponents(string: "https://air-quality-api.open-meteo.com/v1/air-quality")!
            components.queryItems = commonItems(lats: lats, lons: lons, variables: variables)
                + [.init(name: "forecast_days", value: "3")]
        default:
            components = URLComponents(string: "https://api.open-meteo.com/v1/forecast")!
            components.queryItems = commonItems(lats: lats, lons: lons, variables: variables) + [
                .init(name: "models", value: request.model.rawValue),
                .init(name: "wind_speed_unit", value: "ms"),
                .init(name: "forecast_days", value: "7"),
                .init(name: "temporal_resolution", value: "hourly_3"),
            ]
        }

        let data = try await OpenMeteoClient.shared.fetchData(components)

        // Multi-location requests return a JSON array; single location an object.
        let decoder = JSONDecoder()
        let responses: [OMResponse]
        if let array = try? decoder.decode([OMResponse].self, from: data) {
            responses = array
        } else {
            responses = [try decoder.decode(OMResponse.self, from: data)]
        }
        guard responses.count == rows * cols,
              let timeBlock = responses.first(where: { $0.hourly != nil })?.hourly else {
            return nil
        }

        let times = timeBlock.dates
        let stepCount = times.count
        var scalar = [[Float]](repeating: [Float](repeating: .nan, count: rows * cols), count: stepCount)
        var uField: [[Float]]?
        var vField: [[Float]]?
        if layer.isVectorField {
            uField = scalar
            vField = scalar
        }

        for (pointIndex, response) in responses.enumerated() {
            guard let hourly = response.hourly else { continue }
            let values = hourly.numeric[scalarVar] ?? []
            let directions = directionVar.flatMap { hourly.numeric[$0] } ?? []
            for t in 0..<min(stepCount, values.count) {
                guard let raw = values[t] else { continue }
                var si = Float(layer.toSI(raw))
                if layer == .rainAccumulation, t > 0, !scalar[t - 1][pointIndex].isNaN {
                    si += scalar[t - 1][pointIndex]
                }
                scalar[t][pointIndex] = si
                if layer.isVectorField, t < directions.count, let dirDeg = directions[t] {
                    let dir = dirDeg * .pi / 180
                    let speed = Double(si)
                    // Meteorological convention: direction the flow comes FROM —
                    // except ocean currents, which report the direction they flow TO.
                    let sign: Double = (layer == .currents) ? 1 : -1
                    uField?[t][pointIndex] = Float(sign * speed * sin(dir))
                    vField?[t][pointIndex] = Float(sign * speed * cos(dir))
                }
            }
        }

        return WeatherGrid(
            layer: layer,
            latMin: bounds.latMin, latMax: bounds.latMax,
            lonMin: bounds.lonMin, lonMax: bounds.lonMax,
            rows: rows, cols: cols,
            times: times,
            scalar: scalar,
            u: uField, v: vField
        )
    }

    private func commonItems(lats: [String], lons: [String], variables: [String]) -> [URLQueryItem] {
        [
            .init(name: "latitude", value: lats.joined(separator: ",")),
            .init(name: "longitude", value: lons.joined(separator: ",")),
            .init(name: "hourly", value: variables.joined(separator: ",")),
            .init(name: "timeformat", value: "unixtime"),
        ]
    }
}
