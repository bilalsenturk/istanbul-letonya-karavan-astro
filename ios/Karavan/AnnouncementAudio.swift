import AVFoundation
import Foundation

// Kayıtlı anons sesleri (ElevenLabs vb.) — uzak depodan (Cloudflare R2, Vercel…)
// çalınır. Bir anahtar için BİRDEN FAZLA kayıt varsa rastgele biri seçilir;
// hiç kayıt yoksa cihazdaki TTS'e düşülür. Kayıtlar indirildikten sonra
// URLCache'te kalır (offline'da da çalar).
//
// Beklenen manifest (ör. https://.../audio/manifest.json):
// { "captain-01": ["captain-01-a.mp3", "captain-01-b.mp3"], "welcome-sofya": ["..."] }
// Yollar manifest URL'ine görelidir; tam URL de yazılabilir.
@MainActor
final class AnnouncementAudio: NSObject, ObservableObject {
    static let shared = AnnouncementAudio()

    @Published private(set) var clipCount = 0

    private var manifest: [String: [URL]] = [:]
    private var player: AVAudioPlayer?
    private var lastPicked: [String: URL] = [:]   // arka arkaya aynı kayıt çalmasın

    private override init() { super.init() }

    /// Uygulama açılışında bir kez çağır. Manifest yoksa sessizce TTS'e düşülür.
    func loadManifest() async {
        guard let url = Config.audioManifestURL else { return }
        var request = URLRequest(url: url)
        request.timeoutInterval = 10
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse, http.statusCode == 200,
              let raw = try? JSONDecoder().decode([String: [String]].self, from: data)
        else { return }

        var parsed: [String: [URL]] = [:]
        for (key, files) in raw {
            let urls = files.compactMap { URL(string: $0, relativeTo: url)?.absoluteURL }
            if !urls.isEmpty { parsed[key] = urls }
        }
        manifest = parsed
        clipCount = parsed.values.reduce(0) { $0 + $1.count }
    }

    func hasClip(_ key: String) -> Bool { !(manifest[key]?.isEmpty ?? true) }

    /// Anahtar için rastgele bir kayıt çalar. Başarılıysa true (TTS gerekmez).
    func play(_ key: String) async -> Bool {
        guard var options = manifest[key], !options.isEmpty else { return false }
        // Birden fazla kayıt varsa, üst üste aynısını çalma
        if options.count > 1, let last = lastPicked[key] {
            options.removeAll { $0 == last }
        }
        guard let pick = options.randomElement() else { return false }
        lastPicked[key] = pick

        var request = URLRequest(url: pick)
        request.cachePolicy = .returnCacheDataElseLoad     // indirilince offline çalar
        request.timeoutInterval = 12
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse, http.statusCode == 200,
              let audio = try? AVAudioPlayer(data: data)
        else { return false }

        try? AVAudioSession.sharedInstance().setActive(true)
        player = audio
        audio.prepareToPlay()
        return audio.play()
    }
}
