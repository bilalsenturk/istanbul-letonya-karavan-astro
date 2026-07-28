import SwiftUI

// Departure state, intentionally kept typographic instead of card-based.
struct CountdownView: View {
    let departure: Date
    let routeStarted: Bool
    let activeRouteName: String?

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            let diff = departure.timeIntervalSince(context.date)
            if diff <= 0 {
                statusPanel
            } else {
                let days = Int(diff) / 86400
                let hours = (Int(diff) % 86400) / 3600
                let minutes = (Int(diff) % 3600) / 60

                Text("\(days) gün  \(hours) sa  \(minutes) dk")
                    .font(.system(size: 34, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.primary)
                    .minimumScaleFactor(0.72)
                    .lineLimit(1)
                    .contentTransition(.numericText())
                    .accessibilityLabel("Yola çıkmaya \(days) gün \(hours) saat \(minutes) dakika kaldı")
            }
        }
    }

    private var statusPanel: some View {
        Label {
            VStack(alignment: .leading, spacing: 2) {
                Text(routeStarted ? "Rota aktif" : "Rota bekliyor")
                    .font(.headline)
                Text(routeStarted ? (activeRouteName.map { "\($0) yönünde" } ?? "Canlı rota başladı")
                     : "Plan'dan Buraya git ile başlat")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        } icon: {
            Image(systemName: routeStarted ? "location.fill" : "clock")
                .foregroundStyle(routeStarted ? Color.accentColor : .secondary)
        }
    }
}
