import Foundation
import MapKit
import UIKit

// Gerçek navigasyon: Apple Maps (native) ve Google Maps (evrensel link).
enum NavApp {
    /// Apple Maps'te sürüş rotası başlat (mevcut konumdan hedefe)
    static func openAppleMaps(to stop: Stop) {
        let dest = MKMapItem(placemark: MKPlacemark(coordinate: stop.coordinate))
        dest.name = stop.name
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
