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
    let min: Int?
    let max: Int?
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
        default: return "\u{1F4CD}"
        }
    }

    /// Bayrak emojisi simülatörde/bazı fontlarda "?" olarak çıkabildiği için
    /// arayüzde kullanılan güvenli ülke kodu (her yerde render olur).
    var code: String {
        switch country {
        case "Türkiye": return "TR"
        case "Bulgaristan": return "BG"
        case "Romanya": return "RO"
        case "Macaristan": return "HU"
        case "Polonya": return "PL"
        case "Letonya": return "LV"
        case "Litvanya": return "LT"
        default: return "•"
        }
    }
}

struct DayPlan: Codable, Identifiable {
    let slug: String
    /// JSON'daki sabit görüntü metni — YALNIZCA yedek. Gerçek tarih kalkıştan
    /// türetilir (bkz. TripPlanner), böylece kalkış değişince kaskatlanır.
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

    // Web verisinde zaten var olan, app'in şimdiye kadar kullanmadığı zengin alanlar
    let waypoints: [DayWaypoint]?
    let route: String?
    let trafficLabel: String?
    let cityCameras: [CityCamera]?

    var id: String { slug }
    var isRestDay: Bool { origin == destination }

    private enum CodingKeys: String, CodingKey {
        case slug, date, origin, destination, distanceKm, duration, fuel
        case risks, opportunities, contingencies, camp
        case waypoints = "stops"          // JSON'da "stops" = günün ara durakları
        case route, trafficLabel, cityCameras
    }
}

/// Gün içindeki ara durak (petrol, mola, market…)
struct DayWaypoint: Codable, Identifiable {
    let type: String
    let name: String
    let note: String?

    var id: String { "\(type)-\(name)" }

    var icon: String {
        let t = type.lowercased()
        if t.contains("petrol") || t.contains("yakıt") { return "fuelpump.fill" }
        if t.contains("mola") || t.contains("dinlen") { return "cup.and.saucer.fill" }
        if t.contains("market") || t.contains("alışveriş") { return "cart.fill" }
        if t.contains("sınır") { return "flag.2.crossed.fill" }
        if t.contains("kamp") { return "tent.fill" }
        return "mappin.circle.fill"
    }
}

struct CityCamera: Codable, Identifiable {
    let title: String
    let url: String

    var id: String { url }
}

struct Camp: Codable {
    let name: String
    let place: String
    let note: String
    let link: String
    let image: String?                      // "/assets/camps/x.webp" (opsiyonel)
    let alternatives: [CampAlternative]?    // şehir için diğer gerçek kamplar
}

struct CampAlternative: Codable, Identifiable {
    let name: String
    let place: String
    let link: String
    let note: String?
    let image: String?

    var id: String { name }
}

struct ChecklistItem: Codable, Identifiable {
    let id: String
    let due: String
    let task: String
}

extension TripData {
    /// "Bükreş Güney" gibi gün adlarını durak koordinatına eşler
    func stop(matching name: String) -> Stop? {
        stops.first { name.contains($0.name) || $0.name.contains(name) }
    }
}
