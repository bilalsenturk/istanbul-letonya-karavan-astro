import SwiftUI
import Speech
import AVFoundation

// Eller serbest sesli masraf: "45 euro yakıt Kapıkule" de → tutar+kategori+not ayrışır.
// Tanıma cihaz dilinde (tr-TR) Speech framework ile yapılır.
struct VoiceExpenseView: View {
    @EnvironmentObject var expenses: ExpenseStore
    @Environment(\.dismiss) private var dismiss
    @StateObject private var recorder = SpeechRecorder()
    @State private var denied = false

    private var parsed: (amount: Double?, category: ExpenseCategory, note: String) {
        Self.parse(recorder.transcript)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.bg.ignoresSafeArea()
                VStack(spacing: 22) {
                    Spacer()
                    Text(recorder.transcript.isEmpty
                         ? "Mikrofona dokun ve söyle:\n“45 euro yakıt Kapıkule”"
                         : recorder.transcript)
                        .font(.system(size: 19, weight: .medium, design: .rounded))
                        .foregroundStyle(recorder.transcript.isEmpty ? Theme.muted : Theme.text)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)

                    if let amount = parsed.amount {
                        VStack(spacing: 6) {
                            Text("€\(amount, specifier: amount.truncatingRemainder(dividingBy: 1) == 0 ? "%.0f" : "%.2f")")
                                .font(.system(size: 40, weight: .heavy, design: .rounded))
                                .foregroundStyle(Theme.text)
                            Label(parsed.category.label, systemImage: parsed.category.icon)
                                .font(.system(size: 14, weight: .bold, design: .rounded))
                                .foregroundStyle(parsed.category.color)
                        }
                    }

                    if denied {
                        Text("Mikrofon/konuşma izni verilmedi. Ayarlar'dan açabilirsin.")
                            .font(.system(size: 13))
                            .foregroundStyle(Theme.bad)
                    }

                    Spacer()

                    Button {
                        recorder.recording ? recorder.stop() : start()
                    } label: {
                        ZStack {
                            Circle()
                                .fill(recorder.recording ? AnyShapeStyle(Theme.bad) : AnyShapeStyle(Theme.gradWarm))
                                .frame(width: 86, height: 86)
                            Image(systemName: recorder.recording ? "stop.fill" : "mic.fill")
                                .font(.system(size: 30, weight: .bold))
                                .foregroundStyle(.white)
                        }
                    }
                    .buttonStyle(.plain)

                    Button {
                        if let amount = parsed.amount {
                            expenses.add(Expense(amountEur: amount, category: parsed.category, note: parsed.note))
                            dismiss()
                        }
                    } label: {
                        Text("Harcamayı Ekle")
                            .font(.system(size: 16, weight: .bold, design: .rounded))
                            .foregroundStyle(parsed.amount == nil ? Theme.muted : .white)
                            .frame(maxWidth: .infinity).padding(.vertical, 14)
                            .background(
                                parsed.amount == nil ? AnyShapeStyle(Theme.panel) : AnyShapeStyle(Theme.gradCool),
                                in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                            )
                    }
                    .buttonStyle(.plain)
                    .disabled(parsed.amount == nil)
                    .padding(.horizontal, 18)
                    .padding(.bottom, 14)
                }
            }
            .navigationTitle("Sesli Harcama")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Kapat") { recorder.stop(); dismiss() }.tint(Theme.muted)
                }
            }
        }
        .preferredColorScheme(.dark)
        .onDisappear { recorder.stop() }
    }

    private func start() {
        SFSpeechRecognizer.requestAuthorization { status in
            DispatchQueue.main.async {
                guard status == .authorized else { denied = true; return }
                AVAudioApplication.requestRecordPermission { granted in
                    DispatchQueue.main.async {
                        guard granted else { denied = true; return }
                        denied = false
                        try? recorder.start()
                    }
                }
            }
        }
    }

    /// "45 euro yakıt Kapıkule" → (45, .yakit, "Kapıkule …")
    static func parse(_ text: String) -> (Double?, ExpenseCategory, String) {
        let lower = text.lowercased()
        var amount: Double?
        if let regex = try? NSRegularExpression(pattern: #"(\d{1,5}(?:[.,]\d{1,2})?)"#),
           let match = regex.firstMatch(in: lower, range: NSRange(lower.startIndex..., in: lower)),
           let r = Range(match.range(at: 1), in: lower) {
            amount = Double(lower[r].replacingOccurrences(of: ",", with: "."))
        }

        let category: ExpenseCategory
        if ["yakıt", "benzin", "mazot", "motorin", "dizel", "depo"].contains(where: lower.contains) {
            category = .yakit
        } else if ["kamp", "konaklama", "gece"].contains(where: lower.contains) {
            category = .kamp
        } else if ["yemek", "restoran", "market", "kahvaltı", "atıştırmalık"].contains(where: lower.contains) {
            category = .yemek
        } else if ["geçiş", "otoyol", "vinyet", "köprü", "feribot"].contains(where: lower.contains) {
            category = .gecis
        } else {
            category = .diger
        }

        return (amount, category, text.trimmingCharacters(in: .whitespacesAndNewlines))
    }
}

// MARK: - Kayıt + tanıma motoru

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
