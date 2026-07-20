import Foundation

// Bildirim disiplini. Yolculuk sekiz gün sürüyor; bildirim yorgunluğu
// gerçek bir risk — yorulan kullanıcı hepsini kapatır ve kritik olanı da
// kaçırır. Anons motorundaki (AnnouncementEngine) kısıtlama mantığının eşi.
struct NotificationBudget {
    /// Normal bildirimler: aynı türden 45 dakikada bir.
    static let cooldown: TimeInterval = 45 * 60
    /// Kritik bildirimler: aynı türden 10 dakikada bir.
    static let criticalCooldown: TimeInterval = 10 * 60

    private var lastSent: [String: Date] = [:]

    mutating func allow(_ kind: NotifKind, now: Date) -> Bool {
        let limit = kind.isCritical ? Self.criticalCooldown : Self.cooldown
        if let last = lastSent[kind.rawValue], now.timeIntervalSince(last) < limit {
            return false
        }
        lastSent[kind.rawValue] = now
        return true
    }
}
