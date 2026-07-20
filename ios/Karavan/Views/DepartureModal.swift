import SwiftUI

// Kalkış saati gelince ekrana düşen modal: tek dokunuşla etabı başlatır.
// Aynı etap için günde bir kez gösterilir (ertelenirse 15 dk sonra tekrar).
@MainActor
final class DeparturePrompt: ObservableObject {
    static let shared = DeparturePrompt()

    @Published var pendingStop: Stop?

    private var snoozedUntil: Date = .distantPast
    private var lastKey: String?
    private let defaults = UserDefaults.standard
    private let shownKey = "departure-prompt-shown"

    private init() {}

    /// Kalkış anı geldiyse ve bu etap için daha önce gösterilmediyse aç.
    /// Pencere 2 saat: app kapalıyken kalkış saati geçmiş olabilir, ayrıca
    /// erteleme sonrası tekrar açılabilmesi için yeterince geniş olmalı.
    func checkIfDue(departure: Date, nextStop: Stop?) {
        guard let nextStop, pendingStop == nil, Date() >= snoozedUntil else { return }

        let delta = Date().timeIntervalSince(departure)
        guard delta >= 0, delta <= 120 * 60 else { return }

        // Aynı etap + aynı gün için bir kez.
        let key = "\(shownKey)-\(nextStop.id)-\(Self.dayStamp(departure))"
        guard !defaults.bool(forKey: key) else { return }
        defaults.set(true, forKey: key)
        lastKey = key

        pendingStop = nextStop
    }

    /// Erteleme "gösterildi" sayılmaz — yoksa 15 dk sonra bir daha hiç açılmazdı.
    func snooze() {
        if let lastKey { defaults.removeObject(forKey: lastKey) }
        pendingStop = nil
        snoozedUntil = Date().addingTimeInterval(15 * 60)
    }

    func dismiss() {
        lastKey = nil
        pendingStop = nil
    }

    private static func dayStamp(_ d: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: d)
    }
}

struct DepartureModal: View {
    let stop: Stop
    let remainingKm: Int?
    let remainingTimeText: String
    let onStart: () -> Void
    let onSnooze: () -> Void

    var body: some View {
        VStack(spacing: 18) {
            ZStack {
                Circle().fill(Theme.gradWarm).frame(width: 72, height: 72)
                Image(systemName: "car.side.fill")
                    .font(.system(size: 30, weight: .bold))
                    .foregroundStyle(.white)
            }
            .padding(.top, 8)

            VStack(spacing: 6) {
                Text("Kalkış vakti")
                    .font(.system(size: 13, weight: .bold, design: .monospaced))
                    .foregroundStyle(Theme.c1)
                Text(stop.name)
                    .font(.system(size: 27, weight: .heavy, design: .rounded))
                    .foregroundStyle(Theme.text)
                    .multilineTextAlignment(.center)
                if let km = remainingKm {
                    Text("\(km) km · \(remainingTimeText)")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Theme.muted)
                        .monospacedDigit()
                }
            }

            VStack(spacing: 10) {
                Button(action: onStart) {
                    HStack(spacing: 8) {
                        Image(systemName: "play.fill").font(.system(size: 15, weight: .bold))
                        Text("Rotayı başlat").font(.system(size: 16, weight: .heavy, design: .rounded))
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Theme.gradWarm, in: RoundedRectangle(cornerRadius: 15, style: .continuous))
                }
                .buttonStyle(.plain)

                Button(action: onSnooze) {
                    Text("15 dakika sonra")
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundStyle(Theme.muted)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 11)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(22)
        .background(Theme.panel, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).strokeBorder(Theme.line, lineWidth: 1))
        .padding(.horizontal, 26)
        .presentationDetents([.height(400)])
        .presentationBackground(.clear)
    }
}
