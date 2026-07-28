import AVFoundation
import Foundation
import Speech

/// Letonca telaffuz sorusunun mikrofon tarafı.
///
/// `Journal/SpeechRecorder` ile aynı iskelet — ayrı bir tip, çünkü o Türkçeye
/// (`tr-TR`) sabit ve ders ekranının ihtiyaç duyduğu "kullanılamıyor" hâllerini
/// Türkçe metin olarak yayınlamıyor.
///
/// Sessizce ölmemek bu sınıfın tek işi. Dört ayrı yerde yolun kapanabildiği
/// biliniyor ve dördü de kullanıcıya görünür bir Türkçe cümleye çevriliyor:
/// `lv-LV` tanıyıcısı yok (Apple Letoncayı hiç içermiyor, bkz.
/// `LatvianSpeechAvailability` — bu yüzden ders artık telaffuz sorusu üretmiyor ve
/// bu yol pratikte açılmıyor), konuşma tanıma izni yok, mikrofon izni yok,
/// ses hattı açılmıyor. Brifingdeki taslak `try?` ile yutuyor ve `isRecording`'i
/// yine de `true` yapıyordu: mikrofon hiç açılmamışken ekranda "Dinliyorum…"
/// yazıyor, hiçbir zaman da bir şey duymuyordu.
@MainActor
final class LatvianSpeechRecognizer: ObservableObject {
    /// Tanınan metin. Kısmi sonuçlar da buraya yazılıyor; görünüm her
    /// değişimde cevabı yeniden yayınlıyor.
    @Published private(set) var transcript = ""
    @Published private(set) var isRecording = false
    /// Kullanıcıya gösterilecek Türkçe hata. `nil` ise sorun yok.
    @Published private(set) var errorText: String?

    /// Letonca dikte tanınmıyorsa düğme baştan kapalı olmalı.
    let isSupported: Bool

    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "lv-LV"))
    private let engine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var tapInstalled = false
    private var sessionActive = false
    /// `.record`'a geçmeden önceki oturum hâli. `stop()` sabit bir hazır ayara
    /// değil, tam olarak buna dönüyor: ders sesleri (`LatvianAudioStore`) ve yol
    /// müziği aynı oturumu paylaşıyor.
    private var previousCategory: AVAudioSession.Category?
    private var previousOptions: AVAudioSession.CategoryOptions = []

    init() {
        // Ders kurucusunun `speak`'i düşürürken baktığı bayrağın aynısı: iki taraf
        // aynı soruya farklı cevap veremesin.
        isSupported = LatvianSpeechAvailability.hasLatvian
    }

    // MARK: - Akış

    func start() {
        guard !isRecording else { return }
        guard let recognizer, recognizer.isAvailable else {
            fail("Apple'ın konuşma tanıması Letoncayı desteklemiyor — telefonunda bir sorun yok."
                 + " Yazarak gönderebilirsin.")
            return
        }
        errorText = nil
        // `recognizer` bilerek geri çağrılara taşınmıyor: `SFSpeechRecognizer`
        // `Sendable` değil ve izin geri çağrıları `@Sendable`. Her adım ana
        // aktöre dönüp tanıyıcıyı yeniden okuyor.
        SFSpeechRecognizer.requestAuthorization { status in
            Task { @MainActor [weak self] in
                guard let self else { return }
                guard status == .authorized else {
                    self.fail("Konuşma tanıma izni kapalı. Ayarlar'dan açabilir ya da yazarak gönderebilirsin.")
                    return
                }
                self.requestMicrophone()
            }
        }
    }

    private func requestMicrophone() {
        AVAudioApplication.requestRecordPermission { granted in
            Task { @MainActor [weak self] in
                guard let self else { return }
                guard granted else {
                    self.fail("Mikrofon izni kapalı. Ayarlar'dan açabilir ya da yazarak gönderebilirsin.")
                    return
                }
                self.beginCapture()
            }
        }
    }

    /// Her koşulda güvenli: hiç başlamamışken de, yarıda kalmışken de çağrılabilir.
    func stop() {
        engine.stop()
        if tapInstalled {
            engine.inputNode.removeTap(onBus: 0)
            tapInstalled = false
        }
        // Önce iptal: `endAudio()`'dan sonra gelen "son sonuç" kapanmış bir
        // soruya cevap yazmasın.
        task?.cancel()
        task = nil
        request?.endAudio()
        request = nil
        isRecording = false
        restoreSession()
    }

    /// Yeni soruya geçerken. Kaydı da durduruyor — soru değişirken açık kalan
    /// mikrofon bir sonraki sorunun cevabını yazardı.
    func reset() {
        stop()
        transcript = ""
        errorText = nil
    }

    // MARK: - Yakalama

    private func beginCapture() {
        guard let recognizer, recognizer.isAvailable else {
            fail("Apple'ın konuşma tanıması Letoncayı desteklemiyor — telefonunda bir sorun yok."
                 + " Yazarak gönderebilirsin.")
            return
        }
        stop()
        transcript = ""

        let session = AVAudioSession.sharedInstance()
        previousCategory = session.category
        previousOptions = session.categoryOptions
        // Bayrak denemeden ÖNCE kalkıyor: `setCategory` geçip `setActive`
        // düşerse oturum `.record`'da kalmış oluyor ve `stop()` onu geri
        // döndürmek zorunda. Değişiklik hiç olmadıysa geri dönüş zararsız.
        sessionActive = true
        do {
            try session.setCategory(.record, mode: .measurement, options: .duckOthers)
            try session.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            stop()
            fail("Mikrofon açılamadı. Tekrar dene ya da yazarak gönder.")
            return
        }

        let audioRequest = SFSpeechAudioBufferRecognitionRequest()
        audioRequest.shouldReportPartialResults = true
        request = audioRequest

        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        // Rota değişiminde (kulaklık, arama) format 0 kanal/0 Hz dönebiliyor ve
        // `installTap` Swift'in yakalayamadığı bir NSException atıyor.
        guard format.channelCount > 0, format.sampleRate > 0 else {
            stop()
            fail("Mikrofon şu an başka bir şey tarafından kullanılıyor. Tekrar dene.")
            return
        }
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
            audioRequest.append(buffer)
        }
        tapInstalled = true

        do {
            engine.prepare()
            try engine.start()
        } catch {
            stop()
            fail("Mikrofon başlatılamadı. Tekrar dene ya da yazarak gönder.")
            return
        }
        isRecording = true

        task = recognizer.recognitionTask(with: audioRequest) { [weak self] result, error in
            Task { @MainActor [weak self] in
                guard let self, self.isRecording else { return }
                if let result {
                    self.transcript = result.bestTranscription.formattedString
                    if result.isFinal { self.stop() }
                }
                if error != nil {
                    self.stop()
                    // Hiç kelime çıkmadan düşen tanıma, sessiz bir düğme demek.
                    if self.transcript.isEmpty {
                        self.fail("Seni duyamadım. Tekrar dene ya da yazarak gönder.")
                    }
                }
            }
        }
    }

    private func fail(_ message: String) {
        isRecording = false
        errorText = message
    }

    private func restoreSession() {
        guard sessionActive else { return }
        sessionActive = false
        let session = AVAudioSession.sharedInstance()
        if let previousCategory {
            try? session.setCategory(previousCategory, options: previousOptions)
            self.previousCategory = nil
            previousOptions = []
        } else {
            try? session.setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
        }
    }
}
