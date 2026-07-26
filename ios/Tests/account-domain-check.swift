import Foundation

func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
    if condition() {
        print("  ✓ \(message)")
    } else {
        fputs("  ✗ \(message)\n", stderr)
        exit(1)
    }
}

@main
struct AccountDomainCheck {
    static func main() throws {
        print("\n=== Hesap rolleri ve rota özellikleri ===")
        let memberAccess = TripAccess(
            tripRole: .member,
            canEditTrip: false,
            canEditStops: true,
            canEditJournal: true,
            canManageMembers: false,
            canStartRoute: false,
            canDeleteTrip: false
        )
        expect(memberAccess.canEditStops, "üye durakları düzenleyebilir")
        expect(!memberAccess.canManageMembers, "üye, üyeleri yönetemez")
        expect(TripFeatures.standard.latvian == false, "standart rotada Letonca gizli")
        expect(TripFeatures.kuzey.latvian, "Kuzey rotasında Letonca görünür")

        let payload = """
        {
          "id":"trip-1",
          "name":"Balkan Yazı",
          "kind":"standard",
          "transportMode":"walking",
          "revision":3,
          "createdAt":"2026-07-26T08:00:00Z",
          "updatedAt":"2026-07-26T08:10:00Z",
          "stops":[
            {"id":"a","name":"İstanbul","lat":41.01,"lng":28.97,"order":0},
            {"id":"b","name":"Sofya","lat":42.69,"lng":23.32,"order":1,"note":"Kamp","arrivalTarget":{"id":"campuccino","name":"Camping Campuccino","kind":"campground","latitude":42.66,"longitude":23.28,"formattedAddress":"Sofia, Bulgaria","phone":"+359881234567","email":"hello@example.com","source":"appleMaps","updatedAt":"2026-07-26T07:01:00Z"},"stayDetails":{"checkIn":"2026-08-03T12:00:00Z","checkOut":"2026-08-05T08:00:00Z","reservationStatus":"awaitingReply"}}
          ],
          "members":[{"userId":"u1","role":"owner"}],
          "invites":[],
          "features":{"latvian":false,"kuzeyMusic":false,"publicTracking":false},
          "access":{"tripRole":"owner","canEditTrip":true,"canEditStops":true,"canEditJournal":true,"canManageMembers":true,"canStartRoute":true,"canDeleteTrip":true}
        }
        """.data(using: .utf8)!
        let trip = try JSONDecoder().decode(AccountTrip.self, from: payload)
        expect(trip.stops.map(\.name) == ["İstanbul", "Sofya"], "API durak sırasını korur")
        expect(trip.features == .standard, "API özellikleri doğru çözülür")
        expect(trip.transportMode == .walking, "API ulaşım türünü korur")
        expect(trip.stops[0].resolvedSource == .place, "eski duraklar yer olarak çözülür")
        expect(trip.stops[1].arrivalTarget?.name == "Camping Campuccino", "kesin hedef API'den çözülür")
        expect(trip.stops[1].stayDetails?.reservationStatus == .awaitingReply, "konaklama durumu korunur")

        print("\n=== Rota taslağı ===")
        var draft = RouteDraft(name: "Baltık Rotası")
        expect(draft.transportMode == .automobile, "yeni rota otomobille başlar")
        draft.transportMode = .flight
        expect(draft.transportMode == .flight, "rota ulaşım türü değiştirilebilir")
        expect(!draft.isSavable, "iki durak olmadan rota kaydedilmez")
        draft.add(RouteDraftStop(id: "a", name: "İstanbul", lat: 41.01, lng: 28.97))
        draft.add(RouteDraftStop(id: "b", name: "Sofya", lat: 42.69, lng: 23.32, note: "Gece"))
        expect(draft.isSavable, "ad ve iki durakla rota kaydedilir")
        draft.move(fromOffsets: IndexSet(integer: 1), toOffset: 0)
        expect(draft.stops.map(\.id) == ["b", "a"], "duraklar sürükleyerek sıralanır")
        expect(draft.stops[0].note == "Gece", "sıralama durak ayrıntısını korur")
        expect(draft.apiStops.map(\.order) == [0, 1], "API sırası taslaktan türetilir")

        print("\n=== Konumum başlangıcı ===")
        let currentLocation = RouteDraftStop.currentLocation(latitude: 41.021, longitude: 29.002)
        expect(currentLocation.source == .currentLocation, "Konumum özel rota noktasıdır")
        expect(currentLocation.name == "Konumum", "Konumum kullanıcıya doğru adla gösterilir")

        var liveDraft = RouteDraft(name: "Canlı başlangıç")
        liveDraft.add(currentLocation)
        liveDraft.add(RouteDraftStop(id: "destination", name: "Sofya", lat: 42.69, lng: 23.32))
        liveDraft.updateCurrentLocation(latitude: 41.044, longitude: 29.031)
        expect(liveDraft.stops[0].lat == 41.044 && liveDraft.stops[0].lng == 29.031,
               "GPS yenilenince Konumum noktası güncellenir")
        expect(liveDraft.apiStops[0].resolvedSource == .currentLocation,
               "Konumum türü API kaydında korunur")

        liveDraft.reverseStops()
        expect(liveDraft.stops.map(\.id) == ["destination", currentLocation.id],
               "başlangıç ve hedef ters çevrilebilir")
        liveDraft.replace(at: 0, with: RouteDraftStop(id: "riga", name: "Riga", lat: 56.95, lng: 24.1))
        expect(liveDraft.stops[0].name == "Riga", "rota satırından konum değiştirilebilir")

        let editableDraft = RouteDraft(trip: trip)
        expect(editableDraft.name == trip.name, "kayıtlı rota aynı editörde açılır")
        expect(editableDraft.transportMode == .walking, "editör ulaşım türünü korur")
        expect(editableDraft.stops.map(\.id) == ["a", "b"], "editör durak sırasını korur")
        expect(editableDraft.stops[1].arrivalTarget?.id == "campuccino", "editör kesin hedefi korur")
        expect(editableDraft.apiStops[1].arrivalTarget?.phone == "+359881234567", "API dönüşümü hedef iletişimini korur")

        print("\n✅ HESAP VE ROTA MODELİ KONTROLLERİ GEÇTİ")
    }
}
