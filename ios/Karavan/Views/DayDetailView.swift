import SwiftUI

struct DayDetailView: View {
    let day: DayPlan
    let index: Int
    @EnvironmentObject var store: TripStore

    private var destinationStop: Stop? {
        store.trip?.stop(matching: day.destination)
    }

    var body: some View {
        ZStack {
            Theme.bg.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 8) {
                        MonoLabel(text: "\(index + 1). gün · \(day.date)", color: Theme.c1)
                        Text(day.isRestDay ? "\(day.origin)\nDinlenme günü" : "\(day.origin) →\n\(day.destination)")
                            .font(.system(size: 32, weight: .heavy, design: .rounded))
                            .foregroundStyle(Theme.text)
                    }

                    if !day.isRestDay {
                        HStack(spacing: 8) {
                            chip("🛣️ \(day.distanceKm)")
                            chip("⏱️ \(day.duration)")
                        }
                        chip("⛽ \(day.fuel)")

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

                    section("Sorun senaryoları", items: day.risks, tint: Theme.bad)
                    section("Fırsatlar", items: day.opportunities, tint: Theme.ok)
                    section("Yedek plan", items: day.contingencies, tint: Theme.warn)

                    VStack(alignment: .leading, spacing: 8) {
                        MonoLabel(text: "Kamp", color: Theme.c4)
                        Text(day.camp.name)
                            .font(.system(size: 18, weight: .bold, design: .rounded))
                            .foregroundStyle(Theme.text)
                        Text(day.camp.place)
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
                }
                .padding(18)
                .frame(maxWidth: 700)
                .frame(maxWidth: .infinity)
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .preferredColorScheme(.dark)
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
