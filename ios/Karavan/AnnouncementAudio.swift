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
final class AnnouncementAudio: NSObject, ObservableObject, AVAudioPlayerDelegate {
    static let shared = AnnouncementAudio()

    @Published private(set) var clipCount = 0

    private var manifest: [String: [URL]] = [:]
    private var player: AVAudioPlayer?
    private var lastPicked: [String: URL] = [:]   // arka arkaya aynı kayıt çalmasın
    private var finishContinuation: CheckedContinuation<Void, Never>?
    private var decodeFailed = false              // bozuk kayıt → TTS'e düş

    private override init() {
        super.init()
        // Telefon/Siri kesintisinde delegate çağrılmayabilir; sıra kilitlenmesin.
        NotificationCenter.default.addObserver(self, selector: #selector(interrupted(_:)),
                                               name: AVAudioSession.interruptionNotification, object: nil)
    }

    @objc private nonisolated func interrupted(_ notification: Notification) {
        guard let raw = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: raw) else { return }
        Task { @MainActor in
            switch type {
            case .began:
                // Kesinti boyunca DURAKLAT: stop() + continuation çözümü klibi
                // bitmiş sayar ve sıra kesinti sürerken boşa akardı; üstelik
                // .ended'de aynı işi yapmak, o ana kadar başlamış olan SONRAKİ
                // klibi de durduruyordu.
                self.player?.pause()
            case .ended:
                let options = (notification.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt)
                    .map { AVAudioSession.InterruptionOptions(rawValue: $0) } ?? []
                if options.contains(.shouldResume) {
                    self.player?.play()
                } else {
                    // Devam edilmeyecekse klibi kapat ki sıra kilitlenmesin.
                    self.player?.stop()
                    self.finishContinuation?.resume()
                    self.finishContinuation = nil
                }
            @unknown default:
                break
            }
        }
    }

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

    /// Anahtar için rastgele bir kayıt çalar ve bitene kadar bekler.
    /// Başarılıysa true (TTS gerekmez). Bekleme sayesinde klipler üst üste binmez.
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
        audio.delegate = self
        audio.prepareToPlay()
        guard audio.play() else {
            player = nil
            return false
        }

        // Çalma bitene kadar bekle (completion-based: müzik sesi ancak şimdi yükselir).
        decodeFailed = false
        await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
            finishContinuation = c
        }
        player = nil
        // Bozuk kayıt "başarılı" sayılırsa TTS yedeği atlanır ve kullanıcı
        // hiçbir şey duymaz — decode hatası başarısızlık sayılır.
        return !decodeFailed
    }

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in
            if !flag { self.decodeFailed = true }
            self.finishContinuation?.resume()
            self.finishContinuation = nil
        }
    }

    nonisolated func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        Task { @MainActor in
            self.decodeFailed = true
            self.finishContinuation?.resume()
            self.finishContinuation = nil
        }
    }
}
