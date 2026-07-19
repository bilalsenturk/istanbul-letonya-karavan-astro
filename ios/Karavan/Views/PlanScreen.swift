import SwiftUI

struct PlanScreen: View {
    @EnvironmentObject var store: TripStore

    var body: some View {
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
                                        TimelineRow(day: day, index: index, isLast: index == trip.days.count - 1)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }
                    .padding(18)
                    .frame(maxWidth: 760)
                    .frame(maxWidth: .infinity)
                }
            }
            .navigationTitle("Plan")
            .toolbarBackground(.hidden, for: .navigationBar)
        }
        .preferredColorScheme(.dark)
    }
}
