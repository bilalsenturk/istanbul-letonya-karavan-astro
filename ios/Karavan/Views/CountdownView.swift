import SwiftUI

// Segmentli canlı geri sayım — web hero'sundaki tasarımın native karşılığı.
struct CountdownView: View {
    let departure: Date

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let diff = departure.timeIntervalSince(context.date)
            if diff <= 0 {
                HStack(spacing: 10) {
                    Text("🚐")
                    Text("Yoldayız!")
                        .font(.system(size: 26, weight: .heavy, design: .rounded))
                        .foregroundStyle(.white)
                }
                .padding(.horizontal, 22)
                .padding(.vertical, 16)
                .background(Theme.panel, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            } else {
                let days = Int(diff) / 86400
                let hours = (Int(diff) % 86400) / 3600
                let mins = (Int(diff) % 3600) / 60
                let secs = Int(diff) % 60

                HStack(spacing: 8) {
                    tile(String(days), "gün")
                    sep
                    tile(String(format: "%02d", hours), "saat")
                    sep
                    tile(String(format: "%02d", mins), "dk")
                    sep
                    tile(String(format: "%02d", secs), "sn")
                }
            }
        }
    }

    private var sep: some View {
        Text(":")
            .font(.system(size: 26, weight: .heavy, design: .rounded))
            .foregroundStyle(Theme.muted)
            .padding(.bottom, 18)
    }

    private func tile(_ value: String, _ label: String) -> some View {
        VStack(spacing: 5) {
            Text(value)
                .font(.system(size: 34, weight: .heavy, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(Theme.grad)
                .contentTransition(.numericText())
            Text(label.uppercased())
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .kerning(1.4)
                .foregroundStyle(Theme.muted)
        }
        .frame(minWidth: 64)
        .padding(.vertical, 12)
        .padding(.horizontal, 8)
        .background(Theme.panel, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Theme.line, lineWidth: 1)
        )
    }
}
