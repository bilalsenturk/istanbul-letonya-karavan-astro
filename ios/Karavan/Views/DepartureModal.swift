import SwiftUI

// Kalkış saati gelince ekrana düşen modal: tek dokunuşla etabı başlatır.
// Aynı etap için günde bir kez gösterilir (ertelenirse 15 dk sonra tekrar).
@MainActor
final class DeparturePrompt: ObservableObject {
    static let shared = DeparturePrompt()

    @Published var pendingStop: Stop?

    private var lastKey: String?
    /// Sheet'in açılmayı beklediği an — açılınca markShown() sıfırlar.
    private var pendingSince: Date?
    private let defaults = UserDefaults.standard
    private let shownKey = "departure-prompt-shown"
    private let snoozeKey = "departure-prompt-snoozed-until"

    /// Erteleme kalıcı: 15 dk içinde yeniden açılışta modal hemen geri gelmez.
    private var snoozedUntil: Date {
        get {
            let t = defaults.double(forKey: snoozeKey)
            return t > 0 ? Date(timeIntervalSince1970: t) : .distantPast
        }
        set { defaults.set(newValue.timeIntervalSince1970, forKey: snoozeKey) }
    }

    private init() {}

    /// Kalkış anı geldiyse ve bu etap için daha önce gösterilmediyse aç.
    /// Pencere 2 saat: app kapalıyken kalkış saati geçmiş olabilir, ayrıca
    /// erteleme sonrası tekrar açılabilmesi için yeterince geniş olmalı.
    func checkIfDue(departure: Date, nextStop: Stop?) {
        guard let nextStop, Date() >= snoozedUntil else { return }

        // Başka bir sheet açıkken (ör. rol seçimi) .sheet(item:) düşer: modal hiç
        // görünmez ama pendingStop takılı kalır ve sonraki tüm uyarıları kilitler.
        // 30 sn içinde açılmadıysa düşmüş say, yeniden denemeye izin ver.
        if pendingStop != nil {
            guard let since = pendingSince, Date().timeIntervalSince(since) > 30 else { return }
            pendingStop = nil
            pendingSince = nil
            lastKey = nil
        }

        let delta = Date().timeIntervalSince(departure)
        guard delta >= 0, delta <= 120 * 60 else { return }

        // Aynı etap + aynı gün için bir kez.
        let key = DeparturePromptKey.key(prefix: shownKey, stopId: nextStop.id, departure: departure)
        guard !defaults.bool(forKey: key) else { return }
        lastKey = key

        pendingStop = nextStop
        pendingSince = Date()
    }

    /// Sheet gerçekten ekrana gelince çağrılır (DepartureModal.onAppear).
    /// "Gösterildi" bayrağı ancak burada yazılır — başka bir sheet açıkken
    /// .sheet(item:) düşerse modal kaybolur ama gösterilmiş sayılmaz.
    func markShown() {
        pendingSince = nil
        if let lastKey { defaults.set(true, forKey: lastKey) }
    }

    /// Erteleme "gösterildi" sayılmaz — yoksa 15 dk sonra bir daha hiç açılmazdı.
    func snooze() {
        if let lastKey { defaults.removeObject(forKey: lastKey) }
        pendingStop = nil
        pendingSince = nil
        snoozedUntil = Date().addingTimeInterval(15 * 60)
    }

    func dismiss() {
        lastKey = nil
        pendingStop = nil
        pendingSince = nil
    }

}

struct DepartureModal: View {
    let stop: Stop
    let remainingKm: Int?
    let remainingTimeText: String
    let onOpenRoutes: () -> Void
    let onSnooze: () -> Void

    @EnvironmentObject private var role: RoleStore

    var body: some View {
        VStack(spacing: 22) {
            Image(systemName: "car.side.fill")
                .font(.system(size: 38, weight: .semibold))
                .foregroundStyle(.tint)
                .padding(.top, 8)

            VStack(spacing: 6) {
                Text("Kalkış vakti")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text(stop.name)
                    .font(.title2.bold())
                    .multilineTextAlignment(.center)
                if let km = remainingKm {
                    Text("\(km) km · \(remainingTimeText)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }

            VStack(spacing: 10) {
                Button(action: onOpenRoutes) {
                    Label("Planı aç", systemImage: "point.topleft.down.curvedto.point.bottomright.up")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(!role.isDriver)

                // Navigasyonu yalnızca Plan ekranındaki "Buraya git" başlatır.
                if !role.isDriver {
                    Text("Navigasyonu sürücü başlatır")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("Başlatma Plan ekranında, sıradaki durakta Buraya git ile yapılır.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }

                Button("15 dakika sonra", action: onSnooze)
                    .buttonStyle(.bordered)
                    .controlSize(.large)
            }
        }
        .padding(22)
        .presentationDetents([.height(400)])
        // Aşağı kaydırarak kapatma günde-bir-kez hakkını tüketir; yalnızca
        // "Planı aç" / "15 dakika sonra" kapatabilsin.
        .interactiveDismissDisabled()
        .onAppear { DeparturePrompt.shared.markShown() }
    }
}
