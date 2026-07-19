import ActivityKit
import Foundation

// Sürüş Live Activity'sinin sözleşmesi — app başlatır/günceller, widget çizer.
struct TripActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var remainingKm: Int
        var remainingMin: Int
        var speedKmh: Int
        var progress: Double      // 0…1 (etap ilerlemesi)
    }

    // Etap boyunca sabit
    var nextStop: String
    var nextCode: String          // ülke kodu rozeti (BG, HU…)
}
