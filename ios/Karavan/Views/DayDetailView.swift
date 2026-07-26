import SwiftUI

struct DayDetailView: View {
    let day: DayPlan
    let index: Int
    @EnvironmentObject var store: TripStore
    @EnvironmentObject var plan: TripPlanStore
    @EnvironmentObject var routeStore: RouteStore
    @EnvironmentObject var gallery: GalleryStore
    @EnvironmentObject var role: RoleStore
    @EnvironmentObject var nav: NavProgressStore
    @EnvironmentObject var loc: LocationManager
    @EnvironmentObject var routeSession: RouteSession
    @EnvironmentObject private var account: AccountSessionStore
    @EnvironmentObject private var workspace: TripWorkspaceStore
    @Environment(\.openURL) private var openURL
    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var showEdit = false
    @State private var showTargetPicker = false
    @State private var showTargetEditor = false
    @State private var targetError: String?

    /// Türetilmiş gün (kullanıcı düzenlemeleri + hesaplanmış tarih).
    private var eff: EffectiveDay? {
        plan.day(store.trip, slug: day.slug)
    }

    private var destinationStop: Stop? {
        store.trip?.stop(matching: eff?.destination ?? day.destination)
    }

    private var accountDestinationStop: AccountRouteStop? {
        let destination = eff?.destination ?? day.destination
        return workspace.selectedTrip?.stops.first { normalized($0.name) == normalized(destination) }
    }

    private var exactTarget: ArrivalTarget? {
        accountDestinationStop?.resolvedArrivalTarget ?? eff?.arrivalTarget
    }

    private var exactStay: StayDetails {
        accountDestinationStop?.resolvedStayDetails ?? eff?.stayDetails ?? defaultStay
    }

    /// Apple Haritalar'ın bu etap için hesapladığı gerçek mesafe/süre.
    private var realLeg: (distance: Double, time: Double)? {
        guard let legIndex = eff?.legIndex else { return nil }
        return routeStore.legInfo(legIndex)
    }

    var body: some View {
        let e = eff
        let isRest = e?.isRestDay ?? day.isRestDay
        let origin = e?.origin ?? day.origin
        let destination = e?.destination ?? day.destination

        return ZStack {
            Theme.bg.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // En üstte: hedef şehrin kaydırmalı foto galerisi (açıklamalı).
                    let galleryPhotos = gallery.photos(forDestination: destination)
                    if galleryPhotos.isEmpty {
                        CampImage(path: day.camp.image, height: 200)
                    } else {
                        DayGalleryView(photos: galleryPhotos)
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 8) {
                            MonoLabel(text: "\(index + 1). gün · \(e?.dateText ?? day.date)", color: Theme.c1)
                            if e?.isEdited == true {
                                Text("düzenlendi")
                                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                                    .foregroundStyle(Theme.c4)
                                    .padding(.horizontal, 6).padding(.vertical, 3)
                                    .background(Theme.c4.opacity(0.15), in: Capsule())
                            }
                            Spacer()
                        }
                        Text(isRest ? "\(origin)\nDinlenme günü" : "\(origin) →\n\(destination)")
                            .font(.system(size: 32, weight: .heavy, design: .rounded))
                            .foregroundStyle(Theme.text)
                    }

                    dayFactsRow(e)

                    if let note = e?.note {
                        HStack(alignment: .top, spacing: 9) {
                            Image(systemName: "note.text").font(.system(size: 13)).foregroundStyle(Theme.c1)
                            Text(note).font(.system(size: 14)).foregroundStyle(Theme.dim)
                            Spacer()
                        }
                        .padding(12)
                        .background(Theme.c1.opacity(0.10), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
                    }

                    if !isRest {
                        HStack(spacing: 8) {
                            chip("road.lanes", e?.distanceKm ?? day.distanceKm)
                            chip("clock.fill", e?.duration ?? day.duration)
                        }
                        chip("fuelpump.fill", e?.fuel ?? day.fuel)

                    }

                    arrivalTargetSection(isRest: isRest)

                    if let targetError {
                        Text(targetError).font(.footnote).foregroundStyle(Theme.warn)
                    }

                    waypointsSection
                    camerasSection

                    section("Sorun senaryoları", items: day.risks, tint: Theme.bad)
                    section("Fırsatlar", items: day.opportunities, tint: Theme.ok)
                    section("Yedek plan", items: day.contingencies, tint: Theme.warn)

                    alternativesSection
                }
                .padding(18)
                .frame(maxWidth: Adaptive.contentWidth(sizeClass))
                .frame(maxWidth: .infinity)
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { showEdit = true } label: {
                    Label("Düzenle", systemImage: "slider.horizontal.3")
                        .font(.system(size: 15, weight: .semibold))
                }
                .tint(Theme.c2)
                .disabled(eff == nil)
            }
        }
        .sheet(isPresented: $showEdit) {
            if let e = eff { DayEditView(day: e) }
        }
        .sheet(isPresented: $showTargetPicker) {
            if let city = destinationStop {
                ArrivalTargetPickerView(
                    cityName: city.name,
                    cityCoordinate: city.coordinate,
                    initialSelection: exactTarget
                ) { target in
                    saveTarget(target, stay: derivedStay(from: exactStay))
                }
            }
        }
        .sheet(isPresented: $showTargetEditor) {
            if let target = exactTarget {
                ArrivalTargetEditorView(
                    target: target,
                    stay: derivedStay(from: exactStay),
                    routeId: workspace.selectedTrip?.id ?? "kuzey-local"
                ) { target, stay in
                    saveTarget(target, stay: stay)
                }
            }
        }
        // Web senkronu günü kaldırırsa (eff → nil) açık sheet boş kalırdı — kapat.
        .onChange(of: eff == nil) { _, gone in
            if gone { showEdit = false }
        }
        .preferredColorScheme(.dark)
    }

    private func routeActionText(_ state: RouteStepState) -> String {
        switch state {
        case .available: "Buraya git"
        case .active: "Rota aktif"
        case .completed: "Tamamlandı"
        case .locked: "Sırada değil"
        case .origin: "Başlangıç"
        }
    }

    @ViewBuilder
    private func arrivalTargetSection(isRest: Bool) -> some View {
        if let city = destinationStop, let stops = store.trip?.stops {
            let state = routeSession.state(for: city, stops: stops)
            let canStart = role.isDriver && state == .available && exactTarget?.hasValidCoordinate == true
            ArrivalTargetCard(
                target: exactTarget,
                isRestDay: isRest,
                canStart: canStart,
                actionText: role.isDriver ? routeActionText(state) : "Yalnız sürücü başlatabilir",
                onChoose: { showTargetPicker = true },
                onEdit: { showTargetEditor = true },
                onStart: {
                    guard canStart else { return }
                    Task {
                        await LegLauncher.start(
                            stop: city,
                            stops: stops,
                            nav: nav,
                            location: loc.location,
                            speedKmh: loc.speedKmh
                        )
                    }
                }
            )
        }
    }

    private var defaultStay: StayDetails {
        guard let effective = eff else { return StayDetails() }
        let checkOut = TripPlanner.routeCalendar.date(
            byAdding: .day, value: effective.dayCount, to: effective.date
        )
        return StayDetails(checkIn: effective.date, checkOut: checkOut)
    }

    private func derivedStay(from value: StayDetails) -> StayDetails {
        var result = value
        if result.checkIn == nil { result.checkIn = defaultStay.checkIn }
        if result.checkOut == nil { result.checkOut = defaultStay.checkOut }
        return result
    }

    private func saveTarget(_ target: ArrivalTarget, stay: StayDetails) {
        plan.setArrivalTarget(target, stay: stay, slug: day.slug)
        guard var stop = accountDestinationStop, let trip = workspace.selectedTrip,
              trip.access.canEditStops else { return }
        stop.arrivalTarget = AccountArrivalTarget(target)
        stop.stayDetails = AccountStayDetails(stay)
        Task {
            do {
                let changed = try await account.updateStop(trip: trip, stop: stop)
                workspace.replace(changed)
                targetError = nil
            } catch {
                targetError = "Varış yeri cihazda kaydedildi ancak üyelerle eşitlenemedi: \(error.localizedDescription)"
            }
        }
    }

    private func normalized(_ value: String) -> String {
        value.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "tr_TR"))
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Türetilmiş gün bilgileri (gerçek Apple mesafe/süre, varış saati, sınır)

    @ViewBuilder
    private func dayFactsRow(_ e: EffectiveDay?) -> some View {
        if let e {
            let facts = buildFacts(e)
            if !facts.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    MonoLabel(text: "Bu gün", color: Theme.c2)
                    ForEach(facts, id: \.label) { f in
                        HStack(spacing: 10) {
                            Image(systemName: f.icon)
                                .font(.system(size: 13)).foregroundStyle(Theme.c2)
                                .frame(width: 20)
                            Text(f.label)
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(Theme.muted)
                            Spacer()
                            Text(f.value)
                                .font(.system(size: 13.5, weight: .bold, design: .rounded))
                                .foregroundStyle(Theme.text)
                        }
                    }
                }
                .card()
            }
        }
    }

    private func buildFacts(_ e: EffectiveDay) -> [(icon: String, label: String, value: String)] {
        var facts: [(String, String, String)] = []
        let timeFmt = Date.FormatStyle.dateTime.hour().minute()

        if !e.isRestDay {
            facts.append(("clock.fill", "Çıkış", e.departTime.formatted(timeFmt)))
        }
        if let real = realLeg {
            let km = Int((real.distance / 1000).rounded())
            let mins = Int((real.time / 60).rounded())
            let timeText = mins >= 60 ? "\(mins / 60) sa \(mins % 60) dk" : "\(mins) dk"
            facts.append(("map.fill", "Gerçek yol (Apple)", "\(km) km · \(timeText)"))
            let arrival = e.departTime.addingTimeInterval(real.time)
            facts.append(("flag.checkered", "Tahmini varış", arrival.formatted(timeFmt)))
        }
        if e.dayCount > 1 {
            facts.append(("calendar", "Konaklama", "\(e.dayCount) gün"))
        }
        if let trip = store.trip, e.crossesBorder(in: trip) {
            let from = trip.stop(matching: e.origin)?.code ?? ""
            let to = trip.stop(matching: e.destination)?.code ?? ""
            facts.append(("flag.2.crossed.fill", "Sınır geçişi", "\(from) → \(to)"))
        }
        if let label = day.trafficLabel {
            facts.append(("car.2.fill", "Trafik", label))
        }
        return facts.map { (icon: $0.0, label: $0.1, value: $0.2) }
    }

    // MARK: - Gün içi ara duraklar (web verisinde vardı, app'te ilk kez)

    @ViewBuilder private var waypointsSection: some View {
        if let points = day.waypoints, !points.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                MonoLabel(text: "Yol üstü duraklar", color: Theme.c3)
                ForEach(points) { p in
                    HStack(alignment: .top, spacing: 11) {
                        Image(systemName: p.icon)
                            .font(.system(size: 14)).foregroundStyle(Theme.c3)
                            .frame(width: 22)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(p.name)
                                .font(.system(size: 14.5, weight: .semibold, design: .rounded))
                                .foregroundStyle(Theme.text)
                            Text(p.type)
                                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                                .foregroundStyle(Theme.c3.opacity(0.85))
                            if let note = p.note, !note.isEmpty {
                                Text(note)
                                    .font(.system(size: 12.5))
                                    .foregroundStyle(Theme.muted)
                            }
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(11)
                    .background(Theme.panel, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 13, style: .continuous)
                        .strokeBorder(Theme.line, lineWidth: 1))
                }
            }
        }
    }

    @ViewBuilder private var camerasSection: some View {
        if let cams = day.cityCameras, !cams.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                MonoLabel(text: "Yol kameraları", color: Theme.c2)
                ForEach(cams) { cam in
                    Button {
                        if let url = URL(string: cam.url) { openURL(url) }
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "video.fill")
                                .font(.system(size: 13)).foregroundStyle(Theme.c2)
                            Text(cam.title)
                                .font(.system(size: 14, weight: .semibold, design: .rounded))
                                .foregroundStyle(Theme.text)
                                .lineLimit(1)
                            Spacer()
                            Image(systemName: "arrow.up.right")
                                .font(.system(size: 11, weight: .bold)).foregroundStyle(Theme.muted)
                        }
                        .padding(11)
                        .background(Theme.panel, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(Theme.line, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    @ViewBuilder private var alternativesSection: some View {
        if let alts = day.camp.alternatives, !alts.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                MonoLabel(text: "Diğer kamp seçenekleri", color: Theme.c3)
                ForEach(alts) { alt in
                    Button {
                        if let url = URL(string: alt.link) { openURL(url) }
                    } label: {
                        HStack(spacing: 12) {
                            CampImage(path: alt.image, height: 62, width: 82, cornerRadius: 12)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(alt.name)
                                    .font(.system(size: 15, weight: .bold, design: .rounded))
                                    .foregroundStyle(Theme.text)
                                    .lineLimit(1)
                                Text(alt.place)
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundStyle(Theme.dim)
                                    .lineLimit(1)
                                if let note = alt.note, !note.isEmpty {
                                    Text(note)
                                        .font(.system(size: 11.5))
                                        .foregroundStyle(Theme.muted)
                                        .lineLimit(2)
                                }
                            }
                            Spacer(minLength: 4)
                            Image(systemName: "map.fill")
                                .font(.system(size: 13))
                                .foregroundStyle(Theme.c2)
                        }
                        .padding(10)
                        .background(Theme.panel, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Theme.line, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    /// Emoji yerine SF Symbol — her cihaz/font'ta render olur (emoji "?" çıkabiliyordu).
    private func chip(_ symbol: String, _ text: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Theme.c2)
            Text(text)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.dim)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Theme.panel, in: Capsule())
        .overlay(Capsule().strokeBorder(Theme.line, lineWidth: 1))
    }

    private func section(_ title: String, items: [String], tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            MonoLabel(text: title, color: tint)
            ForEach(items, id: \.self) { item in
                HStack(alignment: .top, spacing: 9) {
                    Circle().fill(tint).frame(width: 6, height: 6).padding(.top, 6)
                    Text(item)
                        .font(.system(size: 14))
                        .foregroundStyle(Theme.dim)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .card()
    }
}
