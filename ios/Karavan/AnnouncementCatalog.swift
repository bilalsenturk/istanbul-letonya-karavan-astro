import Foundation

// Tüm SABİT anonsların tek kaynağı. Her anonsun bir ANAHTARI var; aynı anahtar
// için uzak depoda kayıt varsa (ElevenLabs vb.) o çalınır — birden fazla kayıt
// varsa rastgele seçilir. Kayıt yoksa buradaki metin cihaz TTS'i ile okunur.
//
// Ses dosyası eklemek için: kaydı depoya at, audio/manifest.json'a anahtarı yaz:
//   { "captain-01": ["captain-01-ali.mp3", "captain-01-leyla.mp3"] }
enum AnnouncementCatalog {
    struct Clip: Identifiable {
        let key: String
        let text: String
        var lang: String = "tr-TR"
        var id: String { key }
    }

    // MARK: - Kaptan esprileri (araç bağlanınca / yola çıkarken)

    static let captain: [Clip] = [
        Clip(key: "captain-01", text: "Değerli yolcularımız, kaptanınız konuşuyor. Lütfen kemerlerinizi bağlayın. Çiş molası verilmeyecektir."),
        Clip(key: "captain-02", text: "Arabada pırt yapmak kesinlikle yasaktır. Leyla, sana bakıyorum."),
        Clip(key: "captain-03", text: "Kaptan konuşuyor: müzik seçme yetkisi kaptandadır, itirazlar dinlenmeyecektir."),
        Clip(key: "captain-04", text: "Sevgili yolcular, hafif türbülans — yani Balkan yolları — bekleniyor. Kemerler bağlı kalsın."),
        Clip(key: "captain-05", text: "Leyla için özel anons: atıştırmalıkların yarısı kaptana aittir. İyi yolculuklar."),
        Clip(key: "captain-06", text: "Uçuşumuz, pardon, yolculuğumuz başlıyor. Koltuğunuzu dik konuma getirin ve gülümseyin."),
        Clip(key: "captain-07", text: "Kaptan konuşuyor: bu araçta şarkıya eşlik etmek zorunludur. Utanmak yasaktır."),
        Clip(key: "captain-08", text: "Yolcularımızın dikkatine: navigasyon bende, tartışma yok. Leyla, harita katlamayı bırak."),
    ]

    // MARK: - Varış karşılamaları (Türkçe + yerel dil)

    static let arrivals: [String: [Clip]] = [
        "İstanbul": [Clip(key: "arrive-istanbul", text: "İstanbul'a hoş geldiniz.")],
        "Sofya": [
            Clip(key: "arrive-sofya-tr", text: "Sofya'ya hoş geldiniz."),
            Clip(key: "arrive-sofya-bg", text: "Добре дошли в София.", lang: "bg-BG"),
        ],
        "Bükreş": [
            Clip(key: "arrive-bukres-tr", text: "Bükreş'e hoş geldiniz."),
            Clip(key: "arrive-bukres-ro", text: "Bun venit la București.", lang: "ro-RO"),
        ],
        "Deva": [
            Clip(key: "arrive-deva-tr", text: "Deva'ya hoş geldiniz."),
            Clip(key: "arrive-deva-ro", text: "Bun venit la Deva.", lang: "ro-RO"),
        ],
        "Budapeşte": [
            Clip(key: "arrive-budapeste-tr", text: "Budapeşte'ye hoş geldiniz."),
            Clip(key: "arrive-budapeste-hu", text: "Üdvözöljük Budapesten.", lang: "hu-HU"),
        ],
        "Katowice": [
            Clip(key: "arrive-katowice-tr", text: "Katowice'ye hoş geldiniz."),
            Clip(key: "arrive-katowice-pl", text: "Witamy w Katowicach.", lang: "pl-PL"),
        ],
        "Suwałki": [
            Clip(key: "arrive-suwalki-tr", text: "Suwałki'ye hoş geldiniz."),
            Clip(key: "arrive-suwalki-pl", text: "Witamy w Suwałkach.", lang: "pl-PL"),
        ],
        "Riga": [
            Clip(key: "arrive-riga-tr", text: "Riga'ya hoş geldiniz. Yolculuk tamamlandı, tebrikler!"),
            Clip(key: "arrive-riga-lv", text: "Laipni lūdzam Rīgā.", lang: "lv-LV"),
        ],
    ]

    /// Durak adı tam eşleşmezse ("Bükreş Güney" gibi) içeren anahtarı bulur.
    static func arrival(for stopName: String) -> [Clip] {
        if let exact = arrivals[stopName] { return exact }
        if let fuzzy = arrivals.first(where: { stopName.contains($0.key) || $0.key.contains(stopName) }) {
            return fuzzy.value
        }
        return [Clip(key: "arrive-generic", text: "\(stopName), hoş geldiniz.")]
    }

    // MARK: - Durum anonsları

    static let ready = Clip(key: "ready", text: "Gitmeye hazır mısın? Otuz dakikaya yola çıkıyoruz. Kemerler, gaz, evraklar — hadi!")
    static let storm = Clip(key: "storm", text: "Basınç düşüyor, fırtına yaklaşıyor olabilir. Kamp ve mola planını gözden geçir.")
    static let deviation = Clip(key: "deviation", text: "Rotadan saptık. Bilerek miydi? İstersen konumunu paylaşabilirim.")
    static let rainStart = Clip(key: "rain-start", text: "Yağmur başladı. Hızını düşür, takip mesafeni artır.")
    static let restReminder = Clip(key: "rest-reminder", text: "İki saattir yoldayız. Bir mola iyi gelir, kaptan yorulmasın.")
    static let borderAhead = Clip(key: "border-ahead", text: "Sınıra yaklaşıyoruz. Pasaportlar, ruhsat ve sigorta hazır olsun.")

    /// Kaydedilmesi anlamlı tüm sabit anonslar (dinamik sayı içerenler hariç).
    static var allRecordable: [Clip] {
        captain
            + arrivals.keys.sorted().flatMap { arrivals[$0] ?? [] }
            + [ready, storm, deviation, rainStart, restReminder, borderAhead]
    }
}
