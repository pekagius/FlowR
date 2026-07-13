import Foundation
import MapKit
import UIKit

/// Semi-transparent color-field overlay rendered from a `WeatherGrid`,
/// like Windy's layer heatmaps.
final class HeatmapOverlay: NSObject, MKOverlay {
    let grid: WeatherGrid
    let scale: ColorScale
    let alpha: CGFloat
    /// Fractional index into grid.times; mutated while scrubbing the timeline.
    /// Written on the main thread; renderer reads a snapshot per draw pass.
    var fractionalTime: Double

    let boundingMapRect: MKMapRect
    let coordinate: CLLocationCoordinate2D

    init(grid: WeatherGrid, alpha: CGFloat, fractionalTime: Double) {
        self.grid = grid
        self.scale = grid.layer.colorScale
        self.alpha = alpha
        self.fractionalTime = fractionalTime

        let topLeft = MKMapPoint(CLLocationCoordinate2D(latitude: grid.latMax, longitude: grid.lonMin))
        let bottomRight = MKMapPoint(CLLocationCoordinate2D(latitude: grid.latMin, longitude: grid.lonMax))
        boundingMapRect = MKMapRect(
            x: topLeft.x, y: topLeft.y,
            width: bottomRight.x - topLeft.x,
            height: bottomRight.y - topLeft.y
        )
        coordinate = CLLocationCoordinate2D(
            latitude: (grid.latMin + grid.latMax) / 2,
            longitude: (grid.lonMin + grid.lonMax) / 2
        )
        super.init()
    }
}

final class HeatmapRenderer: MKOverlayRenderer {
    private var heatmap: HeatmapOverlay? { overlay as? HeatmapOverlay }

    override func canDraw(_ mapRect: MKMapRect, zoomScale: MKZoomScale) -> Bool {
        heatmap != nil
    }

    override func draw(_ mapRect: MKMapRect, zoomScale: MKZoomScale, in context: CGContext) {
        guard let heatmap else { return }
        let grid = heatmap.grid
        let time = heatmap.fractionalTime
        let scale = heatmap.scale
        let alpha = heatmap.alpha

        let size = 64
        var pixels = [UInt8](repeating: 0, count: size * size * 4)

        // lat depends only on pixel row, lon only on pixel column.
        var lats = [Double](repeating: 0, count: size)
        var lons = [Double](repeating: 0, count: size)
        for i in 0..<size {
            let f = (Double(i) + 0.5) / Double(size)
            lats[i] = MKMapPoint(x: mapRect.midX, y: mapRect.origin.y + f * mapRect.height).coordinate.latitude
            lons[i] = MKMapPoint(x: mapRect.origin.x + f * mapRect.width, y: mapRect.midY).coordinate.longitude
        }

        for row in 0..<size {
            let lat = lats[row]
            for col in 0..<size {
                let value = grid.sampleScalar(lat: lat, lon: lons[col], at: time)
                guard !value.isNaN else { continue }
                let (r, g, b) = scale.components(for: Double(value))
                let a = alpha
                let offset = (row * size + col) * 4
                // premultiplied alpha
                pixels[offset] = UInt8(max(0, min(255, r * a * 255)))
                pixels[offset + 1] = UInt8(max(0, min(255, g * a * 255)))
                pixels[offset + 2] = UInt8(max(0, min(255, b * a * 255)))
                pixels[offset + 3] = UInt8(a * 255)
            }
        }

        guard let provider = CGDataProvider(data: Data(pixels) as CFData),
              let image = CGImage(
                width: size, height: size,
                bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: size * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                provider: provider, decode: nil, shouldInterpolate: true,
                intent: .defaultIntent
              ) else { return }

        let drawRect = rect(for: mapRect)
        context.saveGState()
        context.interpolationQuality = .low
        // CGContext draws images flipped; mirror vertically around the draw rect.
        context.translateBy(x: 0, y: drawRect.midY)
        context.scaleBy(x: 1, y: -1)
        context.translateBy(x: 0, y: -drawRect.midY)
        context.draw(image, in: drawRect)
        context.restoreGState()
    }
}
