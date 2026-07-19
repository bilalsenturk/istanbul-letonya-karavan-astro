import SwiftUI

struct DashboardView: View {
    @EnvironmentObject var store: TripStore
    @EnvironmentObject var loc: LocationManager
    @EnvironmentObject var weather: WeatherService

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.bg.ignoresSafeArea()
                aurora

                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        header
                        if let trip = store.trip {
                            if let departure = trip.departureDate {
                                VStack(alignment: .leading, spacing: 10) {
                                    MonoLabel(text: "Yola çıkmaya kalan", color: Theme.c1)
                                    CountdownView(departure: departure)
                                }
                            }
                            metricRow(trip: trip)
                            LiveLocationCard()
                            weatherStrip
                            timeline(trip: trip)
                        } else {
                            ProgressView().tint(.white).padding(40)
                        }
                    }
                    .padding(.horizontal, 18)
                    .padding(.bottom, 34)
                    .frame(maxWidth: 760)
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
                await weather.refresh(stops: stops)
            }
        }
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
                Text("🚐")
                MonoLabel(text: "İstanbul → Riga", color: Theme.dim)
                Spacer()
                if let t = weather.updatedAt {
                    MonoLabel(text: t.formatted(date: .omitted, time: .shortened))
                }
            }
            Text("Karavan Brifingi")
                .font(.system(size: 38, weight: .heavy, design: .rounded))
                .foregroundStyle(Theme.text)
        }
        .padding(.top, 8)
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

    private var weatherStrip: some View {
        VStack(alignment: .leading, spacing: 10) {
            MonoLabel(text: "Duraklarda hava · canlı", color: Theme.c4)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(weather.items) { w in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack(spacing: 5) {
                                Text(w.flag).font(.system(size: 13))
                                Text(w.name)
                                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                                    .foregroundStyle(Theme.dim)
                            }
                            HStack(spacing: 7) {
                                Text(w.icon).font(.system(size: 22))
                                Text("\(w.temp)°")
                                    .font(.system(size: 26, weight: .heavy, design: .rounded))
                                    .foregroundStyle(Theme.text)
                            }
                            Text(w.isRaining ? "\(w.desc) · ☔" : w.desc)
                                .font(.system(size: 10.5, weight: .medium))
                                .foregroundStyle(Theme.muted)
                                .lineLimit(1)
                        }
                        .padding(12)
                        .frame(width: 128, alignment: .leading)
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

    private func timeline(trip: TripData) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            MonoLabel(text: "Gün gün plan · \(trip.days.count) etap", color: Theme.c2)
            VStack(spacing: 12) {
                ForEach(Array(trip.days.enumerated()), id: \.element.id) { index, day in
                    NavigationLink {
                        DayDetailView(day: day, index: index)
                    } label: {
                        TimelineRow(day: day, index: index, isLast: index == trip.days.count - 1)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

struct TimelineRow: View {
    let day: DayPlan
    let index: Int
    let isLast: Bool

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
                Text(day.date.uppercased())
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .kerning(1.0)
                    .foregroundStyle(Theme.muted)

                Text(day.isRestDay ? "\(day.origin) · Dinlenme" : "\(day.origin) → \(day.destination)")
                    .font(.system(size: 19, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.text)

                if !day.isRestDay {
                    Text("🛣️ \(day.distanceKm)  ·  ⏱️ \(day.duration)")
                        .font(.system(size: 12.5, weight: .medium))
                        .foregroundStyle(Theme.dim)
                }

                HStack {
                    Text("⛺ \(day.camp.place)")
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
