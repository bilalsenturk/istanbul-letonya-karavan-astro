import AVFoundation
import Foundation
import MediaPlayer
import UIKit

// Yolculuk müziği. Parçalar uzak depodan (site / Cloudflare R2) indirilip CİHAZDA
// saklanır — sinyalsiz sınır bölgelerinde de çalar. Anons gelince ses %25'e
// kısılır, anons bitince geri yükselir (kullanıcının anons kuralı).
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
    private var duckDepth: Float = 0.25      // anonsta %25 seviye

    private var musicDir: URL {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Music", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private override init() {
        super.init()
        setupRemoteCommands()
    }

    // MARK: - Katalog

    func load() async {
        guard let base = Config.imageBaseURL,
              let url = URL(string: "/audio/music/manifest.json", relativeTo: base) else { return }
        var request = URLRequest(url: url)
        request.timeoutInterval = 12
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse, http.statusCode == 200,
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
        try? data.write(to: dest, options: .atomic)
        return true
    }

    // MARK: - Çalma

    func play(_ track: Track) async {
        guard await download(track) else { return }
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, options: [.duckOthers])
            try AVAudioSession.sharedInstance().setActive(true)
            let p = try AVAudioPlayer(contentsOf: localURL(for: track))
            p.delegate = self
            p.volume = normalVolume
            p.prepareToPlay()
            p.play()
            player = p
            current = track
            isPlaying = true
            updateNowPlaying()
        } catch {
            isPlaying = false
        }
    }

    func toggle() {
        guard let p = player else {
            if let first = tracks.first { Task { await play(first) } }
            return
        }
        if p.isPlaying { p.pause(); isPlaying = false } else { p.play(); isPlaying = true }
        updateNowPlaying()
    }

    func next() {
        guard !tracks.isEmpty else { return }
        let idx = current.flatMap { c in tracks.firstIndex(where: { $0.id == c.id }) } ?? -1
        let nextIdx = shuffle
            ? Int.random(in: 0 ..< tracks.count)
            : (idx + 1) % tracks.count
        Task { await play(tracks[nextIdx]) }
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

    // MARK: - Anons sırasında kısma (kullanıcı kuralı: %25'e in, sonra geri yükselt)

    func duck() {
        guard let p = player, p.isPlaying else { return }
        p.setVolume(normalVolume * duckDepth, fadeDuration: 0.25)
    }

    func unduck() {
        guard let p = player else { return }
        p.setVolume(normalVolume, fadeDuration: 0.6)
    }

    // MARK: - Kilit ekranı / araç kumandaları

    private func setupRemoteCommands() {
        let c = MPRemoteCommandCenter.shared()
        c.playCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.player?.play(); self?.isPlaying = true; self?.updateNowPlaying() }
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
            guard self.repeatAll, !self.tracks.isEmpty else {
                self.isPlaying = false
                return
            }
            self.next()
        }
    }
}
