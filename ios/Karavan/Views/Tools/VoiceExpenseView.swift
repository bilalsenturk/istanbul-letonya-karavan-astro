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
    @State private var startFailed = false

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

                    if startFailed {
                        Text("Ses motoru başlatılamadı. Kapatıp tekrar dene.")
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
                        do {
                            try recorder.start()
                            startFailed = false
                        } catch {
                            startFailed = true   // motor hatasını yutma — ölü mikrofon düğmesi kalmasın
                        }
                    }
                }
            }
        }
    }

    /// "45 euro yakıt Kapıkule" → (45, .yakit, "Kapıkule")
    /// Tutar + para birimi + kategori kelimesi nottan ayıklanır; geriye yer/ad kalır.
    static func parse(_ text: String) -> (Double?, ExpenseCategory, String) {
        let lower = text.lowercased()
        var amount: Double?
        if let regex = try? NSRegularExpression(pattern: #"(\d{1,5}(?:[.,]\d{1,2})?)"#),
           let match = regex.firstMatch(in: lower, range: NSRange(lower.startIndex..., in: lower)),
           let r = Range(match.range(at: 1), in: lower) {
            amount = Double(lower[r].replacingOccurrences(of: ",", with: "."))
        }

        var category: ExpenseCategory = .diger
        var matchedKeyword: String?
        for (cat, words) in [(ExpenseCategory.yakit, ["yakıt", "benzin", "mazot", "motorin", "dizel", "depo"]),
                             (.kamp, ["kamp", "konaklama", "gece"]),
                             (.yemek, ["yemek", "restoran", "market", "kahvaltı", "atıştırmalık"]),
                             (.gecis, ["geçiş", "otoyol", "vinyet", "köprü", "feribot"])] {
            if let hit = words.first(where: { lower.contains($0) }) {
                category = cat
                matchedKeyword = hit
                break
            }
        }

        // Not: tutar, para birimi ("euro", "€", "tl") ve kategori kelimesi
        // özgün metinden (büyük/küçük harf duyarsız) çıkarılır; geriye
        // özgün yazımıyla yer/ad kalır ("Kapıkule").
        var note = text
        if let regex = try? NSRegularExpression(pattern: #"(\d{1,5}(?:[.,]\d{1,2})?)"#),
           let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
           let r = Range(match.range(at: 1), in: text) {
            note.removeSubrange(r)
        }
        for token in ["euro", "avro", "€", "tl"] {
            note = note.replacingOccurrences(of: token, with: " ", options: .caseInsensitive)
        }
        if let matchedKeyword {
            note = note.replacingOccurrences(of: matchedKeyword, with: " ", options: .caseInsensitive)
        }
        note = note.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return (amount, category, note)
    }
}
