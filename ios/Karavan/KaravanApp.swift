import SwiftUI

@main
struct KaravanApp: App {
    @StateObject private var store = TripStore()
    @StateObject private var locationManager = LocationManager()
    @StateObject private var weather = WeatherService()

    var body: some Scene {
        WindowGroup {
            DashboardView()
                .environmentObject(store)
                .environmentObject(locationManager)
                .environmentObject(weather)
                .preferredColorScheme(.dark)
        }
    }
}
