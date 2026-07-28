import AVFoundation
import Foundation
import MediaPlayer
import UIKit

// Yolculuk müziği. Parçalar uzak depodan (site / Cloudflare R2) indirilip CİHAZDA
// saklanır — sinyalsiz sınır bölgelerinde de çalar. Anons gelince ses yaklaşık %12'ye
// kısılır, anons bitince yumuşakça geri yükselir.
struct Track: Codable, Identifiable, Hashable {
    let id: String
    let title: String
    let artist: String?
    let file: String          // "music/kuzeye-giderken.mp3"
    let duration: Double?
}

private struct MusicManifest: Codable { let tracks: [Track] }

@MainActor
final class MusicPlayer: NSObject, ObservableObject {
    static let shared = MusicPlayer()

    @Published private(set) var tracks: [Track] = []
    @Published private(set) var current: Track?
    @Published private(set) var isPlaying = false
    @Published private(set) var downloading: Set<String> = []
    @Published var shuffle = false
    @Published var repeatAll = true

    private var player: AVAudioPlayer?
    private var normalVolume: Float = 1.0
    private var duckDepth: Float = 0.12      // anonsta konuşma netliği için düşük müzik seviyesi

    private var musicDir: URL {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Music", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// Son indirilen parça listesi — ağ yoksa offline katalog buradan kurulur.
    private var manifestCacheURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("music-manifest.json")
    }

    private override init() {
        super.init()
        setupRemoteCommands()
    }

    // MARK: - Katalog

    func load() async {
        guard let base = Config.imageBaseURL,
              let url = URL(string: "/audio/music/manifest.json", relativeTo: base) else { loadCachedManifest(); return }
        var request = URLRequest(url: url)
        request.timeoutInterval = 12
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse, http.statusCode == 200,
              let decoded = try? JSONDecoder().decode(MusicManifest.self, from: data)
        else { loadCachedManifest(); return }   // ağ yok → son manifesti diskten kur
        tracks = decoded.tracks
        try? data.write(to: manifestCacheURL, options: .atomic)
    }

    /// Offline açılış: son indirilen manifestten katalog; indirilen parçalar çalınabilir kalır.
    private func loadCachedManifest() {
        guard let data = try? Data(contentsOf: manifestCacheURL),
              let decoded = try? JSONDecoder().decode(MusicManifest.self, from: data)
        else { return }
        tracks = decoded.tracks
    }

    func localURL(for track: Track) -> URL {
        musicDir.appendingPathComponent(track.file.replacingOccurrences(of: "/", with: "_"))
    }

    func isDownloaded(_ track: Track) -> Bool {
        FileManager.default.fileExists(atPath: localURL(for: track).path)
    }

    /// Parçayı indirip cihazda sakla (offline çalabilmek için).
    @discardableResult
    func download(_ track: Track) async -> Bool {
        let dest = localURL(for: track)
        if FileManager.default.fileExists(atPath: dest.path) { return true }
        guard let base = Config.imageBaseURL,
              let url = URL(string: "/audio/\(track.file)", relativeTo: base) else { return false }

        downloading.insert(track.id)
        defer { downloading.remove(track.id) }

        var request = URLRequest(url: url)
        request.timeoutInterval = 120
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse, http.statusCode == 200, data.count > 10_000
        else { return false }
        do {
            try data.write(to: dest, options: .atomic)
            return true
        } catch {
            return false   // diske yazılamadı → parça önbellekte değil
        }
    }

    // MARK: - Çalma

    private var playGeneration = 0   // art arda play() yarışında yalnız son istek kazanır
    private var currentPlayGen = 0   // çalmakta olan parçayı başlatan isteğin nesli

    func play(_ track: Track) async {
        playGeneration += 1
        await startPlayback(track, gen: playGeneration)
    }

    /// Parça bitince sıradakine geç: nesli YÜKSELTME — kullanıcının o sırada
    /// başlattığı seçim ezilmesin; yeni bir play() gelirse gen kontrolü bunu eler.
    private func autoAdvance(to track: Track) async {
        await startPlayback(track, gen: playGeneration)
    }

    private func startPlayback(_ track: Track, gen: Int) async {
        guard gen == playGeneration else { return }   // daha yeni istek geldiyse vazgeç
        guard await download(track), gen == playGeneration else { return }
        do {
            try beginPlayback(track)
        } catch {
            // Bozuk inmiş dosya AVAudioPlayer'ı fırlatır: sil, bir kez yeniden indir.
            try? FileManager.default.removeItem(at: localURL(for: track))
            guard await download(track), gen == playGeneration else { restorePlaybackState(); return }
            do {
                try beginPlayback(track)
            } catch {
                restorePlaybackState()
            }
        }
    }

    /// Başlatma başarısız: eski çalar hâlâ ses veriyorsa arayüz bunu yansıtsın
    /// (çalan müzik + duraklatılmış görünen düğme olmasın).
    private func restorePlaybackState() {
        isPlaying = player?.isPlaying ?? false
        updateNowPlaying()
    }

    private func beginPlayback(_ track: Track) throws {
        try AVAudioSession.sharedInstance().setCategory(.playback, options: [.duckOthers])
        try AVAudioSession.sharedInstance().setActive(true)
        let p = try AVAudioPlayer(contentsOf: localURL(for: track))
        p.delegate = self
        p.volume = duckedVolume   // anons sürüyorsa kısık başla
        p.prepareToPlay()
        p.play()
        player = p
        current = track
        currentPlayGen = playGeneration
        isPlaying = true
        updateNowPlaying()
    }

    /// Anons (duck) sürüyorsa kısık, yoksa normal ses — play/toggle/uzaktan
    /// kumanda hepsi buradan geçer ki anons ortasında tam sesle dönülmesin.
    private var duckedVolume: Float {
        duckCount > 0 ? normalVolume * duckDepth : normalVolume
    }

    func toggle() {
        guard let p = player else {
            if let first = tracks.first { Task { await play(first) } }
            return
        }
        if p.isPlaying {
            p.pause(); isPlaying = false
        } else {
            p.volume = duckedVolume
            p.play(); isPlaying = true
        }
        updateNowPlaying()
    }

    func next(auto: Bool = false) {
        guard !tracks.isEmpty else { return }
        let idx = current.flatMap { c in tracks.firstIndex(where: { $0.id == c.id }) } ?? -1
        let nextIdx: Int
        if shuffle {
            // Karışık modda aynı parça üst üste çalmasın.
            var r = Int.random(in: 0 ..< tracks.count)
            if tracks.count > 1, r == idx { r = (r + 1) % tracks.count }
            nextIdx = r
        } else {
            nextIdx = (idx + 1) % tracks.count
        }
        Task { auto ? await self.autoAdvance(to: tracks[nextIdx]) : await self.play(tracks[nextIdx]) }
    }

    func previous() {
        guard !tracks.isEmpty else { return }
        // 3 saniyeden sonra başa sar, öncesinde önceki parça
        if let p = player, p.currentTime > 3 { p.currentTime = 0; updateNowPlaying(); return }
        let idx = current.flatMap { c in tracks.firstIndex(where: { $0.id == c.id }) } ?? 0
        let prevIdx = (idx - 1 + tracks.count) % tracks.count
        Task { await play(tracks[prevIdx]) }
    }

    func stop() {
        player?.stop()
        player = nil
        isPlaying = false
        current = nil
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
    }

    var progress: Double {
        guard let p = player, p.duration > 0 else { return 0 }
        return p.currentTime / p.duration
    }

    var currentTimeText: String {
        guard let p = player else { return "0:00" }
        return Self.timeText(p.currentTime)
    }

    var durationText: String {
        guard let p = player else { return "0:00" }
        return Self.timeText(p.duration)
    }

    static func timeText(_ t: TimeInterval) -> String {
        let s = Int(t.rounded())
        return String(format: "%d:%02d", s / 60, s % 60)
    }

    // MARK: - Anons sırasında kısma
    // Sayaçlı: playOne → speakAndWait iç içe kısabilir; ses ancak en dıştaki
    // anons bitince yükselir. Anons sürerken parça değişirse yeni parça da
    // kısık başlar (play() duckCount'a bakar).

    private var duckCount = 0

    func duck() {
        duckCount += 1
        guard duckCount == 1, let p = player, p.isPlaying else { return }
        normalVolume = max(0.05, p.volume)
        p.setVolume(normalVolume * duckDepth, fadeDuration: 0.45)
    }

    func unduck() {
        guard duckCount > 0 else { return }
        duckCount -= 1
        guard duckCount == 0, let p = player else { return }
        p.setVolume(normalVolume, fadeDuration: 0.9)
    }

    func restoreSessionAfterAnnouncement() {
        guard player != nil else { return }
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, options: [.duckOthers])
        try? AVAudioSession.sharedInstance().setActive(true)
    }

    // MARK: - Kilit ekranı / araç kumandaları

    private func setupRemoteCommands() {
        let c = MPRemoteCommandCenter.shared()
        c.playCommand.addTarget { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                if self.player == nil {
                    self.toggle()   // çalan yok: toggle gibi ilk parçayı başlat (hayalet isPlaying olmasın)
                } else {
                    self.player?.volume = self.duckedVolume   // anons sürüyorsa kısık dön
                    self.player?.play(); self.isPlaying = true; self.updateNowPlaying()
                }
            }
            return .success
        }
        c.pauseCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.player?.pause(); self?.isPlaying = false; self?.updateNowPlaying() }
            return .success
        }
        c.togglePlayPauseCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.toggle() }
            return .success
        }
        c.nextTrackCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.next() }
            return .success
        }
        c.previousTrackCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.previous() }
            return .success
        }
    }

    private func updateNowPlaying() {
        guard let track = current, let p = player else { return }
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: track.title,
            MPMediaItemPropertyArtist: track.artist ?? "Kuzey",
            MPMediaItemPropertyAlbumTitle: "Kuzey · İstanbul → Riga",
            MPMediaItemPropertyPlaybackDuration: p.duration,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: p.currentTime,
            MPNowPlayingInfoPropertyPlaybackRate: p.isPlaying ? 1.0 : 0.0,
        ]
        if let art = UIImage(named: "AppIcon") {
            info[MPMediaItemPropertyArtwork] = MPMediaItemArtwork(boundsSize: art.size) { _ in art }
        }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }
}

extension MusicPlayer: AVAudioPlayerDelegate {
    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in
            // Yerine yenisi başlamış çaların bayat bitiş olayı yeni parçayı kesmesin.
            guard player === self.player else { return }
            // Bozuk dosya: çaları ve parçayı tamamen temizle — toggle() ölü
            // çaları "çalıyor" sanıp sessizlik çalmasın; sonraki dokunuş
            // geçerli bir parça başlatır.
            guard flag else {
                self.player?.stop()
                self.player = nil
                self.current = nil
                self.isPlaying = false
                MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
                return
            }
            guard self.repeatAll, !self.tracks.isEmpty else {
                self.isPlaying = false
                MPNowPlayingInfoCenter.default().nowPlayingInfo = nil   // kilit ekranında bayat bilgi kalmasın
                return
            }
            // Kullanıcı bu parça çalarken yeni bir seçim başlattıysa otomatik
            // ilerletme onun neslini yükseltip seçimini ezmesin.
            guard self.playGeneration == self.currentPlayGen else { return }
            self.next(auto: true)
        }
    }
}
