import SwiftUI

@main
struct KaravanApp: App {
    @StateObject private var store = TripStore()
    @StateObject private var locationManager = LocationManager()
    @StateObject private var weather = WeatherService()
    @StateObject private var expenses = ExpenseStore()
    @StateObject private var routeStore = RouteStore()
    @StateObject private var navProgress = NavProgressStore()

    init() {
        // Kamp görsellerini tek sefer indir, tekrar kullan (hız + veri tasarrufu).
        URLCache.shared = URLCache(memoryCapacity: 32 << 20, diskCapacity: 128 << 20)
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(store)
                .environmentObject(locationManager)
                .environmentObject(weather)
                .environmentObject(expenses)
                .environmentObject(routeStore)
                .environmentObject(navProgress)
                .preferredColorScheme(.dark)
                .task {
                    await NotificationManager.shared.requestAuthorization()
                    weather.notifier = NotificationManager.shared
                    if let departure = store.trip?.departureDate {
                        NotificationManager.shared.scheduleDepartureReminders(departure: departure)
                    }
                    BackgroundWeather.schedule()
                }
        }
        // Arka planda periyodik hava kontrolü (best-effort; iOS zamanlar).
        .backgroundTask(.appRefresh(BackgroundWeather.taskId)) {
            await BackgroundWeather.run()
        }
    }
}
