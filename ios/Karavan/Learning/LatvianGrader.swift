import Foundation

struct LatvianGrade: Hashable, Sendable {
    let isCorrect: Bool
    let correctAnswer: String
}

enum LatvianGrader {
    /// Karşılaştırma için metni sadeleştirir: küçük harf, diakritiksiz, noktalamasız, tek boşluklu.
    /// Amacı, `ā` yazamayan kullanıcıyı cezalandırmamak.
    static func normalize(_ text: String) -> String {
        // Türkçe İ/ı, standart Unicode büyük/küçük harf katlamasında "i"ye erimez
        // (İ combining-dot alır, ı ayrı bir taban harf sayılır); klavyede bu farkı
        // yazamayan kullanıcıyı cezalandırmamak için önce ASCII I/i'ye eşitleniyor.
        let turkishNormalized = text
            .replacingOccurrences(of: "İ", with: "I")
            .replacingOccurrences(of: "ı", with: "i")
        let folded = turkishNormalized.folding(
            options: [.diacriticInsensitive, .caseInsensitive, .widthInsensitive],
            locale: Locale(identifier: "en_US_POSIX")
        )
        let stripped = folded.unicodeScalars
            .map { CharacterSet.alphanumerics.contains($0) ? Character($0) : " " }
            .reduce(into: "") { $0.append($1) }
        return stripped.split(separator: " ").joined(separator: " ")
    }

    static func grade(exercise: LatvianExercise, answer: LatvianAnswer) -> LatvianGrade {
        switch exercise.content {
        case .choice(let options, let correctIndex):
            let correctAnswer = options.indices.contains(correctIndex) ? options[correctIndex] : ""
            guard case .choice(let index) = answer else {
                return LatvianGrade(isCorrect: false, correctAnswer: correctAnswer)
            }
            guard options.indices.contains(index) else {
                return LatvianGrade(isCorrect: false, correctAnswer: correctAnswer)
            }
            return LatvianGrade(isCorrect: index == correctIndex, correctAnswer: correctAnswer)

        case .wordBank(_, let expected):
            let correctAnswer = expected.joined(separator: " ")
            guard case .words(let submitted) = answer else {
                return LatvianGrade(isCorrect: false, correctAnswer: correctAnswer)
            }
            let isCorrect = normalize(submitted.joined(separator: " ")) == normalize(correctAnswer)
            return LatvianGrade(isCorrect: isCorrect, correctAnswer: correctAnswer)

        case .matching(let pairs):
            let correctAnswer = pairs.map { "\($0.lv) → \($0.tr)" }.joined(separator: ", ")
            guard case .pairs(let submitted) = answer, submitted.count == pairs.count else {
                return LatvianGrade(isCorrect: false, correctAnswer: correctAnswer)
            }
            var expected: [String: String] = [:]
            for pair in pairs { expected[normalize(pair.lv)] = normalize(pair.tr) }
            let isCorrect = submitted.allSatisfy { expected[normalize($0.lv)] == normalize($0.tr) }
            return LatvianGrade(isCorrect: isCorrect, correctAnswer: correctAnswer)

        case .typing(let accepted):
            let correctAnswer = accepted.first ?? ""
            guard case .text(let submitted) = answer else {
                return LatvianGrade(isCorrect: false, correctAnswer: correctAnswer)
            }
            let normalized = normalize(submitted)
            let isCorrect = accepted.contains { normalize($0) == normalized }
            return LatvianGrade(isCorrect: isCorrect, correctAnswer: correctAnswer)

        case .speaking(let target):
            guard case .spoken(let transcript) = answer else {
                return LatvianGrade(isCorrect: false, correctAnswer: target)
            }
            return LatvianGrade(isCorrect: normalize(transcript) == normalize(target), correctAnswer: target)
        }
    }
}
