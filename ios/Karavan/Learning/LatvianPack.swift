import Foundation

enum LatvianExerciseKind: String, Codable, CaseIterable, Sendable {
    case listenChoose = "listen_choose"
    case iconChoose = "icon_choose"
    case lvToTr = "lv_to_tr"
    case trToLv = "tr_to_lv"
    case match
    case fillBlank = "fill_blank"
    case caseDrill = "case_drill"
    case dictation
    case order
    case speak
}

enum LatvianCase: String, Codable, Sendable {
    case nominativ, genitiv, dativ, akuzativ, instrumental, lokativ, vokativ
}

struct LatvianCaseForm: Codable, Hashable, Sendable {
    let base: String
    let form: String
    let `case`: LatvianCase
    let suffix: String
    let distractorSuffixes: [String]
}

struct LatvianWord: Codable, Hashable, Identifiable, Sendable {
    let id: String
    let lv: String
    let tr: String
    let icon: String?
    let audioId: String
    let lemma: String
    let freqRank: Int
    let caseForm: LatvianCaseForm?
}

struct LatvianSentence: Codable, Hashable, Identifiable, Sendable {
    let id: String
    let lv: String
    let tr: String
    let audioId: String
    let wordIds: [String]
    let supports: [LatvianExerciseKind]
}

struct LatvianScene: Codable, Hashable, Identifiable, Sendable {
    let id: String
    let index: Int
    let title: String
    let words: [LatvianWord]
    let sentences: [LatvianSentence]
}

struct LatvianPack: Codable, Sendable {
    static let supportedVersion = 1

    let version: Int
    let generatedAt: String
    let audioBaseUrl: String
    let scenes: [LatvianScene]

    /// Kimlik → içerik dizinleri. Ders kurulumu bu aramaları kelime başına birkaç kez
    /// yaptığından, sahneler üzerinde doğrusal tarama yerine bir kez dizin kuruluyor.
    /// Dizinler kodlanmıyor: `CodingKeys` onları dışarıda bırakıyor ve `init(from:)`
    /// çözümlemeden sonra `scenes`'ten türetiyor. Böylece hem `decode(from:)` hem
    /// `loadBundled` her zaman dizinli bir örnek döndürüyor.
    private let wordIndex: [String: LatvianWord]
    private let sceneIndex: [String: LatvianScene]
    private let sentenceIndex: [String: LatvianSentence]

    private enum CodingKeys: String, CodingKey {
        case version, generatedAt, audioBaseUrl, scenes
    }

    init(version: Int, generatedAt: String, audioBaseUrl: String, scenes: [LatvianScene]) {
        self.version = version
        self.generatedAt = generatedAt
        self.audioBaseUrl = audioBaseUrl
        self.scenes = scenes

        var words: [String: LatvianWord] = [:]
        var sceneMap: [String: LatvianScene] = [:]
        var sentences: [String: LatvianSentence] = [:]
        // Aynı kimlik iki kez geçerse ilk giren kazanıyor — eski `first { $0.id == id }`
        // taramasının davranışı buydu.
        for scene in scenes {
            if sceneMap[scene.id] == nil { sceneMap[scene.id] = scene }
            for word in scene.words where words[word.id] == nil {
                words[word.id] = word
            }
            for sentence in scene.sentences where sentences[sentence.id] == nil {
                sentences[sentence.id] = sentence
            }
        }
        wordIndex = words
        sceneIndex = sceneMap
        sentenceIndex = sentences
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            version: try container.decode(Int.self, forKey: .version),
            generatedAt: try container.decode(String.self, forKey: .generatedAt),
            audioBaseUrl: try container.decode(String.self, forKey: .audioBaseUrl),
            scenes: try container.decode([LatvianScene].self, forKey: .scenes)
        )
    }

    static func decode(from data: Data) throws -> LatvianPack {
        let pack = try JSONDecoder().decode(LatvianPack.self, from: data)
        guard pack.version == supportedVersion else {
            throw LatvianPackError.unsupportedVersion(pack.version)
        }
        guard !pack.scenes.isEmpty else { throw LatvianPackError.empty }
        return pack
    }

    static func loadBundled(name: String = "latvian-pack") throws -> LatvianPack {
        guard let url = Bundle.main.url(forResource: name, withExtension: "json") else {
            throw LatvianPackError.missingResource(name)
        }
        return try decode(from: Data(contentsOf: url))
    }

    func word(id: String) -> LatvianWord? { wordIndex[id] }

    func scene(id: String) -> LatvianScene? { sceneIndex[id] }

    func sentence(id: String) -> LatvianSentence? { sentenceIndex[id] }

    func audioURL(for audioId: String) -> URL {
        URL(string: "\(audioBaseUrl)/\(audioId).mp3")!
    }

    /// Ses kimliği → seslendirilen metin. Ses indirme aşaması bunu kullanır.
    var audioManifest: [String: String] {
        var manifest: [String: String] = [:]
        for scene in scenes {
            for word in scene.words { manifest[word.audioId] = word.lv }
            for sentence in scene.sentences { manifest[sentence.audioId] = sentence.lv }
        }
        return manifest
    }
}

enum LatvianPackError: Error, LocalizedError {
    case unsupportedVersion(Int)
    case empty
    case missingResource(String)

    var errorDescription: String? {
        switch self {
        case .unsupportedVersion(let version):
            return "Letonca paketi sürüm \(version) desteklenmiyor."
        case .empty:
            return "Letonca paketinde sahne yok."
        case .missingResource(let name):
            return "Letonca paketi bulunamadı: \(name).json"
        }
    }
}
