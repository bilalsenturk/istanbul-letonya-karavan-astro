import SwiftUI

struct DashboardView: View {
    @EnvironmentObject var store: TripStore
    @EnvironmentObject var loc: LocationManager
    @EnvironmentObject var weather: WeatherService
    @EnvironmentObject var expenses: ExpenseStore
    @EnvironmentObject var routeStore: RouteStore
    @EnvironmentObject var nav: NavProgressStore
    @EnvironmentObject var altimeter: AltimeterService
    @EnvironmentObject var plan: TripPlanStore
    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var showSettings = false

    // Sürüş Focus filtresi (Ayarlar → Odak → Sürüş → Kuzey): sade panel.
    @AppStorage(SharedSnapshot.Key.simpleMode, store: SharedSnapshot.defaults)
    private var simpleMode = false

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.bg.ignoresSafeArea()
                aurora

                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        header
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
                                CountdownView(departure: plan.departure(trip))
                            }
                            if !simpleMode { metricRow(trip: trip) }
                            // iPad'de kartlar iki sütuna açılır, iPhone'da tek sütun kalır.
                            AdaptiveColumns(spacing: 16) {
                                if !simpleMode { expenseCard(trip: trip) }
                                LiveLocationCard()
                                if !simpleMode {
                                    arrivalsCard
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
        }
        .task {
            loc.request()
            if let stops = store.trip?.stops {
                async let w: () = weather.refresh(stops: stops)
                async let r: () = routeStore.computeIfNeeded(stops: stops)
                _ = await (w, r)
                await nav.update(location: loc.location, stops: stops, route: routeStore)
            }
        }
        .onChange(of: loc.location?.timestamp) { _, _ in
            altimeter.stationary = (loc.speedKmh ?? 0) < 5   // yalnızca dururken fırtına kontrolü
        }
        .sheet(isPresented: $showSettings) { TripSettingsView() }
    }

    // MARK: - Parçalar

    private var aurora: some View {
        GeometryReader { geo in
            ZStack {
                Circle().fill(Theme.c3.opacity(0.20))
                    .frame(width: geo.size.width * 0.9)
                    .blur(radius: 90)
                    .offset(x: geo.size.width * 0.35, y: -geo.size.height * 0.32)
                Circle().fill(Theme.c1.opacity(0.16))
                    .frame(width: geo.size.width * 0.8)
                    .blur(radius: 80)
                    .offset(x: -geo.size.width * 0.3, y: geo.size.height * 0.34)
            }
        }
        .ignoresSafeArea()
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
        if nav.currentCity != nil || nav.nextStop != nil {
            HStack(spacing: 8) {
                if let city = nav.currentCity {
                    Label("Şu an: \(city)", systemImage: "location.fill")
                        .font(.system(size: 12.5, weight: .bold, design: .rounded))
                        .foregroundStyle(Theme.c4)
                }
                if let next = nav.nextStop, let km = nav.remainingKm {
                    Text("· Sıradaki \(next.name): \(km) km" + (nav.remainingMinutes != nil ? " · \(nav.remainingTimeText)" : ""))
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
        let ceiling = Double(trip.totalBudget.max ?? 1795)
        let ratio = ceiling > 0 ? min(1, expenses.total / ceiling) : 0
        let percent = Int((ratio * 100).rounded())
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
                    Text("/ €\(ceiling, specifier: "%.0f") tahmini")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Theme.muted)
                }
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
            .card()
        }
        .buttonStyle(.plain)
    }

    // Kalan tüm duraklara zincirleme varış tahmini (Apple ETA) + rakım.
    @ViewBuilder private var arrivalsCard: some View {
        if !nav.arrivals.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    MonoLabel(text: "Tahmini varışlar", color: Theme.c3)
                    Spacer()
                    if altimeter.available, let alt = altimeter.altitude {
                        Label("\(Int(alt)) m", systemImage: "mountain.2.fill")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Theme.dim)
                    }
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
                    Label(day.camp.place, systemImage: "tent.fill")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Theme.muted)
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
