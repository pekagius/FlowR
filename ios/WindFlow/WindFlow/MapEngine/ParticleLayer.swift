import Foundation
import SwiftUI
import MapKit

/// Snapshot of the map's viewport used to convert between screen points and
/// coordinates without touching MKMapView from the render loop.
/// Valid because map rotation and pitch are disabled.
struct MapProjection: Equatable {
    let originX: Double
    let originY: Double
    let mapWidth: Double
    let mapHeight: Double
    let size: CGSize

    static let zero = MapProjection(originX: 0, originY: 1, mapWidth: 1, mapHeight: 1, size: .zero)

    init(originX: Double, originY: Double, mapWidth: Double, mapHeight: Double, size: CGSize) {
        self.originX = originX
        self.originY = originY
        self.mapWidth = mapWidth
        self.mapHeight = mapHeight
        self.size = size
    }

    init(mapView: MKMapView) {
        let rect = mapView.visibleMapRect
        self.init(originX: rect.origin.x, originY: rect.origin.y,
                  mapWidth: rect.width, mapHeight: rect.height,
                  size: mapView.bounds.size)
    }

    func coordinate(for point: CGPoint) -> CLLocationCoordinate2D {
        guard size.width > 0, size.height > 0 else { return .init(latitude: 0, longitude: 0) }
        let mapPoint = MKMapPoint(
            x: originX + Double(point.x) / Double(size.width) * mapWidth,
            y: originY + Double(point.y) / Double(size.height) * mapHeight
        )
        return mapPoint.coordinate
    }

    var metersPerScreenPoint: Double {
        guard size.width > 0 else { return 1 }
        let centerLat = MKMapPoint(x: originX + mapWidth / 2, y: originY + mapHeight / 2).coordinate.latitude
        return MKMetersPerMapPointAtLatitude(centerLat) * mapWidth / Double(size.width)
    }
}

/// CPU particle advection for the animated flow layer (wind / waves / currents).
final class ParticleEngine {
    struct Particle {
        var position: CGPoint
        var age: Int
        var maxAge: Int
        var trail: [CGPoint]
    }

    private(set) var particles: [Particle] = []
    private var lastStep: TimeInterval = 0
    private var generator = SystemRandomNumberGenerator()

    func reset() {
        particles.removeAll()
        lastStep = 0
    }

    private func spawn(in size: CGSize) -> Particle {
        let p = CGPoint(
            x: CGFloat.random(in: 0...max(size.width, 1), using: &generator),
            y: CGFloat.random(in: 0...max(size.height, 1), using: &generator)
        )
        return Particle(position: p, age: 0, maxAge: Int.random(in: 60...180, using: &generator), trail: [p])
    }

    /// Advances the simulation and returns the particles to draw.
    func step(now: TimeInterval, grid: WeatherGrid, projection: MapProjection,
              fractionalTime: Double, targetCount: Int) -> [Particle] {
        let size = projection.size
        guard size.width > 4, size.height > 4 else { return [] }

        let dt = lastStep == 0 ? 1.0 / 60.0 : min(now - lastStep, 1.0 / 20.0)
        lastStep = now

        while particles.count < targetCount { particles.append(spawn(in: size)) }
        if particles.count > targetCount { particles.removeLast(particles.count - targetCount) }

        // Visual exaggeration: px per (m/s) per second, mildly zoom-adaptive.
        let mpp = projection.metersPerScreenPoint
        let base = 3.2 * pow(1500.0 / max(mpp, 1), 0.12)

        for i in particles.indices {
            var p = particles[i]
            let coord = projection.coordinate(for: p.position)
            let sample = grid.sampleVector(lat: coord.latitude, lon: coord.longitude, at: fractionalTime)

            var dead = false
            if let (u, v) = sample {
                p.position.x += CGFloat(Double(u) * base * dt)
                p.position.y -= CGFloat(Double(v) * base * dt)   // screen y grows south
            } else {
                dead = true
            }
            p.age += 1
            if p.age > p.maxAge
                || p.position.x < -20 || p.position.x > size.width + 20
                || p.position.y < -20 || p.position.y > size.height + 20 {
                dead = true
            }

            if dead {
                p = spawn(in: size)
            } else {
                p.trail.append(p.position)
                if p.trail.count > 6 { p.trail.removeFirst(p.trail.count - 6) }
            }
            particles[i] = p
        }
        return particles
    }
}

/// SwiftUI layer that draws the particles over the map.
struct ParticleCanvas: View {
    let grid: WeatherGrid?
    let projection: MapProjection
    let fractionalTime: Double
    let density: Double
    let enabled: Bool

    @State private var engine = ParticleEngine()

    var body: some View {
        if enabled, let grid, grid.u != nil {
            TimelineView(.animation) { timeline in
                Canvas { context, size in
                    let count = Int(600 * density)
                    let now = timeline.date.timeIntervalSinceReferenceDate
                    let particles = engine.step(
                        now: now, grid: grid, projection: projection,
                        fractionalTime: fractionalTime, targetCount: count
                    )
                    for particle in particles {
                        guard particle.trail.count > 1 else { continue }
                        var path = Path()
                        path.move(to: particle.trail[0])
                        for point in particle.trail.dropFirst() { path.addLine(to: point) }
                        let fade = 1.0 - Double(particle.age) / Double(max(particle.maxAge, 1))
                        context.stroke(
                            path,
                            with: .color(.white.opacity(0.10 + 0.45 * fade)),
                            style: StrokeStyle(lineWidth: 1.4, lineCap: .round, lineJoin: .round)
                        )
                    }
                }
            }
            .allowsHitTesting(false)
            .id(grid.layer)   // restart particles when switching layers
        }
    }
}
