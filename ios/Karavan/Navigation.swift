import Foundation
import MapKit
import UIKit
import SwiftUI

enum AppTab: Hashable {
    case dashboard
    case plan
    case journal
    case tools
}

@MainActor
final class AppNavigation: ObservableObject {
    static let shared = AppNavigation()

    @Published var selectedTab: AppTab = .dashboard

    private init() {
        #if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains("-ui-preview-routes") { selectedTab = .plan }
        if arguments.contains("-ui-preview-plan") { selectedTab = .plan }
        if arguments.contains("-ui-preview-map") { selectedTab = .plan }
        if arguments.contains("-ui-preview-dashboard") { selectedTab = .dashboard }
        if arguments.contains("-ui-preview-journal") { selectedTab = .journal }
        if arguments.contains("-ui-preview-tools") { selectedTab = .tools }
        #endif
    }
}

// Gerçek navigasyon: Apple Maps (native) ve Google Maps (evrensel link).
enum NavApp {
    /// Apple Maps'te sürüş rotası başlat (mevcut konumdan hedefe)
    @MainActor
    static func openAppleMaps(to stop: Stop) {
        // Rotayı yalnızca SÜRÜCÜ başlatır — LegLauncher'ı atlayan çağıranlar
        // (durak keşfi, gün detayı, "arabada aç") için son kontrol noktası.
        guard RoleStore.shared.isDriver else { return }
        openAppleMaps(toCoordinate: stop.coordinate, name: stop.name)
    }

    /// Apple Maps'te herhangi bir koordinata sürüş rotası (Apple Haritalar POI sonucu vb.)
    @MainActor
    static func openAppleMaps(toCoordinate coordinate: CLLocationCoordinate2D, name: String) {
        // POI'ye adım adım navigasyon da "rotayı başlat"maktır → yalnızca SÜRÜCÜ
        // (NavApp.openAppleMaps(to:) ile aynı kilit; yalnızca haritada gösterme serbest).
        guard RoleStore.shared.isDriver else { return }
        let dest = MKMapItem(placemark: MKPlacemark(coordinate: coordinate))
        dest.name = name
        MKMapItem.openMaps(
            with: [MKMapItem.forCurrentLocation(), dest],
            launchOptions: [MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeDriving]
        )
    }

    /// Apple Maps'te yeri gösterir; adım adım navigasyon başlatmaz.
    @MainActor
    static func showInAppleMaps(coordinate: CLLocationCoordinate2D, name: String) {
        let item = MKMapItem(placemark: MKPlacemark(coordinate: coordinate))
        item.name = name
        item.openInMaps()
    }

    @MainActor
    static func showInAppleMaps(stop: Stop) {
        showInAppleMaps(coordinate: stop.coordinate, name: stop.name)
    }

    /// Google Maps'te sürüş rotası (app kuruluysa app, değilse tarayıcı)
    @MainActor
    static func openGoogleMaps(to stop: Stop) {
        // Rotayı yalnızca SÜRÜCÜ başlatır (NavApp.openAppleMaps(to:) ile aynı kilit).
        guard RoleStore.shared.isDriver else { return }
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
