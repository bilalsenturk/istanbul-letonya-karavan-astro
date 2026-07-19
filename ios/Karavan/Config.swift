import Foundation

// Tek yerden yapılandırma. Site deploy adresin netleşince yalnızca bunu değiştir.
enum Config {
    /// Deploy edilen sitenin kökü (sonda / yok)
    static let siteURL = URL(string: "https://istanbul-riga.vercel.app")

    /// Uzak gezi verisi (site her deploy olduğunda app içeriği tazelenir)
    static var tripDataURL: URL? { siteURL?.appendingPathComponent("trip-data.json") }

    /// Canlı konumun web'e gönderileceği endpoint (POST)
    static var livePostURL: URL? { siteURL?.appendingPathComponent("api/location") }

    /// Web'e konum gönderirken kullanılan paylaşılan gizli anahtar.
    /// Vercel'de LIVE_POST_SECRET env değişkeniyle aynı olmalı.
    static let livePostSecret = "kuzey-2026-riga"
}
