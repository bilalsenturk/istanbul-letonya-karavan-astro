import MapKit

// Apple Haritalar'ı bir VERİ KAYNAĞI olarak kullanır:
// • MKLocalSearch → durak çevresindeki gerçek kamp/yakıt/yemek/market/şarj yerleri
// • MKLookAroundScene → Apple'ın sokak seviyesi (Look Around) sahnesi
// Konum izni gerektirmez; verilen koordinatın çevresinde arar.

struct Place: Identifiable {
    let id = UUID()
    let name: String
    let coordinate: CLLocationCoordinate2D
    let subtitle: String?
    let url: URL?
    let phone: String?
    let category: MKPointOfInterestCategory?

    func distanceKm(from center: CLLocationCoordinate2D) -> Double {
        CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
            .distance(from: CLLocation(latitude: center.latitude, longitude: center.longitude)) / 1000
    }

    var mapItem: MKMapItem {
        let item = MKMapItem(placemark: MKPlacemark(coordinate: coordinate))
        item.name = name
        return item
    }
}

enum NearbyKind: String, CaseIterable, Identifiable {
    case camp, fuel, food, market, ev

    var id: String { rawValue }

    var label: String {
        switch self {
        case .camp: return "Kamp"
        case .fuel: return "Yakıt"
        case .food: return "Yemek"
        case .market: return "Market"
        case .ev: return "Şarj"
        }
    }

    var icon: String {
        switch self {
        case .camp: return "tent.fill"
        case .fuel: return "fuelpump.fill"
        case .food: return "fork.knife"
        case .market: return "cart.fill"
        case .ev: return "bolt.car.fill"
        }
    }

    var query: String {
        switch self {
        case .camp: return "camping caravan"
        case .fuel: return "gas station"
        case .food: return "restaurant"
        case .market: return "supermarket"
        case .ev: return "ev charging"
        }
    }

    var poiCategories: [MKPointOfInterestCategory] {
        switch self {
        case .camp: return [.campground]
        case .fuel: return [.gasStation]
        case .food: return [.restaurant, .cafe, .bakery]
        case .market: return [.foodMarket, .store]
        case .ev: return [.evCharger]
        }
    }
}

@MainActor
final class AppleMapsService: ObservableObject {
    /// Apple Haritalar POI veritabanında, merkez çevresinde arama.
    func searchNearby(_ kind: NearbyKind, around center: CLLocationCoordinate2D) async -> [Place] {
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = kind.query
        request.region = MKCoordinateRegion(
            center: center,
            latitudinalMeters: 30_000,
            longitudinalMeters: 30_000
        )
        request.pointOfInterestFilter = MKPointOfInterestFilter(including: kind.poiCategories)

        guard let response = try? await MKLocalSearch(request: request).start() else { return [] }

        return response.mapItems.prefix(12).map { item in
            Place(
                name: item.name ?? "—",
                coordinate: item.placemark.coordinate,
                subtitle: item.placemark.locality ?? item.placemark.title,
                url: item.url,
                phone: item.phoneNumber,
                category: item.pointOfInterestCategory
            )
        }
        .sorted { $0.distanceKm(from: center) < $1.distanceKm(from: center) }
    }

    /// Apple Look Around (sokak seviyesi) sahnesi — yoksa nil.
    func lookAroundScene(at coordinate: CLLocationCoordinate2D) async -> MKLookAroundScene? {
        let request = MKLookAroundSceneRequest(coordinate: coordinate)
        return try? await request.scene
    }
}
