import SwiftUI

@main
struct KaravanApp: App {
    @StateObject private var store = TripStore()
    // init'te KURULUR (aşağıda): SLOC/geofence uyanışında UI'siz süreçte bile
    // CLLocationManager delegate'i hazır olsun — @StateObject'in varsayılan
    // tembel kurulumu body ilk çizilene dek bekler, arka plan uyanışını kaçırır.
    @StateObject private var locationManager: LocationManager
    @StateObject private var weather = WeatherService()
    @StateObject private var expenses = ExpenseStore()
    @StateObject private var routeStore = RouteStore()
    @StateObject private var navProgress = NavProgressStore()
    @StateObject private var altimeter = AltimeterService()
    @StateObject private var plan = TripPlanStore()
    // Tek örnek: LegLauncher kilidi de aynı depoyu (RoleStore.shared) okur.
    @StateObject private var role = RoleStore.shared
    @StateObject private var gallery = GalleryStore()
    @StateObject private var roadFeed = RoadFeedService()
    @StateObject private var journal = JournalStore()
    @StateObject private var routeSession = RouteSession.shared
    @StateObject private var appNavigation = AppNavigation.shared
    @StateObject private var notifications = NotificationManager.shared
    @StateObject private var account = AccountSessionStore()
    @StateObject private var workspace = TripWorkspaceStore()
    @StateObject private var travelContent: TravelContentStore
    @ObservedObject private var departurePrompt = DeparturePrompt.shared
    @Environment(\.scenePhase) private var scenePhase
    @State private var appServicesStarted = false

    /// Kalkış saatini dakikada bir yokla (modal ±30 dk penceresinde açılır).
    private let departureTimer = Timer.publish(every: 60, on: .main, in: .common).autoconnect()

    init() {
        // Kamp görsellerini tek sefer indir, tekrar kullan (hız + veri tasarrufu).
        URLCache.shared = URLCache(memoryCapacity: 32 << 20, diskCapacity: 128 << 20)
        // Konum yöneticisini AÇILIŞTA kur (bkz. property'deki not).
        _locationManager = StateObject(wrappedValue: LocationManager())
        let contentURL = (Config.imageBaseURL ?? URL(string: "https://istanbul-letonya-karavan-astro.vercel.app")!)
            .appendingPathComponent("assets/travel-content.json")
        _travelContent = StateObject(wrappedValue: TravelContentStore(remoteURL: contentURL))
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
                .environmentObject(role)
                .environmentObject(gallery)
                .environmentObject(roadFeed)
                .environmentObject(journal)
                .environmentObject(routeSession)
                .environmentObject(appNavigation)
                .environmentObject(notifications)
                .environmentObject(account)
                .environmentObject(workspace)
                .environmentObject(travelContent)
                .preferredColorScheme(.dark)
                // Kalkış saati gelince ekrana düşen modal (kullanıcı isteği).
                .sheet(item: $departurePrompt.pendingStop) { stop in
                    DepartureModal(
                        stop: stop,
                        remainingKm: navProgress.remainingKm,
                        remainingTimeText: navProgress.remainingTimeText,
                        onOpenRoutes: {
                            appNavigation.selectedTab = .plan
                            departurePrompt.dismiss()
                        },
                        onSnooze: { departurePrompt.snooze() }
                    )
                }
                .onReceive(departureTimer) { _ in
                    checkDeparturePrompt()
                }
                .onChange(of: account.user?.id) { _, _ in
                    applyAccountWorkspace()
                }
                .onChange(of: workspace.selectedTrip) { _, _ in
                    applyAccountRole()
                    applyPublishedTripScope()
                }
                .onChange(of: account.initialTrips) { _, _ in
                    workspace.reconcile(trips: account.initialTrips)
                    applyAccountRole()
                    applyPublishedTripScope()
                }
                .task {
                    let contentLoad = Task { await travelContent.loadIfNeeded() }
                    await account.restore()
                    applyAccountWorkspace()
                    await startAppServices()
                    await contentLoad.value
                }
                .onChange(of: store.lastRefreshed) { _, _ in
                    applyPlanCascade()   // uzak veri geldi → takvimi yeniden yayınla
                    // Web verisinde duraklar değiştiyse geofence'leri tazele
                    // (startMonitoringStops eski bölgeleri silip yeniden kurar).
                    if let stops = store.trip?.stops {
                        routeSession.reconcile(stops: stops)
                        locationManager.startMonitoringStops(stops)
                    }
                }
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active {
                        expenses.reload()                 // Siri arka planda eklemiş olabilir
                        locationManager.applyPowerMode()  // termal/güç durumu değişmiş olabilir
                        checkDeparturePrompt()            // öne gelince kalkış penceresi açılmış olabilir
                        Task { await notifications.refreshAuthorization() }
                        Task { await journal.drainQueue() }
                        Task { await travelContent.refreshIfStale() }
                        // Öne gelince planı tazele: sahip cihazda tarih değişmiş olabilir.
                        Task {
                            await plan.syncFromWeb()
                            applyPlanCascade()
                        }
                    }
                    if phase == .background {
                        // Arka plana geçerken hava görevini yeniden planla —
                        // bekleyen isteğin görünür olması iOS'un görevi
                        // zamanlamasına yardımcı olur (best-effort).
                        BackgroundWeather.schedule()
                    }
                }
        }
        // Arka planda periyodik hava kontrolü (best-effort; iOS zamanlar).
        .backgroundTask(.appRefresh(BackgroundWeather.taskId)) {
            await BackgroundWeather.run()
        }
    }

    @MainActor
    private func startAppServices() async {
        guard !appServicesStarted else { return }
        appServicesStarted = true
        weather.notifier = notifications
        locationManager.nav = navProgress
        locationManager.trip = store
        locationManager.routeStore = routeStore
        locationManager.altimeter = altimeter
        locationManager.startIfAuthorized()
        altimeter.start()
        await gallery.load()
        await AnnouncementEngine.shared.load()
        await MusicPlayer.shared.load()
        await roadFeed.refresh()
        await journal.drainQueue()
        await AnnouncementAudio.shared.loadManifest()
        if let stops = store.trip?.stops {
            routeSession.reconcile(stops: stops)
            locationManager.startMonitoringStops(stops)
        }
        store.effectiveDeparture = { [weak store] in plan.departure(store?.trip) }
        applyPlanCascade()
        plan.onChange = { _ in applyPlanCascade() }
        await plan.syncFromWeb()
        applyPlanCascade()
        notifications.scheduleDailyJournalReminder()
        notifications.scheduleDailySummary()
        BackgroundWeather.schedule()
        checkDeparturePrompt()
    }

    /// Kalkış/plan değiştiğinde tek noktadan kaskat:
    /// bildirimleri yeniden kur → widget snapshot'ını tazele → widget'ları yenile.
    @MainActor
    private func applyPlanCascade() {
        let departure = plan.departure(store.trip)
        notifications.scheduleDepartureReminders(departure: departure)
        store.writeSnapshot()
        LiveActivityManager.shared.reloadWidgetsThrottled()
        routeSession.writeSnapshot()
        // Siteye YALNIZCA sahip cihaz yazar. Aksi hâlde henüz senkron olmamış bir
        // takipçi (çevrimdışıydı, yeni kuruldu) eski takvimi siteye basıp
        // sahibin doğru planını ezebilir.
        if plan.isOwner, let scope = PublishedTripScope(trip: workspace.selectedTrip) {
            PlanPublisher.publish(scope: scope, trip: store.trip, edits: plan.edits)
        }
    }

    /// Kalkış uyarısını denetle: gezi kalkışı DEĞİL, bugünün etkin gününün
    /// kalkış saati (2.-8. günler 08:00). GPS yoksa günün varış durağına düş.
    @MainActor
    private func checkDeparturePrompt() {
        guard account.isSignedIn, workspace.selectedTrip?.kind == .kuzey2026 else { return }
        // Web kalkış tarihi ayrıştırılamazsa TripPlanner "bugün 00:00"a düşer;
        // bu yedek tarihle gece yarısı hayalet "Kalkış vakti" modalı açılmasın.
        guard plan.edits.departureAt != nil || store.trip?.departureDate != nil else { return }
        guard let trip = store.trip else { return }
        let nextRequiredStop = routeSession.nextStartableStopId(stops: trip.stops)
            .flatMap { id in trip.stops.first { $0.id == id } }
        departurePrompt.checkIfDue(departure: todaysDeparture(),
                                   nextStop: nextRequiredStop ?? fallbackStop())
    }

    @MainActor
    private func applyAccountWorkspace() {
        guard let user = account.user else {
            workspace.clear()
            applyPublishedTripScope()
            return
        }
        workspace.activate(user: user, trips: account.initialTrips)
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-ui-preview-builder") {
            workspace.closeTrip()
        } else if ProcessInfo.processInfo.arguments.contains("-ui-preview-standard"),
           let standard = account.initialTrips.first(where: { $0.kind == .standard }) {
            workspace.select(standard)
        } else if ProcessInfo.processInfo.arguments.contains(where: {
            ["-ui-preview-dashboard", "-ui-preview-plan", "-ui-preview-map",
             "-ui-preview-journal", "-ui-preview-tools"].contains($0)
        }),
                  let kuzey = account.initialTrips.first(where: { $0.kind == .kuzey2026 }) {
            workspace.select(kuzey)
        }
        #endif
        applyAccountRole()
        applyPublishedTripScope()
    }

    @MainActor
    private func applyAccountRole() {
        guard let user = account.user else { return }
        let ownsSelectedTrip = workspace.selectedTrip?.access.tripRole == .owner
        role.isDriver = user.isAdmin || ownsSelectedTrip
        plan.isOwner = user.isAdmin || ownsSelectedTrip
    }

    /// Public endpoints exist only for the opted-in Kuzey trip. Changing
    /// accounts, a selected trip, or its feature flags recomputes the scope;
    /// leaving it pauses the credential-free outbox without discarding work.
    @MainActor
    private func applyPublishedTripScope() {
        let scope = PublishedTripScope(trip: workspace.selectedTrip)
        PublishOutbox.shared.setScope(scope)
        plan.setPublishedTripScope(scope)
        locationManager.publishedTripScope = scope
        guard scope != nil else { return }
        expenses.publishTotal()
        journal.publishShared()
        applyPlanCascade()
    }

    /// Bugünün etkin günü (çok günlü durakta ortanca gün de sayılır).
    @MainActor
    private func todaysDay() -> EffectiveDay? {
        let cal = TripPlanner.routeCalendar
        let today = cal.startOfDay(for: Date())
        return plan.days(store.trip).first { day in
            guard let end = cal.date(byAdding: .day, value: day.dayCount - 1, to: day.date)
            else { return false }
            return today >= day.date && today <= end
        }
    }

    /// Bugünün kalkış anı; bugün plan dışındaysa gezi kalkışına düş.
    @MainActor
    private func todaysDeparture() -> Date {
        todaysDay()?.departTime ?? plan.departure(store.trip)
    }

    /// GPS henüz yokken modalın hedefi: bugünün varış durağı, yoksa ikinci durak
    /// (stops[0] çıkış noktası; sıradaki anlamlı durak stops[1]).
    @MainActor
    private func fallbackStop() -> Stop? {
        guard let trip = store.trip else { return nil }
        if let day = todaysDay(), let stop = trip.stop(matching: day.destination) {
            return stop
        }
        return trip.stops.dropFirst().first
    }
}
