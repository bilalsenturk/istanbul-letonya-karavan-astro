import AVFoundation
import Foundation
import Speech

// Türkçe sesli dikte. Hem sesli harcama hem günlük kullanır —
// aynı motoru iki yere kopyalamamak için ayrı dosyada.
@MainActor
final class SpeechRecorder: NSObject, ObservableObject {
    /// start()'un sessizce ölü kalmasını engelleyen hata yüzeyi: tanıyıcı
    /// yok/kapalı ya da mikrofon hattı (rota değişimi sonrası) geçersiz bir
    /// format veriyor. Çağıranlar bunu kullanıcıya göstermeli — yutulan hata
    /// düğmeyi ölü bırakır.
    enum SpeechRecorderError: Error {
        case recognizerUnavailable
        case audioInputUnavailable
    }

    @Published var transcript = ""
    @Published var recording = false

    private let engine = AVAudioEngine()
    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "tr-TR"))
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    /// Ses oturumu `.record` moduna alınıp aktif edildi mi? `stop()`'un ses
    /// oturumunu geri döndürüp döndürmeyeceğine bu karar verir —
    /// `start()` hiç çağrılmadan (ya da setCategory/setActive'den önce) `stop()`
    /// çağrılırsa gereksiz yere oturum değiştirilmesin diye.
    private var sessionActive = false
    /// `.record`'a geçmeden ÖNCE oturumun durumu. `stop()` hep aynı sabite
    /// (.playback + mixWithOthers) dönüyordu; oysa MusicPlayer [.duckOthers]
    /// ile kurmuş olabilir — kaydedicinin değiştirmediği hâl neyse ona dön.
    private var previousCategory: AVAudioSession.Category?
    private var previousCategoryOptions: AVAudioSession.CategoryOptions = []

    func start() throws {
        // Eskiden burada sessiz `return` vardı — izin verilmiş ama tanıyıcı
        // kullanılamıyorsa (ör. cihaz dikteyi desteklemiyor, siri kapalı)
        // düğme hiçbir tepki vermeden ölü kalıyordu. Hata fırlat ki çağıran
        // kullanıcıya göstersin.
        guard let recognizer, recognizer.isAvailable else {
            throw SpeechRecorderError.recognizerUnavailable
        }
        stop()
        transcript = ""

        let session = AVAudioSession.sharedInstance()
        // Kendi değişikliğimizden önceki hâli yakala — stop() buna dönecek.
        previousCategory = session.category
        previousCategoryOptions = session.categoryOptions
        try session.setCategory(.record, mode: .measurement, options: .duckOthers)
        try session.setActive(true, options: .notifyOthersOnDeactivation)
        sessionActive = true

        let req = SFSpeechAudioBufferRecognitionRequest()
        req.shouldReportPartialResults = true
        request = req

        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        // Rota değişimi (kulaklık takılması/çıkması, telefon araması) sırasında
        // outputFormat 0 kanal / 0 Hz dönebilir; bu formatla installTap
        // yakalanamayan bir NSException fırlatır (Swift try ile YAKALANMAZ,
        // uygulama çöker). Tap'ten ÖNCE doğrula ve temiz çık.
        guard format.channelCount > 0, format.sampleRate > 0 else {
            stop()
            throw SpeechRecorderError.audioInputUnavailable
        }
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
            req.append(buffer)
        }

        do {
            engine.prepare()
            try engine.start()
        } catch {
            // engine.start() hata fırlatırsa `recording` hiç true olmadan
            // çıkılıyordu; ama tap zaten kuruluydu ve ses oturumu `.record`'da
            // aktif kalıyordu. Eskiden `stop()`'un guard'ı (`recording ||
            // engine.isRunning`) bu durumda erken dönüp hiçbir şey temizlemiyordu
            // — bir sonraki `start()` çağrısı aynı bus'a İKİNCİ bir tap kurup
            // çökebiliyordu. `stop()` artık guard'sız, her koşulda güvenli
            // çalıştığı için burada ona devretmek tutarlı bir duruma dönmeye yeter.
            stop()
            throw error
        }
        recording = true

        task = recognizer.recognitionTask(with: req) { [weak self] result, error in
            DispatchQueue.main.async {
                // stop() sonrası GECİKMİŞ bir sonuç gelirse metni ezmeyin:
                // kullanıcı dikteyi bitirip elle düzenlemeye başlamış
                // olabilir — kayıt artık kapalıyken gelen sonuç o
                // düzenlemeleri silerdi (transcript onChange'i metni taban +
                // transcript olarak baştan kurar).
                guard let self, self.recording else { return }
                if let result { self.transcript = result.bestTranscription.formattedString }
                if error != nil { self.stop() }
            }
        }
    }

    func stop() {
        // Eskiden `guard recording || engine.isRunning else { return }` vardı —
        // `engine.start()` hata verdiğinde ikisi de false kalıyor ve bu guard
        // temizliği tamamen atlıyordu (tap kurulu, oturum aktif kalıyordu).
        // engine.stop()/removeTap(onBus:) zaten kurulu bir şey yokken de güvenle
        // çağrılabilir (no-op) — bu yüzden koşulsuz her zaman çalıştırılır.
        engine.stop()
        engine.inputNode.removeTap(onBus: 0)
        // Önce task iptali: endAudio'dan SONRA tanıyıcı bir "son sonuç"
        // üretebilir ve handler'ın recording kontrolü olmadan metni ezmesi
        // söz konusuydu. İptal edilen task artık sonuç iletmez.
        task?.cancel()
        task = nil
        request?.endAudio()
        request = nil
        recording = false

        guard sessionActive else { return }
        sessionActive = false
        // Anons (TTS)/müzik tekrar çalışabilsin diye ses oturumunu, bu
        // kaydedici değiştirmeden ÖNCEKİ hâline geri kur (MusicPlayer
        // [.duckOthers] ile kurmuş olabilir; sabit bir preset'e dönmek
        // başka bir çalanın karışım davranışını bozardı).
        if let previousCategory {
            try? AVAudioSession.sharedInstance().setCategory(previousCategory, options: previousCategoryOptions)
            self.previousCategory = nil
            previousCategoryOptions = []
        } else {
            try? AVAudioSession.sharedInstance().setCategory(.playback, options: [.mixWithOthers, .duckOthers])
        }
    }
}
