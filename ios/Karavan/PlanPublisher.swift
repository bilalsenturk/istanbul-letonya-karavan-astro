import Foundation

// Hesaplanmış takvimi web'e yayınlar. Tarih türetme logic'i yalnızca TripPlanner'da
// yaşar; site sonucu gösterir. Kalkış/gün düzenlemesi değişince çağrılır.
enum PlanPublisher {
    private static var lastPayload: String?

    @MainActor
    static func publish(trip: TripData?, edits: TripEdits) {
        guard let trip, let url = Config.planPostURL else { return }

        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime]

        let departure = TripPlanner.departure(trip: trip, edits: edits)
        let days = TripPlanner.days(trip: trip, edits: edits)

        let payload: [String: Any] = [
            "departureAt": iso.string(from: departure),
            "arrivalAt": TripPlanner.arrivalDate(trip: trip, edits: edits).map { iso.string(from: $0) } ?? "",
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

        // Aynı takvimi tekrar tekrar göndermeyelim.
        let signature = String(data: body, encoding: .utf8) ?? ""
        guard signature != lastPayload else { return }
        lastPayload = signature

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(Config.livePostSecret, forHTTPHeaderField: "x-live-secret")
        req.httpBody = body
        req.timeoutInterval = 10

        Task { _ = try? await URLSession.shared.data(for: req) }
    }
}
