import Foundation
import MapKit
import UIKit

// Gerçek navigasyon: Apple Maps (native) ve Google Maps (evrensel link).
enum NavApp {
    /// Apple Maps'te sürüş rotası başlat (mevcut konumdan hedefe)
    static func openAppleMaps(to stop: Stop) {
        openAppleMaps(toCoordinate: stop.coordinate, name: stop.name)
    }

    /// Apple Maps'te herhangi bir koordinata sürüş rotası (Apple Haritalar POI sonucu vb.)
    static func openAppleMaps(toCoordinate coordinate: CLLocationCoordinate2D, name: String) {
        let dest = MKMapItem(placemark: MKPlacemark(coordinate: coordinate))
        dest.name = name
        MKMapItem.openMaps(
            with: [MKMapItem.forCurrentLocation(), dest],
            launchOptions: [MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeDriving]
        )
    }

    /// Google Maps'te sürüş rotası (app kuruluysa app, değilse tarayıcı)
    static func openGoogleMaps(to stop: Stop) {
        var comps = URLComponents(string: "https://www.google.com/maps/dir/")!
        comps.queryItems = [
            URLQueryItem(name: "api", value: "1"),
            URLQueryItem(name: "destination", value: "\(stop.lat),\(stop.lng)"),
            URLQueryItem(name: "travelmode", value: "driving"),
        ]
        if let url = comps.url {
            UIApplication.shared.open(url)
        }
    }
}
