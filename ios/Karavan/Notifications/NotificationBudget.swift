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

    /// Bütçe onayı verir VE aynı anda zaman damgasını günceller. Bu iki işin
    /// tek çağrıda birleşmesi kasıtlı bir tasarım kararı değil, çağıranın
    /// kolaylığı için — asıl gönderim burada değil, çağıran tarafta olur.
    /// Bu yüzden allow() true dönüp de gönderim başka bir sebeple (bildirim
    /// izni reddi, sistem kısıtı) gerçekleşmezse, damga zaten atılmış olur
    /// ve o türün bekleme süresi boşa harcanır — kritik türlerde
    /// (borderApproach, lowBattery) bu, gerçek bir sonraki fırsatın
    /// sessizce kaybolması demektir. Bu riski gidermek için: gönderim
    /// başarısız olduğunda çağıran release(_:) ile damgayı geri almalı.
    mutating func allow(_ kind: NotifKind, now: Date) -> Bool {
        let limit = kind.isCritical ? Self.criticalCooldown : Self.cooldown
        if let last = lastSent[kind.rawValue], now.timeIntervalSince(last) < limit {
            return false
        }
        lastSent[kind.rawValue] = now
        return true
    }

    /// allow() bütçeyi geçirdikten SONRA asıl bildirim gönderilemezse
    /// (izin reddi, sistem kısıtı, planlama hatası vb.) çağrılır. allow()
    /// tarafından atılan zaman damgasını siler, böylece o türün bekleme
    /// hakkı boşa harcanmamış olur ve bir sonraki GERÇEK fırsat
    /// engellenmez. Damga hiç atılmamışsa (ör. yanlışlıkla çağrılırsa)
    /// no-op'tur — var olmayan bir anahtarı silmek zararsızdır.
    mutating func release(_ kind: NotifKind) {
        lastSent.removeValue(forKey: kind.rawValue)
    }
}
