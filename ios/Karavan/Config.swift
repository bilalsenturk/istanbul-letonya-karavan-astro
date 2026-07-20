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

    /// Hesaplanmış takvimin (kalkış + gün tarihleri) web'e gönderileceği endpoint.
    static var planPostURL: URL? { siteURL?.appendingPathComponent("api/plan") }

    /// Kamp/galeri görsellerinin kök adresi (JSON'daki "/assets/..." yolları buna göre çözülür).
    /// Görselleri Cloudflare R2 gibi bir CDN'e taşırsan yalnızca burayı değiştir.
    static var imageBaseURL: URL? { mediaBaseURL ?? siteURL }

    /// Medya (görsel + ses) için opsiyonel harici depo. nil → site ile aynı yer.
    /// Örn: URL(string: "https://kuzey.<hesabın>.r2.dev")
    static let mediaBaseURL: URL? = nil

    /// Kayıtlı anons seslerinin manifest'i (yoksa cihaz TTS'i kullanılır).
    static var audioManifestURL: URL? {
        (mediaBaseURL ?? siteURL)?.appendingPathComponent("audio/manifest.json")
    }

    /// Web'e veri gönderirken kullanılan paylaşılan gizli anahtar.
    /// Vercel'de LIVE_POST_SECRET env değişkeniyle aynı olmalı.
    static let livePostSecret = "kuzey-2026-riga"
}
