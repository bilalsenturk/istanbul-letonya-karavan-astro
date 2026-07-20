import SwiftUI

struct DayDetailView: View {
    let day: DayPlan
    let index: Int
    @EnvironmentObject var store: TripStore
    @EnvironmentObject var plan: TripPlanStore
    @EnvironmentObject var routeStore: RouteStore
    @Environment(\.openURL) private var openURL
    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var showEdit = false

    /// Türetilmiş gün (kullanıcı düzenlemeleri + hesaplanmış tarih).
    private var eff: EffectiveDay? {
        plan.day(store.trip, slug: day.slug)
    }

    private var destinationStop: Stop? {
        store.trip?.stop(matching: eff?.destination ?? day.destination)
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
                    CampImage(path: day.camp.image, height: 200)

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
                            chip("🛣️ \(e?.distanceKm ?? day.distanceKm)")
                            chip("⏱️ \(e?.duration ?? day.duration)")
                        }
                        chip("⛽ \(e?.fuel ?? day.fuel)")

                        if let dest = destinationStop {
                            HStack(spacing: 10) {
                                Button {
                                    NavApp.openAppleMaps(to: dest)
                                } label: {
                                    Label("Apple Maps'te sür", systemImage: "arrow.triangle.turn.up.right.circle.fill")
                                        .font(.system(size: 14, weight: .bold, design: .rounded))
                                        .foregroundStyle(.white)
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 12)
                                        .background(Theme.gradWarm, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
                                }
                                Button {
                                    NavApp.openGoogleMaps(to: dest)
                                } label: {
                                    Label("Google Maps", systemImage: "globe.europe.africa.fill")
                                        .font(.system(size: 14, weight: .bold, design: .rounded))
                                        .foregroundStyle(.white)
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 12)
                                        .background(Theme.panel, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 13, style: .continuous)
                                                .strokeBorder(Theme.line, lineWidth: 1)
                                        )
                                }
                            }
                            .padding(.top, 4)
                        }
                    }

                    waypointsSection
                    camerasSection

                    section("Sorun senaryoları", items: day.risks, tint: Theme.bad)
                    section("Fırsatlar", items: day.opportunities, tint: Theme.ok)
                    section("Yedek plan", items: day.contingencies, tint: Theme.warn)

                    VStack(alignment: .leading, spacing: 8) {
                        MonoLabel(text: "Kamp", color: Theme.c4)
                        Text(e?.campName ?? day.camp.name)
                            .font(.system(size: 18, weight: .bold, design: .rounded))
                            .foregroundStyle(Theme.text)
                        Text(e?.campPlace ?? day.camp.place)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(Theme.dim)
                        Text(day.camp.note)
                            .font(.system(size: 13.5))
                            .foregroundStyle(Theme.muted)
                        if let url = URL(string: day.camp.link) {
                            Link(destination: url) {
                                Text("Haritada aç")
                                    .font(.system(size: 14, weight: .bold, design: .rounded))
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 10)
                                    .background(Theme.gradWarm, in: Capsule())
                            }
                            .padding(.top, 4)
                        }
                    }
                    .card()

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
        .preferredColorScheme(.dark)
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

    private func chip(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(Theme.dim)
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
