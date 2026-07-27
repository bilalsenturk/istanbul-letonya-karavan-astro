import AVFoundation
import Foundation
import UIKit

/// Letonca derslerinin haptic ve ses efektleri. Görünümler `AVAudioPlayer`'a
/// hiç dokunmaz, hep bu nesneyi çağırır.
///
/// `Learning/` altındaki diğer dosyalar saf motordur (yalnızca `Foundation`) ve
/// `ios/Tests/run-latvian-check.sh` tarafından `swiftc` ile derlenir. Bu dosya
/// —`LatvianAudioStore` gibi— arayüz sınırıdır: `AVFoundation`/`UIKit` kullanır,
/// `@MainActor`'dır ve o kaynak listesine EKLENMEZ.
///
/// ## Neden ses başına birden çok çalar var
///
/// Tek bir `AVAudioPlayer`'ı `currentTime = 0; play()` ile yeniden tetiklemek
/// çalmakta olanı **keser**. XP sayacı puan başına bir tık çalıyor; tek çalarla
/// on puanlık bir sayım on ayrı tık değil, sürekli kesilen tek bir tık olur.
/// Bu yüzden üst üste binebilen sesler (tık, dokunuş, kombo, doğru) birden çok
/// çalarla tutuluyor ve her çalışta boştaki ilk çalar seçiliyor.
///
/// ## Neden `prewarm()` var
///
/// Çalarlar ilk kullanımda kurulursa dersin **ilk doğru cevabı** gecikmeli ses
/// verir — tam da en çok fark edilen an. `prewarm()` ders ekranı açılırken
/// çağrılır, sekiz sesi `Task.yield()` aralarıyla yükler (tek karede ana
/// döngüyü tıkamaz) ve haptic üreticilerini hazırlar.
///
/// ## Ses oturumu
///
/// Oturum uygulamada paylaşımlı: yol müziği (`MusicPlayer`), sesli günlük ve
/// `LatvianAudioStore` aynı `AVAudioSession`'ı kullanıyor. Burada `LatvianAudioStore`
/// ile **birebir aynı** kurulum yapılıyor, böylece hangisi en son çalışırsa
/// çalışsın oturum aynı halde kalıyor. `setActive(false)` hiç çağrılmıyor:
/// çalan yol müziğini susturur.
@MainActor
final class LatvianFeedback: ObservableObject {

    // MARK: - Ayarlar

    static let soundsEnabledKey = "letonca.soundsEnabled"
    static let hapticsEnabledKey = "letonca.hapticsEnabled"

    /// Ses efektleri açık mı. Kapalıyken haptic'ler çalışmaya devam eder.
    ///
    /// `@AppStorage` bilerek kullanılmadı: `DynamicProperty` olduğu için
    /// `View` dışında `objectWillChange` yayınlamaz, dolayısıyla bu nesneyi
    /// dinleyen ekranlar ayar değişince yenilenmez.
    @Published var soundsEnabled: Bool {
        didSet {
            guard soundsEnabled != oldValue else { return }
            defaults.set(soundsEnabled, forKey: Self.soundsEnabledKey)
            // Ders ortasında açıldıysa ilk ses gecikmeli gelmesin.
            if soundsEnabled { prewarm() } else { releaseSounds() }
        }
    }

    /// Haptic geri bildirim açık mı. Sessiz moddaki kullanıcı için ayrı tutuluyor.
    @Published var hapticsEnabled: Bool {
        didSet {
            guard hapticsEnabled != oldValue else { return }
            defaults.set(hapticsEnabled, forKey: Self.hapticsEnabledKey)
            if hapticsEnabled { prepareGenerators() }
        }
    }

    // MARK: - İç durum

    private let defaults: UserDefaults

    private var voices: [Sound: SoundVoices] = [:]
    private var sessionReady = false
    private var prewarmTask: Task<Void, Never>?

    private let notification = UINotificationFeedbackGenerator()
    private let softImpact = UIImpactFeedbackGenerator(style: .soft)
    private let rigidImpact = UIImpactFeedbackGenerator(style: .rigid)
    private let heavyImpact = UIImpactFeedbackGenerator(style: .heavy)

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        // Anahtar yoksa varsayılan açık; `bool(forKey:)` yokluğu `false` sayardı.
        soundsEnabled = defaults.object(forKey: Self.soundsEnabledKey) as? Bool ?? true
        hapticsEnabled = defaults.object(forKey: Self.hapticsEnabledKey) as? Bool ?? true
    }

    // MARK: - Olaylar

    /// Doğru cevap.
    func correct() {
        fireNotification(.success)
        play(.correct)
    }

    /// Yanlış cevap.
    func wrong() {
        fireNotification(.error)
        play(.wrong)
    }

    /// Kombo kilometre taşı — doğru cevabın sesinin üstüne biner.
    func combo() {
        fireImpact(rigidImpact, intensity: 0.85)
        play(.combo)
    }

    /// Can kaybı: tek ve ağır bir tokat.
    func heartLost() {
        fireImpact(heavyImpact, intensity: 1.0)
        play(.heart)
    }

    /// Ders bitti.
    func lessonComplete() {
        fireNotification(.success)
        play(.complete)
    }

    /// Günlük seri uzadı.
    func streakUp() {
        fireImpact(softImpact, intensity: 0.7)
        play(.streak)
    }

    /// XP sayacının her puanı. Bilerek haptic yok: puan başına titreşim
    /// on puanlık bir sayımda kesintisiz bir uğultuya dönüşür.
    func xpTick() {
        play(.xp)
    }

    /// Şık seçimi, buton dokunuşu.
    func tap() {
        fireImpact(softImpact, intensity: 0.45)
        play(.tap)
    }

    // MARK: - Hazırlık

    /// Sesleri ve haptic üreticilerini önceden kurar. Ders ekranı açılırken
    /// çağrılmalı. Birden çok kez çağrılması zararsızdır.
    func prewarm() {
        prepareGenerators()
        guard soundsEnabled, prewarmTask == nil else { return }
        prepareSessionIfNeeded()
        prewarmTask = Task { @MainActor [weak self] in
            for sound in Sound.allCases {
                guard let self, !Task.isCancelled else { return }
                self.loadIfNeeded(sound)
                // Sekiz sesi tek karede kurmak görünür bir takılma yapar.
                await Task.yield()
            }
        }
    }

    /// Ses çalarlarını (ve tuttukları ses kuyruklarını) bırakır. Ders ekranı
    /// kapanırken çağrılabilir; sonraki `prewarm()` yeniden kurar.
    func releaseSounds() {
        prewarmTask?.cancel()
        prewarmTask = nil
        for voice in voices.values { voice.stopAll() }
        voices.removeAll()
    }

    // MARK: - Haptic

    private func prepareGenerators() {
        guard hapticsEnabled else { return }
        notification.prepare()
        softImpact.prepare()
        rigidImpact.prepare()
        heavyImpact.prepare()
    }

    private func fireNotification(_ type: UINotificationFeedbackGenerator.FeedbackType) {
        guard hapticsEnabled else { return }
        notification.notificationOccurred(type)
        // Ders boyunca olaylar birkaç saniyede bir geliyor; motoru sıcak
        // tutmak sonraki titreşimin gecikmesini önlüyor.
        notification.prepare()
    }

    private func fireImpact(_ generator: UIImpactFeedbackGenerator, intensity: CGFloat) {
        guard hapticsEnabled else { return }
        generator.impactOccurred(intensity: intensity)
        generator.prepare()
    }

    // MARK: - Ses

    private func play(_ sound: Sound) {
        guard soundsEnabled else { return }
        prepareSessionIfNeeded()
        loadIfNeeded(sound)
        guard let player = voices[sound]?.next() else { return }
        player.currentTime = 0
        player.play()
    }

    private func loadIfNeeded(_ sound: Sound) {
        guard voices[sound] == nil else { return }
        guard let url = Bundle.main.url(forResource: sound.rawValue, withExtension: "wav") else {
            #if DEBUG
            print("[LatvianFeedback] pakette yok: \(sound.rawValue).wav")
            #endif
            // Boş kayıt: her çalışta yeniden dosya aramaya çalışmasın.
            voices[sound] = SoundVoices(players: [])
            return
        }
        var players: [AVAudioPlayer] = []
        for _ in 0..<sound.voiceCount {
            guard let player = try? AVAudioPlayer(contentsOf: url) else { break }
            player.volume = sound.volume
            player.prepareToPlay()
            players.append(player)
        }
        voices[sound] = SoundVoices(players: players)
    }

    /// `LatvianAudioStore.prepareSessionIfNeeded()` ile birebir aynı.
    ///
    /// Kategori her seferinde kontrol ediliyor: sesli günlük (`SpeechRecorder`)
    /// kategoriyi `.record`'a çevirmiş olabilir, o halde efektler sessiz kalırdı.
    /// Not: `.playback` sessiz anahtarını dinlemez — ders sesleri zil kapalıyken
    /// de çalsın diye bu bilinçli; kullanıcı `soundsEnabled` ile kapatabiliyor.
    private func prepareSessionIfNeeded() {
        let session = AVAudioSession.sharedInstance()
        guard !sessionReady || session.category != .playback else { return }
        try? session.setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
        try? session.setActive(true)
        sessionReady = true
    }
}

// MARK: - Ses kataloğu

private enum Sound: String, CaseIterable {
    case correct = "lv-correct"
    case wrong = "lv-wrong"
    case complete = "lv-complete"
    case xp = "lv-xp"
    case heart = "lv-heart"
    case streak = "lv-streak"
    case tap = "lv-tap"
    case combo = "lv-combo"

    /// Kaç çalar tutulacağı. Yalnızca üst üste binebilen sesler için >1:
    /// XP tıkı puan başına, dokunuş her şıkta, kombo doğru cevabın üstüne gelir.
    var voiceCount: Int {
        switch self {
        case .xp: return 3
        case .tap, .combo, .correct: return 2
        case .wrong, .complete, .heart, .streak: return 1
        }
    }

    /// Arayüz cırtları yol müziğinin üstünde bağırmasın diye ölçülü seviyeler.
    var volume: Float {
        switch self {
        case .complete: return 1.0
        case .correct, .heart: return 0.85
        case .wrong, .streak: return 0.80
        case .combo: return 0.70
        case .xp: return 0.50
        case .tap: return 0.35
        }
    }
}

/// Bir sesin çalar havuzu.
private final class SoundVoices {
    private let players: [AVAudioPlayer]
    private var index = 0

    init(players: [AVAudioPlayer]) {
        self.players = players
    }

    /// Boştaki ilk çalar; hepsi çalıyorsa sırayla en eskisi kesilir.
    func next() -> AVAudioPlayer? {
        guard !players.isEmpty else { return nil }
        if let free = players.first(where: { !$0.isPlaying }) { return free }
        let player = players[index]
        index = (index + 1) % players.count
        return player
    }

    func stopAll() {
        for player in players where player.isPlaying { player.stop() }
    }
}
