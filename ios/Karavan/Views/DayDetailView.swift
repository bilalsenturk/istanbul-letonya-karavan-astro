import MapKit
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
    @EnvironmentObject private var travelContent: TravelContentStore
    @Environment(\.openURL) private var openURL
    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var showEdit = false
    @State private var showTargetPicker = false
    @State private var showTargetEditor = false
    @State private var showAddSubplan = false
    @State private var targetError: String?
    @State private var contactCamp: CuratedCamp?
    @State private var pendingCampSelection: CuratedCamp?
    @State private var localTargetOverride: ArrivalTarget?
    @State private var localStayOverride: StayDetails?
    @State private var targetSaveRevision = 0
    @State private var targetSaveTask: Task<Void, Never>?

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
        ArrivalTargetResolution.resolve(
            localOverride: localTargetOverride,
            account: accountDestinationStop?.resolvedArrivalTarget,
            plan: eff?.arrivalTarget
        )
    }

    private var exactStay: StayDetails {
        localStayOverride ?? accountDestinationStop?.resolvedStayDetails ?? eff?.stayDetails ?? defaultStay
    }

    private var canEditArrivalTarget: Bool {
        workspace.selectedTrip?.access.canEditStops ?? (account.user == nil)
    }

    /// Apple Haritalar'ın bu etap için hesapladığı gerçek mesafe/süre.
    private var realLeg: (distance: Double, time: Double)? {
        guard let legIndex = eff?.legIndex else { return nil }
        return routeStore.legInfo(legIndex)
    }

    private var destinationContent: TravelDestinationContent? {
        travelContent.content(for: eff?.destination ?? day.destination)
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
                            .font(.system(size: 28, weight: .heavy, design: .rounded))
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

                    arrivalTargetSection(isRest: isRest)
                    communicationStateSection

                    if let content = destinationContent {
                        NearbyCampSection(
                            camps: content.camps,
                            cityCenter: content.cityCenter ?? destinationGeoPoint,
                            selectedTargetID: exactTarget?.id,
                            canEditStops: canEditArrivalTarget,
                            onOpenMaps: { openMap(name: $0.name, location: $0.location, directions: false) },
                            onContact: { contactCamp = $0 },
                            onSelect: { pendingCampSelection = $0 }
                        )
                        NearbyAttractionSection(
                            attractions: content.attractions,
                            referenceLocation: selectedStayLocation ?? content.camps.first?.location,
                            onOpenMaps: { openMap(name: $0.name, location: $0.location, directions: true) }
                        )
                    }

                    waypointsSection
                    subplansSection

                    if let targetError {
                        Text(targetError).font(.footnote).foregroundStyle(Theme.warn)
                    }

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
                    routeId: workspace.selectedTrip?.id ?? "kuzey-local",
                    profile: account.user?.travelProfile,
                    signedOutProfile: account.user == nil
                        ? StayContactProfileStore(routeId: workspace.selectedTrip?.id ?? "kuzey-local")
                            .signedOutProfile(vehicleSeed: workspace.selectedTrip?.kind == .kuzey2026 ? TravelProfileVehicleSeed.kuzey : nil)
                        : nil,
                    transportMode: workspace.selectedTrip?.transportMode ?? .automobile,
                    camp: (exactTarget?.maximumLengthMeters ?? day.camp.maximumLengthMeters).map(StayCamp.init),
                    automaticETA: defaultStay.estimatedArrivalWindow,
                    vehicleSeed: workspace.selectedTrip?.kind == .kuzey2026 ? TravelProfileVehicleSeed.kuzey : nil,
                    purpose: canEditArrivalTarget ? .editSelection : .contactOnly
                ) { target, stay in
                    saveTarget(target, stay: stay)
                }
            }
        }
        .sheet(item: $contactCamp) { camp in
            ArrivalTargetEditorView(
                target: arrivalTarget(for: camp),
                stay: derivedStay(from: exactStay),
                routeId: workspace.selectedTrip?.id ?? "kuzey-local",
                profile: account.user?.travelProfile,
                signedOutProfile: account.user == nil
                    ? StayContactProfileStore(routeId: workspace.selectedTrip?.id ?? "kuzey-local")
                        .signedOutProfile(vehicleSeed: workspace.selectedTrip?.kind == .kuzey2026 ? TravelProfileVehicleSeed.kuzey : nil)
                    : nil,
                transportMode: workspace.selectedTrip?.transportMode ?? .automobile,
                camp: camp.maximumLengthMeters.map(StayCamp.init),
                automaticETA: defaultStay.estimatedArrivalWindow,
                vehicleSeed: workspace.selectedTrip?.kind == .kuzey2026 ? TravelProfileVehicleSeed.kuzey : nil,
                purpose: .contactOnly
            )
        }
        .alert(
            "Bu kampı varış yeri seç?",
            isPresented: Binding(
                get: { pendingCampSelection != nil },
                set: { if !$0 { pendingCampSelection = nil } }
            ),
            presenting: pendingCampSelection
        ) { camp in
            Button("\(camp.name) kampını seç") {
                guard CuratedCampSelectionEligibility.canSelect(
                    supportsCaravan: camp.supportsCaravan,
                    canEditStops: canEditArrivalTarget
                ) else { return }
                saveTarget(arrivalTarget(for: camp), stay: derivedStay(from: exactStay))
                pendingCampSelection = nil
            }
            Button("Vazgeç", role: .cancel) { pendingCampSelection = nil }
        } message: { camp in
            Text(selectionSummary(for: camp))
        }
        .fullScreenCover(isPresented: $showAddSubplan) {
            AddSubplanFlowView(daySlug: day.slug)
        }
        // Web senkronu günü kaldırırsa (eff → nil) açık sheet boş kalırdı — kapat.
        .onChange(of: eff == nil) { _, gone in
            if gone { showEdit = false }
        }
        .onDisappear { targetSaveTask?.cancel() }
        .preferredColorScheme(.dark)
    }

    private var subplansSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Alt planlar")
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.text)
                Spacer()
                Button { showAddSubplan = true } label: {
                    Image(systemName: "plus")
                        .frame(width: 32, height: 32)
                }
                .buttonStyle(.bordered)
                .accessibilityLabel("Alt plan ekle")
            }

            if let items = eff?.subplans, !items.isEmpty {
                VStack(spacing: 0) {
                    ForEach(items) { item in
                        NavigationLink {
                            SubplanDetailView(daySlug: day.slug, subplan: item)
                        } label: {
                            SubplanCompactRow(subplan: item)
                        }
                        .buttonStyle(.plain)
                        if item.id != items.last?.id {
                            Divider().overlay(Theme.line).padding(.leading, 48)
                        }
                    }
                }
                .background(Theme.panel, in: RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Theme.line))
            }
        }
    }

    private var communicationStateSection: some View {
        VStack(alignment: .leading, spacing: 9) {
            MonoLabel(text: "İletişim durumu", color: Theme.c4)
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: "message.badge")
                    .foregroundStyle(Theme.c4)
                VStack(alignment: .leading, spacing: 3) {
                    Text(exactStay.reservationStatus.title)
                        .font(.headline)
                        .foregroundStyle(Theme.text)
                    Text("Bu durum senin kaydındır; teslimatı, rezervasyonu veya karşı tarafın yanıtını doğrulamaz.")
                        .font(.footnote)
                        .foregroundStyle(Theme.muted)
                }
                Spacer(minLength: 0)
            }
            if exactTarget != nil {
                Button {
                    showTargetEditor = true
                } label: {
                    Label("İletişim ve konaklama ayrıntıları", systemImage: "square.and.pencil")
                }
                .buttonStyle(.bordered)
                .accessibilityHint("Hazır mesajı, iletişim kanallarını ve elle tutulan durumu açar")
            }
        }
        .card()
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
                canEditTarget: canEditArrivalTarget,
                actionText: role.isDriver ? routeActionText(state) : "Yalnız sürücü başlatabilir",
                onChoose: { showTargetPicker = true },
                onEdit: { showTargetEditor = true },
                onStart: {
                    guard canStart else { return }
                    Task {
                        guard let target = exactTarget else { return }
                        await LegLauncher.start(
                            stop: city,
                            target: target,
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
        let calendar = destinationCalendar
        let waypointMinutes = StayETAInput.boundedWaypointMinutes(day.waypoints?.compactMap(\.estimatedMinutes) ?? [])
        let eta = realLeg.map {
            StayETACalculator.calculate(.init(
                departure: effective.departTime,
                drivingSeconds: $0.time,
                waypointMinutes: waypointMinutes,
                borderBufferMinutes: day.borderBufferMinutes ?? 0,
                calendar: calendar
            ))
        }
        let checkIn = calendar.startOfDay(for: eta?.start ?? effective.departTime)
        let checkOut = calendar.date(byAdding: .day, value: effective.dayCount, to: checkIn)
        return StayDetails(
            checkIn: checkIn,
            checkOut: checkOut,
            estimatedArrival: eta?.text,
            estimatedArrivalMode: .automatic,
            estimatedArrivalWindow: eta
        )
    }

    private func derivedStay(from value: StayDetails) -> StayDetails {
        var result = value
        if result.checkIn == nil { result.checkIn = defaultStay.checkIn }
        if result.checkOut == nil { result.checkOut = defaultStay.checkOut }
        return StayArrivalModeResolver.applyingAutomaticDefault(defaultStay.estimatedArrivalWindow, to: result)
    }

    private var destinationCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "tr_TR")
        calendar.timeZone = destinationTimeZone
        return calendar
    }

    private var destinationTimeZone: TimeZone {
        let country = destinationStop?.country
        let identifier: String
        switch country {
        case "Bulgaristan": identifier = "Europe/Sofia"
        case "Sırbistan": identifier = "Europe/Belgrade"
        case "Romanya": identifier = "Europe/Bucharest"
        case "Macaristan": identifier = "Europe/Budapest"
        case "Polonya": identifier = "Europe/Warsaw"
        case "Litvanya": identifier = "Europe/Vilnius"
        case "Letonya": identifier = "Europe/Riga"
        default: identifier = "Europe/Istanbul"
        }
        return TimeZone(identifier: identifier) ?? TripPlanner.routeTimeZone
    }

    private func saveTarget(_ target: ArrivalTarget, stay: StayDetails) {
        guard canEditArrivalTarget else {
            targetError = "Bu rotada yalnızca görüntüleme yetkiniz var; varış yeri değiştirilemedi."
            return
        }
        if routeSession.activeStopId == destinationStop?.id,
           routeSession.activeTargetId != nil,
           routeSession.activeTargetId != target.id {
            routeSession.clear()
            LiveActivityManager.shared.endCurrent()
        }
        localTargetOverride = target
        localStayOverride = stay
        plan.setArrivalTarget(target, stay: stay, slug: day.slug)
        guard var stop = accountDestinationStop, let trip = workspace.selectedTrip,
              trip.access.canEditStops else { return }
        stop.arrivalTarget = AccountArrivalTarget(target)
        stop.stayDetails = AccountStayDetails(stay)
        guard let userID = account.user?.id else { return }
        targetSaveRevision += 1
        let context = ArrivalTargetSyncContext(
            revision: targetSaveRevision,
            tripID: trip.id,
            userID: userID
        )
        targetSaveTask?.cancel()
        targetSaveTask = Task {
            do {
                let changed = try await account.updateStop(trip: trip, stop: stop)
                guard !Task.isCancelled,
                      context.isCurrent(
                        revision: targetSaveRevision,
                        tripID: workspace.selectedTrip?.id,
                        userID: account.user?.id
                      )
                else { return }
                workspace.replace(changed)
                localTargetOverride = nil
                localStayOverride = nil
                targetError = nil
            } catch {
                guard !Task.isCancelled,
                      context.isCurrent(
                        revision: targetSaveRevision,
                        tripID: workspace.selectedTrip?.id,
                        userID: account.user?.id
                      )
                else { return }
                targetError = "Varış yeri cihazda kaydedildi ancak üyelerle eşitlenemedi: \(error.localizedDescription)"
            }
        }
    }

    private var destinationGeoPoint: GeoPoint? {
        guard let coordinate = destinationStop?.coordinate else { return nil }
        return GeoPoint(latitude: coordinate.latitude, longitude: coordinate.longitude)
    }

    private var selectedStayLocation: GeoPoint? {
        guard let target = exactTarget, target.hasValidCoordinate else { return nil }
        return GeoPoint(latitude: target.latitude, longitude: target.longitude)
    }

    private func arrivalTarget(for camp: CuratedCamp) -> ArrivalTarget {
        ArrivalTarget(
            id: "curated-camp:\(camp.id)",
            name: camp.name,
            kind: camp.supportsCaravan ? .campground : .other,
            latitude: camp.location.latitude,
            longitude: camp.location.longitude,
            formattedAddress: camp.address,
            phone: camp.phone,
            whatsAppPhone: camp.phone,
            email: camp.email,
            websiteURL: camp.websiteURL,
            maximumLengthMeters: camp.maximumLengthMeters,
            source: .user
        )
    }

    private func selectionSummary(for camp: CuratedCamp) -> String {
        var changes = ["Varış: \(camp.name)"]
        if let phone = camp.phone { changes.append("Telefon: \(phone)") }
        if let email = camp.email { changes.append("E-posta: \(email)") }
        if let maximum = camp.maximumLengthMeters {
            changes.append("Uzunluk sınırı: \(maximum.formatted(.number.precision(.fractionLength(0...1)))) m")
        }
        return changes.joined(separator: "\n")
    }

    private func openMap(name: String, location: GeoPoint, directions: Bool) {
        let item = MKMapItem(placemark: MKPlacemark(coordinate: CLLocationCoordinate2D(
            latitude: location.latitude,
            longitude: location.longitude
        )))
        item.name = name
        if directions {
            item.openInMaps(launchOptions: [MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeDriving])
        } else {
            item.openInMaps()
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
