import SwiftUI

// Panel kartı: rota ülkelerinde dizel fiyatı, Kapıkule beklemesi ve kur.
struct RoadFeedCard: View {
    @EnvironmentObject var store: TripStore
    @EnvironmentObject var nav: NavProgressStore
    @EnvironmentObject var feed: RoadFeedService

    /// Rota üzerindeki ülke kodları (sırayla, tekrarsız).
    private var routeCodes: [String] {
        var seen: [String] = []
        for stop in store.trip?.stops ?? [] where !seen.contains(stop.code) {
            seen.append(stop.code)
        }
        return seen
    }

    var body: some View {
        if let data = feed.feed {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    MonoLabel(text: "Yol bülteni", color: Theme.c3)
                    Spacer()
                    if let t = feed.updatedAt {
                        Text(t.formatted(date: .omitted, time: .shortened))
                            .font(.system(size: 10, weight: .semibold, design: .monospaced))
                            .foregroundStyle(Theme.muted)
                    }
                }

                // Dizel — rota ülkeleri, en ucuz vurgulu
                let prices = data.fuel.filter { routeCodes.contains($0.country) }
                if !prices.isEmpty {
                    let cheapest = prices.min { $0.dieselEur < $1.dieselEur }?.country
                    VStack(alignment: .leading, spacing: 6) {
                        Label("Dizel (€/L)", systemImage: "fuelpump.fill")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(Theme.muted)
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(prices) { p in
                                    VStack(spacing: 3) {
                                        Text(p.country)
                                            .font(.system(size: 10, weight: .heavy, design: .rounded))
                                            .foregroundStyle(p.country == cheapest ? .black.opacity(0.85) : Theme.dim)
                                        Text(String(format: "%.2f", p.dieselEur))
                                            .font(.system(size: 13, weight: .bold, design: .rounded))
                                            .foregroundStyle(p.country == cheapest ? .black.opacity(0.85) : Theme.text)
                                    }
                                    .padding(.horizontal, 10).padding(.vertical, 7)
                                    .background(
                                        p.country == cheapest ? AnyShapeStyle(Theme.ok) : AnyShapeStyle(Theme.panel),
                                        in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    )
                                }
                            }
                        }
                        if let c = cheapest {
                            Text("En ucuz: \(c) — burada tam depo mantıklı.")
                                .font(.system(size: 11)).foregroundStyle(Theme.ok)
                        }
                    }
                }

                // Sınır beklemesi
                ForEach(data.borders) { b in
                    VStack(alignment: .leading, spacing: 3) {
                        HStack {
                            Label(b.name, systemImage: "flag.2.crossed.fill")
                                .font(.system(size: 12, weight: .bold, design: .rounded))
                                .foregroundStyle(Theme.text)
                            Spacer()
                            if let out = b.outbound {
                                Text(out)
                                    .font(.system(size: 12, weight: .heavy, design: .rounded))
                                    .foregroundStyle(Theme.c1)
                            }
                        }
                        if let note = b.note {
                            Text(note).font(.system(size: 11)).foregroundStyle(Theme.muted)
                        }
                    }
                    .padding(10)
                    .background(Theme.panel, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }

                // Kur — sıradaki durağın para birimi öne çıkar
                if !data.rates.isEmpty {
                    let nextCode = nav.nextStop?.code
                    let nextCurrency = nextCode.flatMap { RoadFeedService.currency(for: $0) }
                    VStack(alignment: .leading, spacing: 6) {
                        Label("1 € =", systemImage: "eurosign.circle.fill")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(Theme.muted)
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(["TRY", "BGN", "RON", "HUF", "PLN"], id: \.self) { cur in
                                    if let rate = data.rates[cur] {
                                        let isNext = cur == nextCurrency
                                        HStack(spacing: 4) {
                                            Text(cur)
                                                .font(.system(size: 10, weight: .heavy, design: .monospaced))
                                            Text(rate >= 100 ? String(format: "%.0f", rate) : String(format: "%.2f", rate))
                                                .font(.system(size: 12, weight: .bold, design: .rounded))
                                        }
                                        .foregroundStyle(isNext ? Theme.c2 : Theme.dim)
                                        .padding(.horizontal, 9).padding(.vertical, 6)
                                        .background(
                                            isNext ? Theme.c2.opacity(0.14) : Theme.panel,
                                            in: Capsule()
                                        )
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .card()
        }
    }
}
