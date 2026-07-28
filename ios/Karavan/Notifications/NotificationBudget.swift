import Foundation

// Bildirim disiplini. Yolculuk sekiz gün sürüyor; bildirim yorgunluğu
// gerçek bir risk — yorulan kullanıcı hepsini kapatır ve kritik olanı da
// kaçırır. Anons motorundaki (AnnouncementEngine) kısıtlama mantığının eşi.
struct NotificationBudget {
    /// Normal bildirimler: aynı türden 45 dakikada bir.
    static let cooldown: TimeInterval = 45 * 60
    /// Kritik bildirimler: aynı türden 10 dakikada bir.
    static let criticalCooldown: TimeInterval = 10 * 60

    /// Damgalar UserDefaults'ta tutulur — yalnızca bellekte kalsaydı uygulama
    /// kapanıp açılınca (force-quit) bütün bekleme süreleri sıfırlanırdı.
    /// Anons motorundaki (AnnouncementEngine) `annPlayed.*` kalıbının eşi.
    private static let defaultsKey = "notifBudget.lastSent"

    /// UI'sız CLI doğrulamalarında (ios/Tests) bundle kimliği yoktur; o ortamda
    /// kalıcılık kapalı kalır ki bağımsız test çalıştırmaları aynı damgalarla
    /// birbirini etkilemesin. Gerçek uygulamada her zaman kalıcıdır.
    private static let persists = Bundle.main.bundleIdentifier != nil

    private var lastSent: [String: Date] {
        get {
            guard Self.persists else { return inMemory }
            let raw = UserDefaults.standard.dictionary(forKey: Self.defaultsKey) as? [String: TimeInterval] ?? [:]
            return raw.mapValues { Date(timeIntervalSince1970: $0) }
        }
        set {
            guard Self.persists else { inMemory = newValue; return }
            UserDefaults.standard.set(newValue.mapValues { $0.timeIntervalSince1970 },
                                      forKey: Self.defaultsKey)
        }
    }

    private var inMemory: [String: Date] = [:]

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
        allow(kind, key: nil, now: now)
    }

    /// Aynı türün farklı BAĞLAMLARI (ör. arrivalSoon için durak adı, kur
    /// sıçraması için para birimi kodu) ayrı bütçe sayılır — Sofya'ya
    /// yaklaşma bildirimi Bükreş hakkını, TRY sıçraması RON hakkını yemez.
    mutating func allow(_ kind: NotifKind, key: String?, now: Date) -> Bool {
        let limit = kind.isCritical ? Self.criticalCooldown : Self.cooldown
        let storageKey = Self.storageKey(kind, key: key)
        var sent = lastSent
        // now < last: saat geriye alınmış ya da damga gelecekte — bekleme
        // sayma (aksi halde saat kayması türü süresiz kilitler).
        if let last = sent[storageKey], now >= last, now.timeIntervalSince(last) < limit {
            return false
        }
        sent[storageKey] = now
        lastSent = sent
        return true
    }

    /// allow() bütçeyi geçirdikten SONRA asıl bildirim gönderilemezse
    /// (izin reddi, sistem kısıtı, planlama hatası vb.) çağrılır. allow()
    /// tarafından atılan zaman damgasını siler, böylece o türün bekleme
    /// hakkı boşa harcanmamış olur ve bir sonraki GERÇEK fırsat
    /// engellenmez. Damga hiç atılmamışsa (ör. yanlışlıkla çağrılırsa)
    /// no-op'tur — var olmayan bir anahtarı silmek zararsızdır.
    mutating func release(_ kind: NotifKind) {
        release(kind, key: nil)
    }

    /// release(_:)'in bağlam-anahtarlı eşi — allow(_:key:now:) ile atılan
    /// damgayı geri alır.
    mutating func release(_ kind: NotifKind, key: String?) {
        var sent = lastSent
        sent.removeValue(forKey: Self.storageKey(kind, key: key))
        lastSent = sent
    }

    private static func storageKey(_ kind: NotifKind, key: String?) -> String {
        guard let key, !key.isEmpty else { return kind.rawValue }
        return "\(kind.rawValue).\(key)"
    }
}
