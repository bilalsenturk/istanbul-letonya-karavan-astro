import SwiftUI

struct NearbyCampSection: View {
    let camps: [CuratedCamp]
    let cityCenter: GeoPoint?
    let selectedTargetID: String?
    let onOpenMaps: (CuratedCamp) -> Void
    let onContact: (CuratedCamp) -> Void
    let onSelect: (CuratedCamp) -> Void

    @State private var disclosedCamp: CuratedCamp?

    var body: some View {
        if !camps.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                MonoLabel(text: "Yakın kamp alternatifleri", color: Theme.c3)
                ForEach(camps) { camp in
                    CampOptionCard(
                        camp: camp,
                        distanceText: distanceText(for: camp),
                        isSelected: selectedTargetID == "curated-camp:\(camp.id)",
                        onOpenMaps: { onOpenMaps(camp) },
                        onContact: { onContact(camp) },
                        onSelect: { onSelect(camp) },
                        onShowSource: { disclosedCamp = camp }
                    )
                }
            }
            .sheet(item: $disclosedCamp) { camp in
                TravelSourceDetail(
                    title: camp.name,
                    source: camp.source,
                    media: camp.media,
                    verifiedAt: camp.verifiedAt
                )
            }
        }
    }

    private func distanceText(for camp: CuratedCamp) -> String? {
        guard let cityCenter else { return nil }
        return "Şehir merkezine kuş uçuşu \(cityCenter.distanceKm(to: camp.location).formatted(.number.precision(.fractionLength(1)))) km"
    }
}

struct NearbyAttractionSection: View {
    let attractions: [NearbyAttraction]
    let referenceLocation: GeoPoint?
    let onOpenMaps: (NearbyAttraction) -> Void

    @State private var disclosedAttraction: NearbyAttraction?

    var body: some View {
        if !attractions.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                MonoLabel(text: "Yakında gezilecek yerler", color: Theme.c1)
                ForEach(attractions) { attraction in
                    AttractionCard(
                        attraction: attraction,
                        distanceText: distanceText(for: attraction),
                        onOpenMaps: { onOpenMaps(attraction) },
                        onShowSource: { disclosedAttraction = attraction }
                    )
                }
            }
            .sheet(item: $disclosedAttraction) { attraction in
                TravelSourceDetail(
                    title: attraction.name,
                    source: attraction.source,
                    media: attraction.media,
                    verifiedAt: attraction.verifiedAt
                )
            }
        }
    }

    private func distanceText(for attraction: NearbyAttraction) -> String? {
        guard let referenceLocation else { return nil }
        return "Konaklamadan kuş uçuşu \(referenceLocation.distanceKm(to: attraction.location).formatted(.number.precision(.fractionLength(1)))) km"
    }
}

private struct CampOptionCard: View {
    let camp: CuratedCamp
    let distanceText: String?
    let isSelected: Bool
    let onOpenMaps: () -> Void
    let onContact: () -> Void
    let onSelect: () -> Void
    let onShowSource: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ZStack(alignment: .topLeading) {
                CampImage(
                    path: camp.media.url.absoluteString,
                    height: 154,
                    cornerRadius: 14,
                    accessibilityLabel: camp.media.alt ?? "\(camp.name) için temsili destinasyon görseli"
                )
                if camp.media.depictsCampground == false {
                    Text("TEMSİLİ DESTİNASYON · KAMP FOTOĞRAFI DEĞİL")
                        .font(.caption2.weight(.heavy))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 6)
                        .background(.black.opacity(0.78), in: Capsule())
                        .padding(8)
                        .accessibilityLabel("Temsili destinasyon görseli; kamp alanını göstermez")
                }
            }

            VStack(alignment: .leading, spacing: 7) {
                HStack(alignment: .firstTextBaseline) {
                    Text(camp.name)
                        .font(.headline)
                        .foregroundStyle(Theme.text)
                    Spacer(minLength: 8)
                    if isSelected {
                        Label("Seçili", systemImage: "checkmark.circle.fill")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(Theme.ok)
                    }
                }
                Text(camp.address)
                    .font(.subheadline)
                    .foregroundStyle(Theme.muted)
                if let distanceText {
                    Label(distanceText, systemImage: "point.topleft.down.to.point.bottomright.curvepath")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Theme.c2)
                }
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 8) { capabilityLabels }
                    VStack(alignment: .leading, spacing: 6) { capabilityLabels }
                }
                Text(camp.recommendation)
                    .font(.subheadline)
                    .foregroundStyle(Theme.dim)
                if let warning = camp.warning, !warning.isEmpty {
                    Label(warning, systemImage: "exclamationmark.triangle.fill")
                        .font(.footnote)
                        .foregroundStyle(Theme.warn)
                }
                if let disclosure = camp.media.disclosure, !disclosure.isEmpty {
                    Text(disclosure)
                        .font(.caption)
                        .foregroundStyle(Theme.muted)
                }
            }

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) { actionButtons }
                VStack(spacing: 8) { actionButtons }
            }
            Button("Kaynak ve fotoğraf bilgisi", action: onShowSource)
                .font(.footnote.weight(.semibold))
                .accessibilityHint("Doğrulama kaynağını, fotoğraf kredisini ve lisansını gösterir")
        }
        .padding(12)
        .background(Theme.panel, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Theme.line))
    }

    @ViewBuilder private var capabilityLabels: some View {
        Label(camp.supportsCaravan ? "Çekme karavan uygun" : "Karavan kabulünü teyit et", systemImage: "caravan.fill")
            .foregroundStyle(camp.supportsCaravan ? Theme.ok : Theme.warn)
        if let electricity = camp.hasElectricity {
            Label(electricity ? "Elektrik var" : "Elektrik yok", systemImage: "bolt.fill")
                .foregroundStyle(electricity ? Theme.ok : Theme.warn)
        }
        if let maximum = camp.maximumLengthMeters {
            Label("En fazla \(maximum.formatted(.number.precision(.fractionLength(0...1)))) m", systemImage: "ruler")
                .foregroundStyle(Theme.warn)
        }
    }

    @ViewBuilder private var actionButtons: some View {
        Button(action: onOpenMaps) { Label("Haritada Aç", systemImage: "map") }
            .buttonStyle(.bordered)
            .accessibilityLabel("\(camp.name) konumunu Haritalar'da aç")
        Button(action: onContact) { Label("İletişim", systemImage: "message") }
            .buttonStyle(.bordered)
            .accessibilityLabel("\(camp.name) için hazır iletişim ekranını aç")
        Button(action: onSelect) { Label("Bu kampı seç", systemImage: "checkmark.circle") }
            .buttonStyle(.bordered)
            .disabled(isSelected)
            .accessibilityLabel("\(camp.name) kampını varış yeri seç")
    }
}

private struct AttractionCard: View {
    let attraction: NearbyAttraction
    let distanceText: String?
    let onOpenMaps: () -> Void
    let onShowSource: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            CampImage(
                path: attraction.media.url.absoluteString,
                height: 150,
                cornerRadius: 14,
                symbol: "binoculars.fill",
                accessibilityLabel: attraction.media.alt ?? attraction.name
            )
            Text(attraction.name)
                .font(.headline)
                .foregroundStyle(Theme.text)
            Text(attraction.category.uppercased())
                .font(.caption2.weight(.heavy))
                .foregroundStyle(Theme.c1)
            Text(attraction.recommendation)
                .font(.subheadline)
                .foregroundStyle(Theme.dim)
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 10) { facts }
                VStack(alignment: .leading, spacing: 6) { facts }
            }
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) { actions }
                VStack(spacing: 8) { actions }
            }
        }
        .padding(12)
        .background(Theme.panel, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Theme.line))
    }

    @ViewBuilder private var facts: some View {
        if let distanceText {
            Label(distanceText, systemImage: "location.fill")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Theme.c2)
        }
        Label(durationText, systemImage: "clock")
            .font(.caption.weight(.semibold))
            .foregroundStyle(Theme.muted)
    }

    @ViewBuilder private var actions: some View {
        Button(action: onOpenMaps) { Label("Yol Tarifi", systemImage: "arrow.triangle.turn.up.right.diamond") }
            .buttonStyle(.bordered)
            .accessibilityLabel("\(attraction.name) için Haritalar'da yol tarifi aç")
        Button("Kaynak ve fotoğraf", action: onShowSource)
            .font(.footnote.weight(.semibold))
    }

    private var durationText: String {
        let hours = attraction.visitDurationMinutes / 60
        let minutes = attraction.visitDurationMinutes % 60
        if hours == 0 { return "\(minutes) dk ziyaret" }
        if minutes == 0 { return "\(hours) sa ziyaret" }
        return "\(hours) sa \(minutes) dk ziyaret"
    }
}

private struct TravelSourceDetail: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    let title: String
    let source: TravelSource
    let media: TravelMedia
    let verifiedAt: Date

    var body: some View {
        NavigationStack {
            List {
                Section("Doğrulama kaynağı") {
                    LabeledContent("Kaynak", value: source.name)
                    LabeledContent("Doğrulama tarihi", value: verifiedAt.formatted(date: .long, time: .omitted))
                    Button("Resmî kaynağı aç") { openURL(source.url) }
                }
                Section("Fotoğraf") {
                    LabeledContent("Kredi", value: media.credit)
                    LabeledContent("Lisans", value: media.license)
                    if let disclosure = media.disclosure {
                        Label(disclosure, systemImage: "info.circle.fill")
                    }
                    if let mediaSource = media.source {
                        Button("Fotoğraf kaynağını aç") { openURL(mediaSource.url) }
                    }
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Bitti") { dismiss() } }
            }
        }
    }
}
