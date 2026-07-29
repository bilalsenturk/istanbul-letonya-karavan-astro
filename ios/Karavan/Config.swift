import Foundation

// Tek yerden yapılandırma. Site deploy adresin netleşince yalnızca bunu değiştir.
enum Config {
    #if targetEnvironment(simulator)
    /// Simülatörde Mac'in yerel Astro dev sunucusuna bağlan (astro dev · :4321).
    /// Böylece deploy öncesi güncel veri + kamp görselleri simülatörde görünür.
    static let siteURL = URL(string: "http://localhost:4321")
    #else
    /// Gerçek cihaz / yayın: deploy edilen sitenin kökü (sonda / yok)
    static let siteURL = URL(string: "https://istanbul-letonya-karavan-astro.vercel.app")
    #endif

    /// Uzak gezi verisi (site her deploy olduğunda app içeriği tazelenir)
    static var tripDataURL: URL? { siteURL?.appendingPathComponent("trip-data.json") }

    /// Yol bülteni: dizel fiyatı + sınır beklemesi + döviz kuru.
    static var roadFeedURL: URL? { siteURL?.appendingPathComponent("api/roadfeed") }

    /// Güncel sürüm manifest'i (TestFlight build no + zorunlu minimum + davet linki).
    static var versionManifestURL: URL? { siteURL?.appendingPathComponent("kuzey-version.json") }

    /// Apple oturumu ve kullanıcıya özel rota API'si.
    static var accountAPIBaseURL: URL? { siteURL?.appendingPathComponent("api/v2") }

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

}
