import AVFoundation
import Foundation
import Speech

// Türkçe sesli dikte. Hem sesli harcama hem günlük kullanır —
// aynı motoru iki yere kopyalamamak için ayrı dosyada.
@MainActor
final class SpeechRecorder: NSObject, ObservableObject {
    @Published var transcript = ""
    @Published var recording = false

    private let engine = AVAudioEngine()
    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "tr-TR"))
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    /// Ses oturumu `.record` moduna alınıp aktif edildi mi? `stop()`'un ses
    /// oturumunu `.playback`'e geri döndürüp döndürmeyeceğine bu karar verir —
    /// `start()` hiç çağrılmadan (ya da setCategory/setActive'den önce) `stop()`
    /// çağrılırsa gereksiz yere oturum değiştirilmesin diye.
    private var sessionActive = false

    func start() throws {
        guard let recognizer, recognizer.isAvailable else { return }
        stop()
        transcript = ""

        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.record, mode: .measurement, options: .duckOthers)
        try session.setActive(true, options: .notifyOthersOnDeactivation)
        sessionActive = true

        let req = SFSpeechAudioBufferRecognitionRequest()
        req.shouldReportPartialResults = true
        request = req

        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
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
                if let result { self?.transcript = result.bestTranscription.formattedString }
                if error != nil { self?.stop() }
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
        request?.endAudio()
        task?.cancel()
        task = nil
        request = nil
        recording = false

        guard sessionActive else { return }
        sessionActive = false
        // Anons (TTS) tekrar çalışabilsin diye ses oturumunu geri kur.
        try? AVAudioSession.sharedInstance().setCategory(.playback, options: [.mixWithOthers, .duckOthers])
    }
}
