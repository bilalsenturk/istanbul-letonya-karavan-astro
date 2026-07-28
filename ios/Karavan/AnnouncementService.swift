import Foundation
import AVFoundation

// Sesli anons/kaptan sistemi — cihazda TTS (AVSpeechSynthesizer).
// Araç bağlantısını (CarPlay/araç ses yolu) tespit eder; bağlanınca "hadi başlat"
// + kaptan esprisi; duraklarda YEREL DİLDE karşılama; her 100 km'de mesafe anonsu.
//
// NOT: Native CarPlay ekranı için Apple onaylı entitlement + ücretli üyelik gerekir.
// Bu sistem CarPlay'e bağlıyken araç hoparlöründen konuşur; entitlement gerekmez.
@MainActor
final class AnnouncementService: NSObject, ObservableObject, AVSpeechSynthesizerDelegate {
    static let shared = AnnouncementService()

    @Published var lastLine: String?
    @Published var enabled = true

    /// Araç bağlanınca app'in ne diyeceğini dışarıdan kurar (sıradaki durağa erişim için).
    var onCarConnected: (() -> Void)? {
        didSet {
            // Araç açılışta zaten bağlıysa, atamadan önce kaçan anonsu şimdi ateşle.
            if inCar, onCarConnected != nil { onCarConnected?() }
        }
    }

    private let synth = AVSpeechSynthesizer()
    private var inCar = false
    private var speechTask: Task<Void, Never>?        // anonsları tek sıraya bağlar
    private var ttsContinuation: CheckedContinuation<Void, Never>?

    // Sıradaki hedefe mesafe anonsu için durum
    private var lastBucket: Int?
    private var lastStopForBucket: String?

    // Çift anons koruması: aynı olay iki bağımsız yoldan tetiklenebilir
    // (kalkış: düğme/modal + araç bağlantısı; varış: geofence yeniden kurulumu).
    private var lastDeparture: (stop: String?, at: Date)?
    private var lastArrival: (stop: String, at: Date)?

    private override init() {
        super.init()
        synth.delegate = self
        try? AVAudioSession.sharedInstance().setCategory(.playback, options: [.mixWithOthers, .duckOthers])
        NotificationCenter.default.addObserver(self, selector: #selector(routeChanged),
                                               name: AVAudioSession.routeChangeNotification, object: nil)
        checkCarRoute()
    }

    // MARK: - Konuşma

    /// Kayıtlı ses varsa onu (birden fazlaysa rastgele) çalar, yoksa cihaz TTS'i.
    /// Anons boyunca müzik yaklaşık %12'ye kısılır; kayıt/TTS GERÇEKTEN bitince geri yükselir.
    func say(_ clip: AnnouncementCatalog.Clip) {
        guard enabled else { return }
        enqueue { [weak self] in
            guard let self, self.enabled else { return }
            // Çalma gerçekten başlarken göster — sıraya girerken yazılırsa
            // kapalıyken bırakılan ya da hâlâ bekleyen anons ekrana düşer.
            self.lastLine = clip.text
            await self.playOne(clip)
        }
    }

    func speak(_ text: String, language: String = "tr-TR") {
        guard enabled else { return }
        enqueue { [weak self] in
            guard let self, self.enabled else { return }
            self.lastLine = text
            await self.speakOne(text, language: language)
        }
    }

    /// Anonsları sıraya bağlar: klipler ve TTS üst üste binmez, çağrı sırasıyla çalar.
    private func enqueue(_ work: @escaping @MainActor () async -> Void) {
        let previous = speechTask
        speechTask = Task { @MainActor in
            await previous?.value
            await work()
        }
    }

    /// Tek anons: kayıt bitene kadar bekle; kayıt yoksa TTS'i konuşup bitişini bekle.
    private func playOne(_ clip: AnnouncementCatalog.Clip) async {
        await withAnnouncementAudio {
            if await AnnouncementAudio.shared.play(clip.key) { return }
            // Cihazda yerel TTS sesi yoksa (ör. Bulgarca ses indirilmemiş) Türkçe
            // ses yabancı metni okur ve anlaşılmaz olur — Türkçe satıra, o da
            // yoksa sessizliğe düş.
            if clip.lang != "tr-TR", AVSpeechSynthesisVoice(language: clip.lang) == nil {
                guard let tr = AnnouncementEngine.shared.turkishText(for: clip.key) else { return }
                await self.speakAndWait(tr, language: "tr-TR")
                return
            }
            await self.speakAndWait(clip.text, language: clip.lang)
        }
    }

    /// TTS'i konuşup bitişini bekle. Ses oturumu ve müzik kısma üstteki
    /// withAnnouncementAudio sarmalayıcısında yönetilir.
    private func speakAndWait(_ text: String, language: String) async {
        try? AVAudioSession.sharedInstance().setActive(true)
        let u = AVSpeechUtterance(string: text)
        u.voice = AVSpeechSynthesisVoice(language: language) ?? AVSpeechSynthesisVoice(language: "tr-TR")
        u.rate = AVSpeechUtteranceDefaultSpeechRate * 0.96
        u.postUtteranceDelay = 0.15
        // Bekçi: didFinish/didCancel hiç gelmezse (kesinti, sentezleyici hatası)
        // continuation sonsuza dek bekler ve seri sıra tamamen kilitlenir —
        // tahmini konuşma süresi + pay sonra sırayı kurtar.
        let timeout = Double(text.count) / 12.0 + 4.0
        let watchdog = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
            self?.resumeTTS()
        }
        await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
            ttsContinuation = c
            synth.speak(u)
        }
        watchdog.cancel()
    }

    private func speakOne(_ text: String, language: String) async {
        await withAnnouncementAudio {
            await self.speakAndWait(text, language: language)
        }
    }

    private func withAnnouncementAudio(_ body: @escaping @MainActor () async -> Void) async {
        beginAnnouncementAudio()
        try? await Task.sleep(nanoseconds: 350_000_000)
        await body()
        try? await Task.sleep(nanoseconds: 250_000_000)
        endAnnouncementAudio()
    }

    private func beginAnnouncementAudio() {
        MusicPlayer.shared.duck()
        try? AVAudioSession.sharedInstance().setCategory(
            .playback,
            mode: .spokenAudio,
            options: [.duckOthers, .interruptSpokenAudioAndMixWithOthers]
        )
        try? AVAudioSession.sharedInstance().setActive(true)
    }

    private func endAnnouncementAudio() {
        MusicPlayer.shared.unduck()
        if MusicPlayer.shared.isPlaying {
            MusicPlayer.shared.restoreSessionAfterAnnouncement()
        } else {
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        }
    }

    private func resumeTTS() {
        ttsContinuation?.resume()
        ttsContinuation = nil
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in self.resumeTTS() }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        Task { @MainActor in self.resumeTTS() }
    }

    // MARK: - Araç (CarPlay / araç ses yolu) tespiti

    @objc private nonisolated func routeChanged() {
        Task { @MainActor in self.checkCarRoute() }
    }

    private func checkCarRoute() {
        let outputs = AVAudioSession.sharedInstance().currentRoute.outputs
        let carNow = outputs.contains { $0.portType == .carAudio }
        if carNow && !inCar {
            inCar = true
            onCarConnected?()
        } else if !carNow {
            inCar = false
        }
    }

    // MARK: - Kaptan esprileri (Leyla'ya özel)

    /// Bir kategoriden kural-uyumlu anons çal (motor seçer). Uygun yoksa sessiz kalır.
    func announce(_ category: String) {
        guard enabled else { return }   // kapalıyken bekleme sürelerini tüketme
        guard let clip = AnnouncementEngine.shared.pick(category) else { return }
        say(clip)
    }

    /// Araç bağlanınca / yola çıkarken: TEK kaptan anonsu + sıradaki durak.
    /// Aynı kalkış hem düğme/modaldan (LegLauncher) hem araç bağlanınca
    /// (onCarConnected) ateşlenebilir — kısa pencerede ikinciyi yut.
    func announceDeparture(nextStop: String?) {
        guard enabled else { return }   // kapalıyken damga atma: pencere boşa yanar
        let now = Date()
        if let last = lastDeparture, last.stop == nextStop,
           now.timeIntervalSince(last.at) < 3 * 60 { return }
        lastDeparture = (nextStop, now)
        // Yeni etap başlıyor: önceki durağın varış damgası bu bacakta geçersiz —
        // aksi halde aynı durağa 6 saat içindeki MEŞRU yeniden varış yutulur.
        lastArrival = nil
        announce("captain")
        if let nextStop {
            speak("Sıradaki durak: \(nextStop). Hadi başlat!")
        }
    }

    /// Kullanıcı panelden açıkça isterse: rota gerçekten başlamadıysa "yola
    /// çıktık" dili kullanmadan yol tarifi başlatma yönlendirmesi yap.
    func announceRouteReady(nextStop: String?, triggeredByUserAction: Bool = false) {
        guard enabled else { return }
        guard RouteAnnouncementPolicy.allowsRouteReadyAnnouncement(
            triggeredByUserAction: triggeredByUserAction,
            routeStarted: RouteSession.shared.isActive
        ) else { return }
        announce("captain")
        if let nextStop {
            speak("Sıradaki rota hazır: \(nextStop). Başlatmak için Rotalar ekranında Buraya git'e dokun.")
        } else {
            speak("Rotalar hazır. Başlatmak için Rotalar ekranında sıradaki etapta Buraya git'e dokun.")
        }
    }

    // MARK: - Yerel dilde karşılama (varışta)

    /// Bir durağa varışta: Türkçe varyant + yerel dilde + (varsa) Riga'ya kalan.
    /// Geofence aynı durak için tekrar ateşlenebilir (izin yükseltmesinde bölgeler
    /// yeniden kurulur, çemberden çık-gir olur) — 6 saat içindeki tekrarı yut.
    /// Pencere yalnızca çift tetiklemeyi yutsun diye: kalkış (announceDeparture)
    /// bu damgayı sıfırlar, böylece yeni etabın varışı engellenmez.
    func announceArrival(stopName: String, remainingToFinalKm: Int?) {
        guard enabled else { return }   // kapalıyken damga atma: pencere boşa yanar
        let now = Date()
        if let last = lastArrival, last.stop == stopName,
           now.timeIntervalSince(last.at) < 6 * 3600 { return }
        lastArrival = (stopName, now)
        // Bu duraktan yeniden kalkışta kalkış anonsu engellenmesin.
        lastDeparture = nil
        let slug = AnnouncementCatalog.citySlug(for: stopName)
        for clip in AnnouncementEngine.shared.arrivalClips(citySlug: slug) {
            say(clip)
        }
        if let km = remainingToFinalKm, km > 0 {
            speak("Riga'ya \(km) kilometre kaldı.")
        }
    }

    // MARK: - Mesafe anonsu (her 100 km + yaklaşınca)

    func progressUpdate(nextStop: String, remainingKm: Int) {
        if lastStopForBucket != nextStop {
            lastStopForBucket = nextStop
            lastBucket = remainingKm / 100
            return
        }
        if remainingKm <= 15 {
            if lastBucket != -1 {
                lastBucket = -1
                speak("Sıradaki durak \(nextStop). Yaklaşıyoruz, \(remainingKm) kilometre kaldı.")
            }
            return
        }
        let bucket = remainingKm / 100
        // Yaklaşma anonsundan sonra mesafe tekrar açıldıysa durumu sıfırla
        // (aksi hâlde lastBucket=-1'e takılır, bu durak için bir daha anons çıkmaz).
        if lastBucket == -1 { lastBucket = bucket }
        if let last = lastBucket, bucket < last {
            lastBucket = bucket
            speak("Sıradaki durak \(nextStop). \(remainingKm) kilometre kaldı.")
        }
    }
}
