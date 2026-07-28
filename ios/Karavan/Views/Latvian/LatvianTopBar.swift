import SwiftUI

/// Kurs ana ekranının üst çubuğu: gün serisi, can, XP ve günlük hedef halkası.
///
/// Hiçbir şey hesaplamıyor ve **saat okumuyor** — dört değeri hazır alıyor
/// (bkz. `LatvianCourseModel`). Motorun "gizli saat yok" kuralı arayüzde de
/// geçerli: `Date()` tek bir yerde, kurs modelinde okunuyor.
///
/// Her rozet tek bir erişilebilirlik ögesi. Çocukları ayrı ayrı bırakılsaydı
/// VoiceOver beş kalbi beş ayrı "kalp" olarak okurdu; `children: .ignore`
/// beşini "5 candan 3 tanesi dolu" tek cümlesine indiriyor.
struct LatvianTopBar: View {
    let streakDays: Int
    let hearts: Int
    let xp: Int
    /// Bugün ders yapıldı mı. Halka dolu ya da boş — günlük hedef tek bir ders
    /// olduğu için ara değer yok ve olmayan bir kesirlilik uydurulmuyor.
    let isDailyGoalDone: Bool
    /// Hatırlatmaların tek anahtarı. Ayrı bir ayar ekranı açmak yerine burada:
    /// kursun tek ekranı var ve bildirim bu kursa ait tek ayar.
    let notificationsEnabled: Bool
    let onToggleNotifications: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 14) {
            badge(
                icon: "flame.fill",
                value: "\(streakDays)",
                tone: Theme.c1,
                label: "\(streakDays) günlük seri"
            )
            heartRow
            badge(
                icon: "bolt.fill",
                value: "\(xp)",
                tone: Theme.c4,
                label: "\(xp) XP"
            )
            Spacer(minLength: 0)
            notificationToggle
            dailyGoalRing
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }

    // MARK: - Parçalar

    private var heartRow: some View {
        HStack(spacing: 3) {
            ForEach(0..<LatvianProgress.maxHearts, id: \.self) { index in
                Image(systemName: index < hearts ? "heart.fill" : "heart")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(index < hearts ? Theme.bad : Theme.muted)
                    .scaleEffect(index < hearts ? 1 : 0.86)
            }
        }
        .animation(motion(LatvianMotion.pop), value: hearts)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(heartsLabel)
    }

    private var heartsLabel: String {
        hearts <= 0
            ? "Can kalmadı"
            : "\(LatvianProgress.maxHearts) candan \(hearts) tanesi dolu"
    }

    private var notificationToggle: some View {
        Button(action: onToggleNotifications) {
            Image(systemName: notificationsEnabled ? "bell.fill" : "bell.slash.fill")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(notificationsEnabled ? Theme.c4 : Theme.muted)
                .frame(width: 28, height: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Letonca hatırlatmaları")
        .accessibilityValue(notificationsEnabled ? "Açık" : "Kapalı")
        .accessibilityHint(notificationsEnabled
                           ? "Kapatmak için iki kez dokun. Kurulu hatırlatmalar da silinir."
                           : "Açmak için iki kez dokun.")
    }

    private var dailyGoalRing: some View {
        ZStack {
            Circle()
                .stroke(Theme.line, lineWidth: 4)
            Circle()
                .trim(from: 0, to: isDailyGoalDone ? 1 : 0)
                .stroke(Theme.ok, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                .rotationEffect(.degrees(-90))
            if isDailyGoalDone {
                Image(systemName: "checkmark")
                    .font(.system(size: 11, weight: .black))
                    .foregroundStyle(Theme.ok)
            }
        }
        .frame(width: 28, height: 28)
        .animation(motion(LatvianMotion.slide), value: isDailyGoalDone)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(isDailyGoalDone ? "Günlük hedef tamam" : "Günlük hedef: bugün henüz ders yok")
    }

    private func badge(icon: String, value: String, tone: Color, label: String) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(tone)
            Text(value)
                .font(.system(size: 15, weight: .heavy, design: .rounded))
                .foregroundStyle(Theme.text)
                .monospacedDigit()
                // Sayının yerinde değişmesi için hem `contentTransition` hem
                // bir eğri gerekiyor: eğri olmadan geçiş hiç çalışmıyor.
                .contentTransition(.numericText())
                .animation(motion(LatvianMotion.count), value: value)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
    }

    private func motion(_ base: Animation) -> Animation {
        LatvianMotion.adaptive(base, reduceMotion: reduceMotion)
    }
}

#Preview("Üst çubuk") {
    VStack(spacing: 0) {
        LatvianTopBar(streakDays: 7, hearts: 3, xp: 1240, isDailyGoalDone: true,
                      notificationsEnabled: true, onToggleNotifications: {})
        LatvianTopBar(streakDays: 0, hearts: 0, xp: 0, isDailyGoalDone: false,
                      notificationsEnabled: false, onToggleNotifications: {})
    }
    .frame(maxHeight: .infinity)
    .background(Theme.bg)
}
