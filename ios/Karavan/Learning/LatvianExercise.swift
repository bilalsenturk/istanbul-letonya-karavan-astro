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
        // Bir çekim eki drilidir ama gövde verilir ve cevap üç seçenekten seçilir
        // (fillBlank ile aynı yapı); kelime hiç üretilmediği için tanıma sayılır.
        case .caseDrill:
            return .recognition
        case .trToLv, .dictation, .order, .speak:
            return .production
        }
    }

    /// Soru tipinin öğrenciden istediği şeyin ağırlığı; küçük olan daha kolay.
    ///
    /// Sıra iki ölçüte göre: **cevabın biçimi** (birkaç seçenekten dokunmak < bir kelime
    /// bankasını sıraya dizmek < klavyeyle yazmak) ve **modalite** (tanımak < üretmek).
    /// Bu yüzden tüm tanıma tipleri tüm üretim tiplerinin önünde geliyor.
    ///
    /// Tek kullanıcısı ders kurgusundaki kurtarma merdiveni (bkz.
    /// `LatvianLessonBuilder.rescueKinds`): takılan bir kelime bu sıranın başından
    /// yeniden öğretiliyor, kartı toparladıkça merdivende yukarı çıkıyor. Mutlak
    /// değerlerin anlamı yok, yalnızca sıraları kullanılıyor.
    var difficultyRank: Int {
        switch self {
        case .iconChoose: return 0   // görsel ipucu + dört seçenek
        case .listenChoose: return 1 // ses ipucu + dört seçenek
        case .fillBlank: return 2    // cümle bağlamı + dört seçenek
        case .caseDrill: return 3    // gövde verili, üç ek seçeneği
        case .match: return 4        // dört çift aynı anda
        case .lvToTr: return 5       // Letonca cümleyi anlayıp Türkçesini dizme
        case .order: return 6        // verili Letonca kelimeleri sıraya dizme
        case .trToLv: return 7       // Türkçeden Letonca cümle kurma
        case .speak: return 8        // duyduğunu telaffuz etme
        case .dictation: return 9    // duyduğunu harfi harfine yazma
        }
    }

    /// Cevabın "easy" sayılması için altında kalması gereken süre (saniye).
    /// Soru tipinin gerektirdiği motor eyleme göre ölçeklenir: bir seçeneğe dokunmak
    /// birkaç saniye sürer, bir cümleyi dikteyle yazmak ya da konuşmak çok daha uzun sürer;
    /// tek bir eşik kullanmak yazma/konuşma sorularını hep "good" ile sınırlardı.
    var fastThresholdSeconds: TimeInterval {
        switch self {
        case .listenChoose, .iconChoose, .fillBlank, .caseDrill:
            return 5
        case .speak:
            return 10
        case .lvToTr, .trToLv, .order, .dictation:
            return 12
        case .match:
            return 15
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

    /// **Cevabın** Türkçesi — cevap doğru da olsa yanlış da olsa panelde gösterilir.
    ///
    /// Eskiden burada `explanation` adlı tek bir alan vardı ve adı ne taşıdığını
    /// söylemediği için `trToLv`/`order`'da Letonca cümlenin kendisi yazılmıştı:
    /// öğrenci cevabı Letonca görüyor, altında yine Letonca okuyor, Türkçesini
    /// hiç öğrenmiyordu. Ad artık içeriği taahhüt ediyor ve motor kontrolü bunu
    /// gerçek paket üzerinde harfi harfine doğruluyor.
    ///
    /// `nil` olduğu iki yer var ve ikisi de bilerek: `lvToTr`'de cevabın kendisi
    /// zaten Türkçe, `match`'te dört çiftin Türkçesi zaten cevabın içinde.
    var answerGlossTr: String?

    /// **Cevabı** seslendiren klip. Sorunun `audioId`'siyle aynı olmak zorunda
    /// değil: `fillBlank`'te soru sessizdir ama cevap tek bir kelimedir ve o
    /// kelimenin klibi vardır; `lvToTr`'de soru sessizdir ama okunan Letonca
    /// cümlenin klibi vardır.
    ///
    /// Yalnızca inmiş klipler yazılır (bkz. `LatvianExerciseFactory`), yani
    /// panel bu alanı gördüğünde düğmeyi koşulsuz çizebilir.
    var answerAudioId: String?

    init(
        id: String,
        kind: LatvianExerciseKind,
        targetWordId: String,
        prompt: String,
        audioId: String? = nil,
        content: LatvianExerciseContent,
        carrier: String? = nil,
        answerGlossTr: String? = nil,
        answerAudioId: String? = nil
    ) {
        self.id = id
        self.kind = kind
        self.targetWordId = targetWordId
        self.prompt = prompt
        self.audioId = audioId
        self.content = content
        self.carrier = carrier
        self.answerGlossTr = answerGlossTr
        self.answerAudioId = answerAudioId
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
