import Foundation

// Hesaplanmış takvimi web'e yayınlar. Tarih türetme logic'i yalnızca TripPlanner'da
// yaşar; site sonucu gösterir. Kalkış/gün düzenlemesi değişince çağrılır.
enum PlanPublisher {
    @MainActor
    static func publish(trip: TripData?, edits: TripEdits) {
        guard let trip, let url = Config.planPostURL else { return }

        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime]

        let departure = TripPlanner.departure(trip: trip, edits: edits)
        let days = TripPlanner.days(trip: trip, edits: edits)

        // Gün listesi boşken varış bilinmez: "" yerine null gönder.
        let arrival: Any
        if let arrivalDate = TripPlanner.arrivalDate(trip: trip, edits: edits) {
            arrival = iso.string(from: arrivalDate)
        } else {
            arrival = NSNull()
        }

        let payload: [String: Any] = [
            "departureAt": iso.string(from: departure),
            "arrivalAt": arrival,
            "totalDays": TripPlanner.totalDays(trip: trip, edits: edits),
            "days": days.map { d in
                [
                    "slug": d.base.slug,
                    "date": iso.string(from: d.date),
                    "label": d.dateText,
                    "origin": d.origin,
                    "destination": d.destination,
                    "restDay": d.isRestDay,
                    "dayCount": d.dayCount,
                ]
            },
        ]

        guard let body = try? JSONSerialization.data(withJSONObject: payload) else { return }

        // Aynı takvimi tekrar tekrar göndermeyelim; başarısız kalırsa outbox saklar.
        let signature = String(data: body, encoding: .utf8) ?? ""
        PublishOutbox.shared.enqueue(key: "plan", url: url, body: body, signature: signature)
    }
}
