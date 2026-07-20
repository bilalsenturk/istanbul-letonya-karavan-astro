import SwiftUI

@main
struct KaravanApp: App {
    @StateObject private var store = TripStore()
    @StateObject private var locationManager = LocationManager()
    @StateObject private var weather = WeatherService()
    @StateObject private var expenses = ExpenseStore()
    @StateObject private var routeStore = RouteStore()
    @StateObject private var navProgress = NavProgressStore()
    @StateObject private var altimeter = AltimeterService()
    @StateObject private var plan = TripPlanStore()
    @StateObject private var gallery = GalleryStore()
    @Environment(\.scenePhase) private var scenePhase

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
                .environmentObject(altimeter)
                .environmentObject(plan)
                .environmentObject(gallery)
                .preferredColorScheme(.dark)
                .task {
                    await NotificationManager.shared.requestAuthorization()
                    weather.notifier = NotificationManager.shared
                    locationManager.nav = navProgress
                    locationManager.trip = store
                    locationManager.routeStore = routeStore
                    altimeter.start()
                    await gallery.load()
                    await AnnouncementAudio.shared.loadManifest()   // kayıtlı sesler (varsa)
                    // Araç (CarPlay/araç ses yolu) bağlanınca: kaptan esprisi + sıradaki durak + hadi başlat
                    AnnouncementService.shared.onCarConnected = {
                        AnnouncementService.shared.announceDeparture(nextStop: navProgress.nextStop?.name)
                    }
                    if let stops = store.trip?.stops {
                        locationManager.startMonitoringStops(stops)
                    }
                    // Kalkış tarihi kullanıcı düzenlemesiyle değişebilir → tek kaynak: plan
                    store.effectiveDeparture = { [weak store] in plan.departure(store?.trip) }
                    applyPlanCascade()
                    plan.onChange = { _ in applyPlanCascade() }
                    BackgroundWeather.schedule()
                }
                .onChange(of: store.lastRefreshed) { _, _ in
                    applyPlanCascade()   // uzak veri geldi → takvimi yeniden yayınla
                }
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active {
                        expenses.reload()                 // Siri arka planda eklemiş olabilir
                        locationManager.applyPowerMode()  // termal/güç durumu değişmiş olabilir
                    }
                }
        }
        // Arka planda periyodik hava kontrolü (best-effort; iOS zamanlar).
        .backgroundTask(.appRefresh(BackgroundWeather.taskId)) {
            await BackgroundWeather.run()
        }
    }

    /// Kalkış/plan değiştiğinde tek noktadan kaskat:
    /// bildirimleri yeniden kur → widget snapshot'ını tazele → widget'ları yenile.
    @MainActor
    private func applyPlanCascade() {
        let departure = plan.departure(store.trip)
        NotificationManager.shared.scheduleDepartureReminders(departure: departure)
        store.writeSnapshot()
        LiveActivityManager.shared.reloadWidgetsThrottled()
        PlanPublisher.publish(trip: store.trip, edits: plan.edits)   // siteye yansıt
    }
}
