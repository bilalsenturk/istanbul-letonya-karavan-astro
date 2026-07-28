import MapKit
import SwiftUI

struct PlanScreen: View {
    @EnvironmentObject private var store: TripStore
    @EnvironmentObject private var plan: TripPlanStore
    @State private var showMap = ProcessInfo.processInfo.arguments.contains("-ui-preview-map")

    var body: some View {
        NavigationStack {
            List {
                ForEach(plan.days(store.trip)) { day in
                    Section {
                        NavigationLink {
                            DayDetailView(day: day.base, index: day.index)
                        } label: {
                            PlanDayRow(day: day)
                        }

                        ForEach(day.subplans) { item in
                            NavigationLink {
                                SubplanDetailView(daySlug: day.base.slug, subplan: item)
                            } label: {
                                SubplanCompactRow(subplan: item)
                            }
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(Theme.bg)
            .navigationTitle("Plan")
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button { showMap = true } label: {
                        Image(systemName: "map")
                    }
                    .accessibilityLabel("Plan haritası")
                }
            }
        }
        .fullScreenCover(isPresented: $showMap) {
            PlanMapView()
        }
        .preferredColorScheme(.dark)
    }

}

private struct PlanDayRow: View {
    let day: EffectiveDay
    @EnvironmentObject private var routeStore: RouteStore
    @EnvironmentObject private var store: TripStore
    @EnvironmentObject private var plan: TripPlanStore
    @State private var automaticTravelMinutes: Int?

    var body: some View {
        HStack(spacing: 12) {
            VStack(spacing: 2) {
                Text("\(day.index + 1)")
                    .font(.system(size: 14, weight: .black, design: .rounded))
                Text(day.shortDateText)
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(Theme.muted)
            }
            .foregroundStyle(Theme.text)
            .frame(width: 36, height: 42)
            .background(Theme.c2.opacity(0.14), in: RoundedRectangle(cornerRadius: 7))

            VStack(alignment: .leading, spacing: 4) {
                Text(day.isRestDay ? day.origin : day.destination)
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.text)
                    .lineLimit(1)
                Text(summary)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Theme.muted)
                    .lineLimit(1)
                if let target = day.arrivalTarget?.name {
                    Label(target, systemImage: "tent.fill")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Theme.dim)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 8)
        }
        .padding(12)
        .contentShape(Rectangle())
        .task(id: routeSignature) { await refreshAutomaticRoute() }
    }

    private var summary: String {
        guard !day.isRestDay else { return "Dinlenme günü" }
        let departure = day.departTime.formatted(date: .omitted, time: .shortened)
        if let minutes = automaticTravelMinutes {
            let arrival = day.departTime.addingTimeInterval(TimeInterval(minutes * 60))
                .formatted(date: .omitted, time: .shortened)
            return "\(departure) → \(arrival) · \(minutes / 60) sa \(minutes % 60) dk"
        }
        guard let legIndex = day.legIndex, let leg = routeStore.legInfo(legIndex) else {
            return "\(departure) çıkış · \(day.duration)"
        }
        let minutes = Int((leg.time / 60).rounded())
        let arrival = day.departTime.addingTimeInterval(leg.time)
            .formatted(date: .omitted, time: .shortened)
        return "\(departure) → \(arrival) · \(minutes / 60) sa \(minutes % 60) dk"
    }

    private var routeSignature: String {
        guard let source = automaticSource, let target = automaticTarget else { return day.id }
        return "\(source.latitude),\(source.longitude)>\(target.latitude),\(target.longitude)"
    }

    /// Bir önceki günün son alt planı varsa yeni etap oradan başlar. Alt plan
    /// yoksa önceki kesin konaklama hedefi, o da yoksa şehir koordinatı kullanılır.
    private var automaticSource: CLLocationCoordinate2D? {
        guard let trip = store.trip else { return nil }
        let days = plan.days(trip)
        guard let index = days.firstIndex(where: { $0.id == day.id }) else { return nil }
        if index == 0 { return trip.stop(matching: day.origin)?.coordinate }
        let previous = days[index - 1]
        if let item = previous.subplans.last {
            return CLLocationCoordinate2D(latitude: item.latitude, longitude: item.longitude)
        }
        if let target = previous.arrivalTarget, target.hasValidCoordinate {
            return CLLocationCoordinate2D(latitude: target.latitude, longitude: target.longitude)
        }
        return trip.stop(matching: day.origin)?.coordinate
    }

    private var automaticTarget: CLLocationCoordinate2D? {
        if let target = day.arrivalTarget, target.hasValidCoordinate {
            return CLLocationCoordinate2D(latitude: target.latitude, longitude: target.longitude)
        }
        return store.trip?.stop(matching: day.destination)?.coordinate
    }

    private func refreshAutomaticRoute() async {
        guard !day.isRestDay, let source = automaticSource, let target = automaticTarget else {
            automaticTravelMinutes = nil
            return
        }
        let request = MKDirections.Request()
        request.source = MKMapItem(placemark: MKPlacemark(coordinate: source))
        request.destination = MKMapItem(placemark: MKPlacemark(coordinate: target))
        request.transportType = .automobile
        if let response = try? await MKDirections(request: request).calculate(),
           let route = response.routes.first {
            automaticTravelMinutes = max(1, Int(ceil(route.expectedTravelTime / 60)))
        } else {
            automaticTravelMinutes = nil
        }
    }

}

struct SubplanCompactRow: View {
    let subplan: DaySubplan

    var body: some View {
        HStack(spacing: 12) {
            Text(Self.timeText(subplan.startMinute))
                .font(.system(size: 12, weight: .bold, design: .monospaced))
                .foregroundStyle(Theme.c2)
                .frame(width: 38, alignment: .leading)
            Image(systemName: "arrow.turn.down.right")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(Theme.muted)
            VStack(alignment: .leading, spacing: 2) {
                Text(subplan.title)
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(Theme.text)
                    .lineLimit(1)
                Text("\(subplan.durationMinutes) dk · \(subplan.placeName)")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.muted)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
        }
        .padding(.horizontal, 12)
        .frame(minHeight: 52)
        .contentShape(Rectangle())
    }

    static func timeText(_ minute: Int) -> String {
        String(format: "%02d:%02d", max(0, minute) / 60 % 24, max(0, minute) % 60)
    }
}

private struct PlanMapView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            MapScreen()
                .navigationTitle("Plan haritası")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Kapat") { dismiss() }
                    }
                }
        }
    }
}
