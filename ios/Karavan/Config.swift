import Foundation

// Tek yerden yapılandırma. Site deploy adresin netleşince yalnızca bunu değiştir.
enum Config {
    #if targetEnvironment(simulator)
    /// Simülatörde Mac'in yerel Astro dev sunucusuna bağlan (astro dev · :4321).
    /// Böylece deploy öncesi güncel veri + kamp görselleri simülatörde görünür.
    static let siteURL = URL(string: "http://localhost:4321")
    #else
    /// Gerçek cihaz / yayın: deploy edilen sitenin kökü (sonda / yok)
    static let siteURL = URL(string: "https://istanbul-riga.vercel.app")
    #endif

    /// Uzak gezi verisi (site her deploy olduğunda app içeriği tazelenir)
    static var tripDataURL: URL? { siteURL?.appendingPathComponent("trip-data.json") }

    /// Canlı konumun web'e gönderileceği endpoint (POST)
    static var livePostURL: URL? { siteURL?.appendingPathComponent("api/location") }

    /// Harcama toplamının web'e gönderileceği endpoint (POST). Kalemler cihazda kalır.
    static var expensesPostURL: URL? { siteURL?.appendingPathComponent("api/expenses") }

    /// Kamp görsellerinin kök adresi (JSON'daki "/assets/..." yolları buna göre çözülür)
    static var imageBaseURL: URL? { siteURL }

    /// Web'e veri gönderirken kullanılan paylaşılan gizli anahtar.
    /// Vercel'de LIVE_POST_SECRET env değişkeniyle aynı olmalı.
    static let livePostSecret = "kuzey-2026-riga"
}
