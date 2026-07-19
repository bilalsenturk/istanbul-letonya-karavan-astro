import Foundation
import AVFoundation

// Sesli anons/kaptan sistemi — cihazda TTS (AVSpeechSynthesizer).
// Araç bağlantısını (CarPlay/araç ses yolu) tespit eder; bağlanınca "hadi başlat"
// + kaptan esprisi; duraklarda YEREL DİLDE karşılama; her 100 km'de mesafe anonsu.
//
// NOT: Native CarPlay ekranı için Apple onaylı entitlement + ücretli üyelik gerekir.
// Bu sistem CarPlay'e bağlıyken araç hoparlöründen konuşur; entitlement gerekmez.
@MainActor
final class AnnouncementService: NSObject, ObservableObject {
    static let shared = AnnouncementService()

    @Published var lastLine: String?
    @Published var enabled = true

    /// Araç bağlanınca app'in ne diyeceğini dışarıdan kurar (sıradaki durağa erişim için).
    var onCarConnected: (() -> Void)?

    private let synth = AVSpeechSynthesizer()
    private var inCar = false
    private var captainIndex = 0

    // Sıradaki hedefe mesafe anonsu için durum
    private var lastBucket: Int?
    private var lastStopForBucket: String?

    private override init() {
        super.init()
        try? AVAudioSession.sharedInstance().setCategory(.playback, options: [.mixWithOthers, .duckOthers])
        NotificationCenter.default.addObserver(self, selector: #selector(routeChanged),
                                               name: AVAudioSession.routeChangeNotification, object: nil)
        checkCarRoute()
    }

    // MARK: - Konuşma

    func speak(_ text: String, language: String = "tr-TR") {
        guard enabled else { return }
        lastLine = text
        try? AVAudioSession.sharedInstance().setActive(true)
        let u = AVSpeechUtterance(string: text)
        u.voice = AVSpeechSynthesisVoice(language: language) ?? AVSpeechSynthesisVoice(language: "tr-TR")
        u.rate = AVSpeechUtteranceDefaultSpeechRate * 0.96
        u.postUtteranceDelay = 0.15
        synth.speak(u)
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

    private let captainLines = [
        "Değerli yolcularımız, kaptanınız konuşuyor. Lütfen kemerlerinizi bağlayın. Çiş molası verilmeyecektir.",
        "Arabada pırt yapmak kesinlikle yasaktır. Leyla, sana bakıyorum.",
        "Kaptan konuşuyor: müzik seçme yetkisi kaptandadır, itirazlar dinlenmeyecektir.",
        "Sevgili yolcular, hafif türbülans — yani Balkan yolları — bekleniyor. Kemerler bağlı kalsın.",
        "Leyla için özel anons: atıştırmalıkların yarısı kaptana aittir. İyi yolculuklar.",
        "Uçuşumuz, pardon, yolculuğumuz başlıyor. Koltuğunuzu dik konuma getirin ve gülümseyin.",
    ]

    func nextCaptainLine() -> String {
        defer { captainIndex = (captainIndex + 1) % captainLines.count }
        return captainLines[captainIndex]
    }

    /// Araç bağlanınca / yola çıkarken: kaptan esprisi + sıradaki durak + hadi başlat.
    func announceDeparture(nextStop: String?) {
        var line = nextCaptainLine()
        if let nextStop { line += " Sıradaki durak: \(nextStop). Hadi başlat!" }
        speak(line)
    }

    // MARK: - Yerel dilde karşılama (varışta)

    private static let welcomes: [String: (lang: String, text: String)] = [
        "İstanbul": ("tr-TR", "İstanbul'a hoş geldiniz."),
        "Sofya": ("bg-BG", "Добре дошли в София."),
        "Bükreş": ("ro-RO", "Bun venit la București."),
        "Bükreş Güney": ("ro-RO", "Bun venit la București."),
        "Deva": ("ro-RO", "Bun venit la Deva."),
        "Budapeşte": ("hu-HU", "Üdvözöljük Budapesten."),
        "Katowice": ("pl-PL", "Witamy w Katowicach."),
        "Suwałki": ("pl-PL", "Witamy w Suwałkach."),
        "Riga": ("lv-LV", "Laipni lūdzam Rīgā."),
    ]

    /// Bir durağa varışta: Türkçe karşılama + yerel dilde + (varsa) Riga'ya kalan.
    func announceArrival(stopName: String, remainingToFinalKm: Int?) {
        speak("\(stopName), hoş geldiniz.")
        if let w = Self.welcomes[stopName], w.lang != "tr-TR" {
            speak(w.text, language: w.lang)
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
        if let last = lastBucket, bucket < last {
            lastBucket = bucket
            speak("Sıradaki durak \(nextStop). \(remainingKm) kilometre kaldı.")
        } else if lastBucket == nil {
            lastBucket = bucket
        }
    }
}
