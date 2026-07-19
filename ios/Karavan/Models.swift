import Foundation
import CoreLocation

// tripData.json'un app'in kullandığı alt kümesi.
// Codable fazladan JSON alanlarını yok sayar; web tarafı genişlese de app kırılmaz.

struct TripData: Codable {
    let departureAt: String
    let totalKm: Int
    let totalBudget: Budget
    let stops: [Stop]
    let days: [DayPlan]
    let checklist: [ChecklistItem]

    var departureDate: Date? {
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime]
        return iso.date(from: departureAt)
    }
}

struct Budget: Codable {
    let fuel: String
    let total: String
}

struct Stop: Codable, Identifiable {
    let id: String
    let name: String
    let country: String
    let lat: Double
    let lng: Double

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: lat, longitude: lng)
    }

    var flag: String {
        switch country {
        case "Türkiye": return "🇹🇷"
        case "Bulgaristan": return "🇧🇬"
        case "Romanya": return "🇷🇴"
        case "Macaristan": return "🇭🇺"
        case "Polonya": return "🇵🇱"
        case "Letonya": return "🇱🇻"
        case "Litvanya": return "🇱🇹"
        default: return "📍"
        }
    }
}

struct DayPlan: Codable, Identifiable {
    let slug: String
    let date: String
    let origin: String
    let destination: String
    let distanceKm: String
    let duration: String
    let fuel: String
    let risks: [String]
    let opportunities: [String]
    let contingencies: [String]
    let camp: Camp

    var id: String { slug }
    var isRestDay: Bool { origin == destination }
}

struct Camp: Codable {
    let name: String
    let place: String
    let note: String
    let link: String
}

struct ChecklistItem: Codable, Identifiable {
    let id: String
    let due: String
    let task: String
}
