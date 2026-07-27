import Foundation

enum LatvianModality: String, Codable, Hashable, Sendable {
    case recognition
    case production
}

extension LatvianExerciseKind {
    /// Hangi hafıza kaydını beslediğini belirler.
    var modality: LatvianModality {
        switch self {
        case .listenChoose, .iconChoose, .match, .lvToTr, .fillBlank:
            return .recognition
        case .trToLv, .dictation, .order, .speak, .caseDrill:
            return .production
        }
    }

    var turkishTitle: String {
        switch self {
        case .listenChoose: return "Dinle ve seç"
        case .iconChoose: return "Görselden seç"
        case .lvToTr: return "Letoncadan Türkçeye"
        case .trToLv: return "Türkçeden Letoncaya"
        case .match: return "Eşleştir"
        case .fillBlank: return "Boşluğu doldur"
        case .caseDrill: return "Doğru eki seç"
        case .dictation: return "Duyduğunu yaz"
        case .order: return "Cümleyi sırala"
        case .speak: return "Dinle ve tekrar et"
        }
    }
}

struct LatvianMatchPair: Hashable, Sendable {
    let lv: String
    let tr: String
}

enum LatvianExerciseContent: Hashable, Sendable {
    /// Tek doğru cevaplı seçmeli. `iconChoose` için seçenekler emoji taşır.
    case choice(options: [String], correctIndex: Int)
    /// Kelime bankasından cümle kurma. `bank` karıştırılmış, `answer` doğru sıra.
    case wordBank(bank: [String], answer: [String])
    /// Dokunarak eşleştirme.
    case matching(pairs: [LatvianMatchPair])
    /// Klavyeyle yazma. `accepted` tüm kabul edilebilir yazımlar.
    case typing(accepted: [String])
    /// Telaffuz. `target` söylenmesi gereken metin.
    case speaking(target: String)
}

struct LatvianExercise: Identifiable, Hashable, Sendable {
    let id: String
    let kind: LatvianExerciseKind
    let targetWordId: String
    let prompt: String
    /// Varsa çalınacak ses. `listenChoose`, `dictation`, `speak` için zorunlu.
    let audioId: String?
    let content: LatvianExerciseContent
    /// Boşluk doldurma ve hal tatbikatında gösterilen, altı çizili cümle.
    var carrier: String?
    /// Yanlış cevapta gösterilecek Türkçe açıklama.
    var explanation: String?

    init(
        id: String,
        kind: LatvianExerciseKind,
        targetWordId: String,
        prompt: String,
        audioId: String? = nil,
        content: LatvianExerciseContent,
        carrier: String? = nil,
        explanation: String? = nil
    ) {
        self.id = id
        self.kind = kind
        self.targetWordId = targetWordId
        self.prompt = prompt
        self.audioId = audioId
        self.content = content
        self.carrier = carrier
        self.explanation = explanation
    }

    var modality: LatvianModality { kind.modality }

    var optionCount: Int {
        if case .choice(let options, _) = content { return options.count }
        return 0
    }

    /// Ses gerektiren sorular, sesi inmemişse üretilmez.
    var requiresAudio: Bool {
        switch kind {
        case .listenChoose, .dictation, .speak: return true
        default: return false
        }
    }
}

enum LatvianAnswer: Hashable, Sendable {
    case choice(index: Int)
    case words([String])
    case text(String)
    case pairs([LatvianMatchPair])
    case spoken(transcript: String)
}
