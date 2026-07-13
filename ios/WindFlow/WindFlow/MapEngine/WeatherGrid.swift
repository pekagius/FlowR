import Foundation
import CoreLocation

/// A regular lat/lon grid of forecast values over time, fetched for the
/// visible map region. Backs both the heatmap overlay and the particle layer.
struct WeatherGrid {
    let id = UUID()
    let layer: WeatherLayer
    let latMin: Double, latMax: Double
    let lonMin: Double, lonMax: Double
    let rows: Int, cols: Int
    let times: [Date]

    /// scalar[t][row * cols + col] — SI units, .nan where missing (e.g. marine on land)
    let scalar: [[Float]]
    /// vector components (m/s eastward / northward), only for vector layers
    let u: [[Float]]?
    let v: [[Float]]?

    var pointCount: Int { rows * cols }

    var timeRange: ClosedRange<Date>? {
        guard let first = times.first, let last = times.last else { return nil }
        return first...last
    }

    func contains(lat: Double, lon: Double) -> Bool {
        lat >= latMin && lat <= latMax && lon >= lonMin && lon <= lonMax
    }

    /// Fractional time index for a date (clamped).
    func timeIndex(for date: Date) -> Double {
        guard times.count > 1 else { return 0 }
        let t0 = times[0].timeIntervalSince1970
        let dt = times[1].timeIntervalSince1970 - t0
        guard dt > 0 else { return 0 }
        let raw = (date.timeIntervalSince1970 - t0) / dt
        return min(max(raw, 0), Double(times.count - 1))
    }

    /// Bilinear sample of one time slice.
    private func bilinear(_ field: [Float], lat: Double, lon: Double) -> Float {
        guard rows > 1, cols > 1 else { return field.first ?? .nan }
        let fy = (lat - latMin) / (latMax - latMin) * Double(rows - 1)
        let fx = (lon - lonMin) / (lonMax - lonMin) * Double(cols - 1)
        guard fx >= 0, fy >= 0, fx <= Double(cols - 1), fy <= Double(rows - 1) else { return .nan }
        let x0 = min(Int(fx), cols - 2), y0 = min(Int(fy), rows - 2)
        let tx = Float(fx - Double(x0)), ty = Float(fy - Double(y0))
        let i00 = field[y0 * cols + x0]
        let i10 = field[y0 * cols + x0 + 1]
        let i01 = field[(y0 + 1) * cols + x0]
        let i11 = field[(y0 + 1) * cols + x0 + 1]
        if i00.isNaN || i10.isNaN || i01.isNaN || i11.isNaN {
            // fall back to nearest non-NaN neighbor
            let nearest = field[(ty < 0.5 ? y0 : y0 + 1) * cols + (tx < 0.5 ? x0 : x0 + 1)]
            return nearest
        }
        let top = i00 + (i10 - i00) * tx
        let bottom = i01 + (i11 - i01) * tx
        return top + (bottom - top) * ty
    }

    /// Time-interpolated scalar sample.
    func sampleScalar(lat: Double, lon: Double, at fractionalTime: Double) -> Float {
        guard !scalar.isEmpty else { return .nan }
        let t0 = min(Int(fractionalTime), scalar.count - 1)
        let a = bilinear(scalar[t0], lat: lat, lon: lon)
        let t1 = min(t0 + 1, scalar.count - 1)
        if t1 == t0 { return a }
        let b = bilinear(scalar[t1], lat: lat, lon: lon)
        if a.isNaN { return b }
        if b.isNaN { return a }
        let frac = Float(fractionalTime - Double(t0))
        return a + (b - a) * frac
    }

    /// Time-interpolated vector sample (u east, v north) in m/s.
    func sampleVector(lat: Double, lon: Double, at fractionalTime: Double) -> (Float, Float)? {
        guard let u, let v, !u.isEmpty else { return nil }
        let t0 = min(Int(fractionalTime), u.count - 1)
        let t1 = min(t0 + 1, u.count - 1)
        let frac = Float(fractionalTime - Double(t0))
        let ua = bilinear(u[t0], lat: lat, lon: lon)
        let va = bilinear(v[t0], lat: lat, lon: lon)
        if ua.isNaN || va.isNaN { return nil }
        if t1 == t0 { return (ua, va) }
        let ub = bilinear(u[t1], lat: lat, lon: lon)
        let vb = bilinear(v[t1], lat: lat, lon: lon)
        if ub.isNaN || vb.isNaN { return (ua, va) }
        return (ua + (ub - ua) * frac, va + (vb - va) * frac)
    }
}
