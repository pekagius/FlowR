import Foundation
import CoreLocation

// MARK: - Tropical storms (NHC hurricane tracker)

struct TropicalStorm: Identifiable {
    let id: String
    let name: String
    let classification: String   // e.g. "HU", "TS", "TD"
    let intensityKt: Double?     // max sustained wind in knots
    let pressureMb: Double?
    let latitude: Double
    let longitude: Double
    let movementDir: Double?
    let movementSpeedKt: Double?
    let lastUpdate: String?

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    var classificationText: String {
        switch classification.uppercased() {
        case "HU", "MH": return "Hurricane"
        case "TS": return "Tropical Storm"
        case "TD": return "Tropical Depression"
        case "STD": return "Subtropical Depression"
        case "STS": return "Subtropical Storm"
        case "PTC": return "Post-tropical Cyclone"
        default: return classification
        }
    }
}

// MARK: - Weather alerts (NWS, US coverage)

struct WeatherWarning: Identifiable {
    let id: String
    let event: String
    let severity: String
    let headline: String
    let description: String
    let areaDesc: String
    let effective: Date?
    let expires: Date?

    var severityRank: Int {
        switch severity.lowercased() {
        case "extreme": return 4
        case "severe": return 3
        case "moderate": return 2
        case "minor": return 1
        default: return 0
        }
    }
}

// MARK: - Webcams (Windy Webcams API, optional key)

struct Webcam: Identifiable, Decodable {
    let webcamId: Int
    let title: String
    let status: String?
    let viewCount: Int?
    let images: WebcamImages?
    let location: WebcamLocation?

    var id: Int { webcamId }

    struct WebcamImages: Decodable {
        let current: WebcamImageSet?
    }
    struct WebcamImageSet: Decodable {
        let preview: String?
        let thumbnail: String?
    }
    struct WebcamLocation: Decodable {
        let city: String?
        let country: String?
        let latitude: Double?
        let longitude: Double?
    }
}
