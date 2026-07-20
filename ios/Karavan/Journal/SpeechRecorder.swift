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

    func start() throws {
        guard let recognizer, recognizer.isAvailable else { return }
        stop()
        transcript = ""

        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.record, mode: .measurement, options: .duckOthers)
        try session.setActive(true, options: .notifyOthersOnDeactivation)

        let req = SFSpeechAudioBufferRecognitionRequest()
        req.shouldReportPartialResults = true
        request = req

        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
            req.append(buffer)
        }
        engine.prepare()
        try engine.start()
        recording = true

        task = recognizer.recognitionTask(with: req) { [weak self] result, error in
            DispatchQueue.main.async {
                if let result { self?.transcript = result.bestTranscription.formattedString }
                if error != nil { self?.stop() }
            }
        }
    }

    func stop() {
        guard recording || engine.isRunning else { return }
        engine.stop()
        engine.inputNode.removeTap(onBus: 0)
        request?.endAudio()
        task?.cancel()
        task = nil
        request = nil
        recording = false
        // Anons (TTS) tekrar çalışabilsin diye ses oturumunu geri kur.
        try? AVAudioSession.sharedInstance().setCategory(.playback, options: [.mixWithOthers, .duckOthers])
    }
}
