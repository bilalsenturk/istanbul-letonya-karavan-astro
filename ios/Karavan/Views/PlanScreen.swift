import SwiftUI

struct PlanScreen: View {
    @EnvironmentObject var store: TripStore
    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var selected: DayPlan.ID?

    var body: some View {
        Group {
            if Adaptive.isWide(sizeClass) {
                // iPad: solda gün listesi, sağda detay — ekranı gerçekten kullanır.
                NavigationSplitView {
                    dayList
                        .navigationTitle("Plan")
                        .toolbarBackground(.hidden, for: .navigationBar)
                } detail: {
                    ZStack {
                        Theme.bg.ignoresSafeArea()
                        if let trip = store.trip,
                           let index = trip.days.firstIndex(where: { $0.id == selected }) {
                            DayDetailView(day: trip.days[index], index: index)
                        } else {
                            ContentUnavailableView(
                                "Bir gün seç",
                                systemImage: "calendar.day.timeline.left",
                                description: Text("Soldaki listeden bir günü seçince detayı burada açılır.")
                            )
                            .foregroundStyle(Theme.muted)
                        }
                    }
                }
                .navigationSplitViewStyle(.balanced)
            } else {
                // iPhone: klasik yığın
                NavigationStack {
                    ZStack {
                        Theme.bg.ignoresSafeArea()
                        ScrollView {
                            VStack(alignment: .leading, spacing: 12) {
                                if let trip = store.trip {
                                    MonoLabel(text: "Gün gün plan · \(trip.days.count) etap", color: Theme.c2)
                                    VStack(spacing: 12) {
                                        ForEach(Array(trip.days.enumerated()), id: \.element.id) { index, day in
                                            NavigationLink {
                                                DayDetailView(day: day, index: index)
                                            } label: {
                                                TimelineRow(day: day, index: index,
                                                            isLast: index == trip.days.count - 1)
                                            }
                                            .buttonStyle(.plain)
                                        }
                                    }
                                }
                            }
                            .padding(18)
                            .frame(maxWidth: Adaptive.contentWidth(sizeClass))
                            .frame(maxWidth: .infinity)
                        }
                    }
                    .navigationTitle("Plan")
                    .toolbarBackground(.hidden, for: .navigationBar)
                }
            }
        }
        .preferredColorScheme(.dark)
        .onAppear {
            if selected == nil { selected = store.trip?.days.first?.id }
        }
    }

    private var dayList: some View {
        ZStack {
            Theme.bg.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if let trip = store.trip {
                        MonoLabel(text: "Gün gün plan · \(trip.days.count) etap", color: Theme.c2)
                        ForEach(Array(trip.days.enumerated()), id: \.element.id) { index, day in
                            Button {
                                selected = day.id
                            } label: {
                                TimelineRow(day: day, index: index, isLast: index == trip.days.count - 1)
                                    .background(
                                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                                            .fill(selected == day.id ? Theme.c2.opacity(0.10) : .clear)
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(16)
            }
        }
    }
}
