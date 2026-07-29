import SwiftUI
import UserNotifications

struct DashboardView: View {
    @EnvironmentObject var store: TripStore
    @EnvironmentObject var loc: LocationManager
    @EnvironmentObject var weather: WeatherService
    @EnvironmentObject var expenses: ExpenseStore
    @EnvironmentObject var routeStore: RouteStore
    @EnvironmentObject var nav: NavProgressStore
    @EnvironmentObject var altimeter: AltimeterService
    @EnvironmentObject var plan: TripPlanStore
    @EnvironmentObject var routeSession: RouteSession
    @EnvironmentObject private var notifications: NotificationManager
    @EnvironmentObject private var account: AccountSessionStore
    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var showSettings = false
    @State private var showJourneyMenu = false
    @StateObject private var updates = UpdateChecker.shared

    // Sürüş Focus filtresi (Ayarlar → Odak → Sürüş → Kuzey): sade panel.
    @AppStorage(SharedSnapshot.Key.simpleMode, store: SharedSnapshot.defaults)
    private var simpleMode = false

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.bg.ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        header
                        if updates.shouldShowBanner { updateBanner }
                        if !notifications.authorized { notificationPrimer }
                        if let trip = store.trip {
                            VStack(alignment: .leading, spacing: 10) {
                                HStack {
                                    MonoLabel(text: "Yola çıkmaya kalan", color: Theme.c1)
                                    Spacer()
                                    Button { showSettings = true } label: {
                                        Label(plan.edits.departureAt == nil ? "Tarihi değiştir" : "Düzenlendi",
                                              systemImage: "calendar.badge.plus")
                                            .font(.system(size: 11, weight: .semibold))
                                            .foregroundStyle(plan.edits.departureAt == nil ? Theme.muted : Theme.c4)
                                    }
                                }
                                // Kalkış = düzenleme > web verisi (tek kaynak: TripPlanner)
                                CountdownView(
                                    departure: plan.departure(trip),
                                    routeStarted: routeSession.isActive,
                                    activeRouteName: routeSession.activeStopName
                                )
                            }
                            if !simpleMode { metricRow(trip: trip) }
                            // iPad'de kartlar iki sütuna açılır, iPhone'da tek sütun kalır.
                            AdaptiveColumns(spacing: 16) {
                                if !simpleMode { expenseCard(trip: trip) }
                                LiveLocationCard()
                                if !simpleMode { altitudeCard }
                                MiniMusicBar()
                                if !simpleMode {
                                    arrivalsCard
                                    RoadFeedCard()
                                    weatherStrip
                                }
                            }
                        } else {
                            ProgressView().tint(.white).padding(40)
                        }
                    }
                    .padding(.horizontal, 18)
                    .padding(.bottom, 34)
                    .frame(maxWidth: Adaptive.contentWidth(sizeClass))
                    .frame(maxWidth: .infinity)
                }
                .refreshable {
                    await store.refreshFromRemote()
                    if let stops = store.trip?.stops {
                        await weather.refresh(stops: stops)
                    }
                }
            }
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showJourneyMenu = true } label: {
                        if account.isRestoring {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Image(systemName: account.isSignedIn ? "person.crop.circle.fill" : "person.crop.circle")
                        }
                    }
                    .accessibilityLabel(account.isSignedIn ? "Hesap ve yolculuk" : "Apple hesabıyla giriş yap")
                }
            }
        }
        .task {
            async let u: () = updates.checkIfNeeded()
            async let b: () = bootstrap()
            _ = await (u, b)
        }
        // .task yolculuk yüklenmeden çalıştıysa (bundled decode + uzaktan
        // yükleme yarışı) hava/rota/nav başlatılmadan kalırdı — gelince tekrar dene.
        .onChange(of: store.trip != nil) { _, loaded in
            if loaded { Task { await bootstrap() } }
        }
        .onChange(of: loc.location?.timestamp) { _, _ in
            updateAltimeterMotionGate()
        }
        .onChange(of: loc.status) { _, _ in
            updateAltimeterMotionGate()
        }
        .sheet(isPresented: $showSettings) { TripSettingsView() }
        .sheet(isPresented: $showJourneyMenu) {
            JourneyMenuView()
        }
    }

    // MARK: - Parçalar

    // TestFlight güncelleme bildirimi (kaynak: sitedeki /kuzey-version.json).
    // Zorunluysa kapatılamaz; değilse "Sonra" o build için gizler.
    private var updateBanner: some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack {
                MonoLabel(text: updates.isRequired ? "Güncelleme gerekli" : "Yeni sürüm",
                          color: updates.isRequired ? Theme.bad : Theme.c1)
                Spacer()
                if !updates.isRequired {
                    Button { updates.snoozeLatest() } label: {
                        Text("Sonra")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Theme.muted)
                    }
                    .buttonStyle(.plain)
                }
            }
            Text(updates.isRequired
                 ? "Bu sürüm artık desteklenmiyor"
                 : "Yeni sürüm hazır\(updates.latestBuild.map { " (build \($0))" } ?? "")")
                .font(.system(size: 17, weight: .heavy, design: .rounded))
                .foregroundStyle(Theme.text)
            Text(updates.isRequired
                 ? "Kuzey'i kullanmaya devam etmek için TestFlight'tan güncelle."
                 : "TestFlight'ta yeni bir build var; güncellemek için dokun.")
                .font(.system(size: 12.5, weight: .medium))
                .foregroundStyle(Theme.dim)
            if let url = updates.testflightURL {
                Link(destination: url) {
                    HStack(spacing: 8) {
                        Image(systemName: "arrow.down.circle.fill")
                            .font(.system(size: 14, weight: .bold))
                        Text("TestFlight'ta güncelle")
                            .font(.system(size: 15, weight: .bold, design: .rounded))
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(
                        updates.isRequired ? AnyShapeStyle(Theme.bad) : AnyShapeStyle(Theme.gradWarm),
                        in: RoundedRectangle(cornerRadius: 13, style: .continuous)
                    )
                }
            }
        }
        .card()
    }

    private var notificationPrimer: some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack(spacing: 8) {
                Image(systemName: "bell.badge.fill")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(Theme.c1)
                MonoLabel(text: "Yolculuk bildirimleri", color: Theme.c1)
            }
            Text("Kalkış, varış ve hava uyarılarını zamanında al.")
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundStyle(Theme.dim)
            Button(action: performNotificationPermissionAction) {
                Text(notifications.authorizationStatus == .denied ? "Ayarları Aç" : "Bildirimleri Aç")
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 44)
                    .background(Theme.gradWarm, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
            }
            .buttonStyle(.plain)
        }
        .card()
    }

    private func performNotificationPermissionAction() {
        if notifications.authorizationStatus == .denied {
            notifications.openSettings()
        } else {
            Task { await notifications.requestAuthorization() }
        }
    }

    /// Mevcut konum izni + hava/rota/nav önyüklemesi. Yolculuk henüz yoksa
    /// sessizce geçer; trip geldiğinde onChange yeniden çağırır.
    private func bootstrap() async {
        loc.startIfAuthorized()
        updateAltimeterMotionGate()
        if let stops = store.trip?.stops {
            async let w: () = weather.refresh(stops: stops)
            async let r: () = routeStore.computeIfNeeded(stops: stops)
            _ = await (w, r)
            await nav.update(location: loc.location, stops: stops, route: routeStore)
        }
    }

    private func updateAltimeterMotionGate() {
        altimeter.motionSignalUnavailable = loc.status == .denied || loc.status == .restricted
        altimeter.updateMotion(speedKmh: loc.speedKmh)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "location.north.circle.fill")
                    .font(.system(size: 17))
                    .foregroundStyle(Theme.grad)
                MonoLabel(text: "Kuzey · İstanbul → Riga", color: Theme.dim)
                Spacer()
                if let t = weather.updatedAt {
                    MonoLabel(text: t.formatted(date: .omitted, time: .shortened))
                }
            }
            Text("Letonya Yolculuğu")
                .font(.system(size: 36, weight: .heavy, design: .rounded))
                .foregroundStyle(Theme.text)
            liveStatusLine
        }
        .padding(.top, 8)
    }

    // Anlık şehir + sıradaki hedefe kalan km/süre (dashboard başlığı altında).
    @ViewBuilder private var liveStatusLine: some View {
        let nextRequiredStop = store.trip.flatMap { trip in
            routeSession.nextStartableStopId(stops: trip.stops)
                .flatMap { id in trip.stops.first { $0.id == id } }
        }
        if nav.currentCity != nil || routeSession.isActive || nextRequiredStop != nil {
            HStack(spacing: 8) {
                if let city = nav.currentCity {
                    Label("Şu an: \(city)", systemImage: "location.fill")
                        .font(.system(size: 12.5, weight: .bold, design: .rounded))
                        .foregroundStyle(Theme.c4)
                }
                if routeSession.isActive, let active = routeSession.activeStopName, let km = nav.remainingKm {
                    Text("· Aktif rota \(active): \(km) km" + (nav.remainingMinutes != nil ? " · \(nav.remainingTimeText)" : ""))
                        .font(.system(size: 12.5, weight: .semibold, design: .rounded))
                        .foregroundStyle(Theme.dim)
                        .lineLimit(1)
                        .minimumScaleFactor(0.65)
                } else if let next = nextRequiredStop {
                    Text("· Sıradaki etap: \(next.name)")
                        .font(.system(size: 12.5, weight: .semibold, design: .rounded))
                        .foregroundStyle(Theme.dim)
                        .lineLimit(1)
                        .minimumScaleFactor(0.65)
                }
            }
        }
    }

    private func metricRow(trip: TripData) -> some View {
        HStack(spacing: 10) {
            metric(value: "\(trip.totalKm)", unit: "km", label: "Mesafe")
            metric(value: trip.totalBudget.fuel, unit: "", label: "Yakıt")
            metric(value: "\(trip.days.count) gün", unit: "\(trip.stops.count) durak", label: "Rota")
        }
    }

    private func metric(value: String, unit: String, label: String) -> some View {
        VStack(spacing: 3) {
            Text(value)
                .font(.system(size: 17, weight: .heavy, design: .rounded))
                .foregroundStyle(Theme.text)
                .lineLimit(1)
                .minimumScaleFactor(0.55)
            Text(unit.isEmpty ? label.uppercased() : "\(unit) · \(label)".uppercased())
                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                .kerning(0.8)
                .foregroundStyle(Theme.muted)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(Theme.panel, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Theme.line, lineWidth: 1)
        )
    }

    // MARK: - Harcama kartı (dokununca detay liste açılır)

    private func expenseCard(trip: TripData) -> some View {
        // Üst sınır web verisinde yoksa sihirli sayıyla oran HESAPLAMA —
        // bütçe çubuğunu gizle, yalnızca harcanan toplamı göster.
        let ceiling = trip.totalBudget.max.map(Double.init)
        let ratio = ceiling.flatMap { $0 > 0 ? min(1, expenses.total / $0) : nil }
        return NavigationLink {
            ExpensesView()
        } label: {
            VStack(alignment: .leading, spacing: 11) {
                HStack {
                    MonoLabel(text: "Harcanan", color: Theme.c1)
                    Spacer()
                    Text("detay")
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .foregroundStyle(Theme.muted)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Theme.muted)
                }
                HStack(alignment: .firstTextBaseline, spacing: 7) {
                    Text("€\(expenses.total, specifier: "%.0f")")
                        .font(.system(size: 34, weight: .heavy, design: .rounded))
                        .foregroundStyle(Theme.text)
                    if let ceiling {
                        Text("/ €\(ceiling, specifier: "%.0f") tahmini")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(Theme.muted)
                    } else if expenses.expenses.isEmpty {
                        Text("+ ekle")
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .foregroundStyle(Theme.dim)
                    }
                }
                if let ceiling, let ratio {
                    let percent = Int((ratio * 100).rounded())
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color.white.opacity(0.08))
                            Capsule()
                                .fill(percent >= 100 ? AnyShapeStyle(Theme.bad) : AnyShapeStyle(Theme.gradWarm))
                                .frame(width: geo.size.width * ratio)
                        }
                    }
                    .frame(height: 9)
                    HStack {
                        Text("%\(percent) harcandı")
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .foregroundStyle(percent >= 100 ? Theme.bad : Theme.dim)
                        Spacer()
                        Text(expenses.expenses.isEmpty ? "+ ekle" : "kalan €\(max(0, ceiling - expenses.total), specifier: "%.0f")")
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .foregroundStyle(Theme.dim)
                    }
                }
            }
            .card()
        }
        .buttonStyle(.plain)
    }

    // Kalan tüm duraklara zincirleme varış tahmini (Apple ETA) + rakım.
    @ViewBuilder private var arrivalsCard: some View {
        if routeSession.isActive && !nav.arrivals.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    MonoLabel(text: "Tahmini varışlar", color: Theme.c3)
                    Spacer()
                }
                ForEach(nav.arrivals) { a in
                    HStack(spacing: 10) {
                        CountryBadge(code: a.code, size: 9)
                        Text(a.name)
                            .font(.system(size: 14, weight: .semibold, design: .rounded))
                            .foregroundStyle(Theme.text)
                        Spacer()
                        Text(etaText(a.eta))
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                            .foregroundStyle(Theme.dim)
                    }
                }
            }
            .card()
        }
    }

    private var altitudeCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                MonoLabel(text: "Yükseklik", color: Theme.c4)
                Spacer()
                if let pressure = altimeter.pressureHpa {
                    Text("\(Int(pressure.rounded())) hPa")
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundStyle(Theme.muted)
                }
            }

            if let reading = AltitudeDisplay.reading(
                absoluteMeters: altimeter.absoluteAltitude,
                relativeMeters: altimeter.relativeAltitude
            ) {
                HStack(alignment: .center, spacing: 14) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(Theme.c4.opacity(0.14))
                            .frame(width: 54, height: 54)
                        Image(systemName: reading.symbol)
                            .font(.system(size: 24, weight: .bold))
                            .foregroundStyle(Theme.c4)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(reading.text)
                            .font(.system(size: 36, weight: .heavy, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(Theme.text)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                        Text(reading.label)
                            .font(.system(size: 12, weight: .bold, design: .monospaced))
                            .foregroundStyle(Theme.muted)
                    }
                    Spacer(minLength: 0)
                }
                if altimeter.altitudeIsRelative {
                    Text("Mutlak barometre yok; değer başlangıca göre değişimi gösterir.")
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(Theme.muted)
                } else if altimeter.motionSignalUnavailable {
                    Text("Konum izni yok; basınç uyarısı hareket ayrımı olmadan izlenir.")
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(Theme.warn)
                }
            } else {
                HStack(spacing: 10) {
                    Image(systemName: altimeter.available ? "gauge.with.dots.needle.67percent" : "slash.circle")
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(Theme.muted)
                    Text(altimeter.available ? "Rakım ölçülüyor…" : "Bu cihazda barometre yok")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(Theme.muted)
                    Spacer()
                }
                .padding(.vertical, 8)
            }
        }
        .card()
    }

    private func etaText(_ date: Date) -> String {
        let cal = Calendar.current
        let time = date.formatted(date: .omitted, time: .shortened)
        if cal.isDateInToday(date) { return time }
        if cal.isDateInTomorrow(date) { return "yarın \(time)" }
        return date.formatted(.dateTime.weekday(.abbreviated).hour().minute())
    }

    private var weatherStrip: some View {
        VStack(alignment: .leading, spacing: 10) {
            MonoLabel(text: "Duraklarda hava · canlı", color: Theme.c4)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(weather.items) { w in
                        VStack(alignment: .leading, spacing: 7) {
                            HStack(spacing: 5) {
                                Text(w.code)
                                    .font(.system(size: 10, weight: .heavy, design: .rounded))
                                    .foregroundStyle(Theme.dim)
                                Text(w.name)
                                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                                    .foregroundStyle(Theme.dim)
                            }
                            HStack(spacing: 8) {
                                Image(systemName: w.symbol)
                                    .symbolRenderingMode(.multicolor)
                                    .font(.system(size: 24))
                                Text("\(w.temp)°")
                                    .font(.system(size: 27, weight: .heavy, design: .rounded))
                                    .foregroundStyle(Theme.text)
                            }
                            Text(w.desc)
                                .font(.system(size: 10.5, weight: .medium))
                                .foregroundStyle(w.isRaining ? Theme.c2 : Theme.muted)
                                .lineLimit(1)
                        }
                        .padding(12)
                        .frame(width: 130, alignment: .leading)
                        .background(
                            w.isRaining ? Theme.c2.opacity(0.13) : Color.white.opacity(0.055),
                            in: RoundedRectangle(cornerRadius: 15, style: .continuous)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 15, style: .continuous)
                                .strokeBorder(w.isRaining ? Theme.c2.opacity(0.45) : Theme.line, lineWidth: 1)
                        )
                    }
                }
            }
        }
    }
}

struct TimelineRow: View {
    let day: DayPlan
    let index: Int
    let isLast: Bool

    @EnvironmentObject private var store: TripStore
    @EnvironmentObject private var plan: TripPlanStore

    /// Türetilmiş tarih (kalkış değişince kendiliğinden güncellenir).
    private var effective: EffectiveDay? { plan.day(store.trip, slug: day.slug) }

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(spacing: 0) {
                ZStack {
                    Circle()
                        .fill(day.isRestDay ? AnyShapeStyle(Theme.gradCool) : AnyShapeStyle(Theme.gradWarm))
                        .frame(width: 38, height: 38)
                    Text(day.isRestDay ? "☾" : "\(index + 1)")
                        .font(.system(size: 16, weight: .heavy, design: .rounded))
                        .foregroundStyle(day.isRestDay ? Color.white : Color.black.opacity(0.8))
                }
                if !isLast {
                    Rectangle()
                        .fill(Theme.line)
                        .frame(width: 2)
                        .frame(maxHeight: .infinity)
                }
            }
            .frame(width: 38)

            VStack(alignment: .leading, spacing: 8) {
                Text((effective?.dateText ?? day.date).uppercased())
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .kerning(1.0)
                    .foregroundStyle(Theme.muted)

                Text(day.isRestDay ? "\(day.origin) · Dinlenme" : "\(day.origin) → \(day.destination)")
                    .font(.system(size: 19, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.text)

                if !day.isRestDay {
                    HStack(spacing: 12) {
                        Label(day.distanceKm, systemImage: "road.lanes")
                        Label(day.duration, systemImage: "clock.fill")
                    }
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Theme.dim)
                }

                HStack {
                    Label(
                        effective?.arrivalTarget?.name
                            ?? (day.isRestDay ? "Konaklama planlanmadı" : "Varış yeri seçilmedi"),
                        systemImage: effective?.arrivalTarget == nil ? "mappin.slash" : "mappin.and.ellipse"
                    )
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(effective?.arrivalTarget == nil ? Theme.c3 : Theme.muted)
                        .lineLimit(1)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Theme.c2)
                }
            }
            .padding(14)
            .background(Theme.panel, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(Theme.line, lineWidth: 1)
            )
        }
        .fixedSize(horizontal: false, vertical: true)
    }
}
