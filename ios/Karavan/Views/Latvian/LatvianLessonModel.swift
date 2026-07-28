import Foundation

/// Bir dersin sonucu. Kabuk bunu `onFinish` ile **tam olarak bir kez** verir;
/// hafızaya (FSRS), XP'ye ve seriye yazmak çağıranın işi — `LatvianLessonSession`
/// gibi bu tip de diske dokunmuyor.
struct LatvianLessonOutcome {
    /// Tek bir gönderimin hafızaya yazılacak hâli.
    struct Answer {
        let wordId: String
        let modality: LatvianModality
        let rating: LatvianRating
    }

    let xp: Int
    let accuracy: Double
    let isFailed: Bool

    /// Öğrenci dersi yarıda bıraktı (üst şeritteki çarpı → onay).
    ///
    /// `isFailed`'den ayrı bir alan, çünkü ikisi aynı şey değil: can bitmesi
    /// dersin **sonucu**, yarıda bırakmak dersin **hiç sonuçlanmaması**. Verilen
    /// cevaplar yine hafızaya yazılıyor (bkz. `LatvianCourseModel.finish`), ama
    /// ne seri ilerliyor ne de kutlama açılıyor.
    let wasAbandoned: Bool

    /// Gönderim sırasıyla. Yanlış cevaplanan soru burada **iki kez** geçer
    /// (önce `again`, sonra doğrusu); `LatvianProgress.registerAnswer` sırayla
    /// çağrılmalı ki planlayıcı ikisini de görsün.
    let answers: [Answer]
}

/// Cevap panelinin çizdiği, **gönderim anında dondurulmuş** özet.
///
/// Panel oturuma bakmıyor: panel açıkken oturumun canı/kombosu değişmese de
/// dondurulmuş olması, "panel açıkken ekranda ne yazıyorsa gönderilen cevaba
/// aittir" garantisini tek bir yerde veriyor.
struct LatvianAnswerReview: Equatable {
    let result: LatvianSubmissionResult
    /// Doğru cevabın Türkçesi; cevap doğru da olsa gösteriliyor.
    let glossTr: String?
    /// Doğru cevabı seslendiren klip — panelin "Cevabı dinle" düğmesi.
    /// Soruyu üreten motor yalnızca inmiş klipleri buraya yazıyor.
    let answerAudioId: String?
    /// Bu cevap dersi bitiriyor mu — panelin düğmesi "Bitir" mi "Devam" mı diyecek.
    let isFinal: Bool
}

/// `LatvianLessonSession` ile ekran arasındaki tek kapı.
///
/// Oturum `SwiftUI` bilmeyen düz bir sınıf; `@State` içinde tutulsaydı
/// mutasyonları hiçbir yayın üretmez, ekran yalnızca yanındaki başka bir
/// `@State` değiştiği için tesadüfen tazelenirdi. Buradaki `@Published`
/// aynalar o tesadüfü sözleşmeye çeviriyor.
///
/// ## Neden kural oturumda değil de burada tekrar var
///
/// Oturum kendini zaten savunuyor (ikinci `submit` yeniden notlamıyor, boşa
/// `advance` bir şey yapmıyor). Ama **görünümün kendi defteri** oturumun
/// içinde değil: `answers` listesi ve `onFinish`. Brifingdeki taslak
/// `session.submit`'ten dönen sonucu koşulsuz `answers`'a ekliyordu — hızlı iki
/// dokunuşta oturum tek cevap sayarken defter iki kayıt tutuyor, yani FSRS aynı
/// kelimeye iki kez yazıyordu. Bu yüzden gönderim burada da kapıda duruyor.
///
/// Ana kuyrukta çalışır (görünüm dışında kullanıcısı yok); `@MainActor`
/// işaretlenmedi çünkü `View.init` yalıtımsız ve oradan kuruluyor.
final class LatvianLessonModel: ObservableObject {

    /// Ekranda olması gereken soru.
    @Published private(set) var current: LatvianExercise?

    /// Soru görünümünün kimliği. **Soru kimliği kullanılamaz:** son soru yanlış
    /// cevaplanınca kuyruk `[A]` → `[A]` olur, kimlik değişmez, `SwiftUI` aynı
    /// görünümü korur ve öğrencinin yanlış seçimi ekranda seçili kalır. Her
    /// gösterim ayrı bir sayı alıyor, böylece giden sorudan gelen soruya durum
    /// sızamıyor.
    @Published private(set) var presentationIndex = 0

    @Published private(set) var progress: Double = 0
    @Published private(set) var heartsLeft: Int
    @Published private(set) var comboCount = 0

    /// Açık cevap paneli. `nil` ise öğrenci cevap veriyor.
    @Published private(set) var review: LatvianAnswerReview?

    /// Ders bitti (ya da can bitti) ve sonuç verildi. Panel bilerek açık
    /// bırakılıyor: kapatmak, çağıran ekranı değiştirene kadar bir kare boyunca
    /// canlı bir soru gösterirdi.
    @Published private(set) var isOver = false

    private let session: LatvianLessonSession
    private var answers: [LatvianLessonOutcome.Answer] = []

    init(exercises: [LatvianExercise]) {
        session = LatvianLessonSession(exercises: exercises)
        heartsLeft = session.heartsLeft
        sync()
    }

    /// Soru verilmeden açılan ders. Çağıran boş liste geçerse ekran sonsuza
    /// kadar boş kalırdı; burada anında sonuç dönüyor.
    func finishIfEmpty() -> LatvianLessonOutcome? {
        guard !isOver, review == nil, session.current == nil else { return nil }
        isOver = true
        return makeOutcome(wasAbandoned: false)
    }

    /// Öğrenci dersi yarıda bıraktı. Sonuç **o ana kadarki** defterle dönüyor:
    /// verilen cevaplar duruyor, kaybedilen canlar geri gelmiyor.
    ///
    /// Bilerek `review == nil` koşulu **yok**: cevap paneli açıkken de çıkılabilir
    /// ve o cevap zaten `submit`'te deftere yazıldı. Panel açıkken çıkışı
    /// engellemek, kullanıcının sıkıştığı yerlerden birini olduğu gibi bırakırdı.
    ///
    /// - Returns: Çağıranın işlemesi gereken sonuç; ders zaten bitmişse `nil`
    ///   (ikinci dokunuş sonucu bir daha döndürmez).
    func abandon() -> LatvianLessonOutcome? {
        guard !isOver else { return nil }
        isOver = true
        return makeOutcome(wasAbandoned: true)
    }

    /// Cevabı notlatır.
    ///
    /// - Returns: Panelin çizeceği özet; gönderim kabul edilmediyse (panel zaten
    ///   açık, ders bitmiş, can bitmiş) `nil` — çağıran o durumda ses çalmamalı,
    ///   deftere yazmamalı.
    func submit(_ answer: LatvianAnswer, elapsed: TimeInterval) -> LatvianAnswerReview? {
        guard !isOver, review == nil, !session.isFailed, let exercise = session.current else { return nil }

        let result = session.submit(answer, elapsed: elapsed, usedHint: false)
        answers.append(
            LatvianLessonOutcome.Answer(
                wordId: exercise.targetWordId, modality: exercise.modality, rating: result.rating
            )
        )

        // Can bittiyse ders başarısız; doğru cevaplanan **son** soru kuyruğu
        // boşaltacak. İkisi de bu cevabın dersi bitirdiği anlamına geliyor.
        let isFinal = session.isFailed || (session.remainingCount == 1 && result.grade.isCorrect)
        // Soru buradan dışarı sızmıyor: panel yalnızca bu dondurulmuş özeti
        // görüyor, iki yeni alan da gönderim anında sorudan kopyalanıyor.
        let value = LatvianAnswerReview(
            result: result,
            glossTr: exercise.answerGlossTr,
            answerAudioId: exercise.answerAudioId,
            isFinal: isFinal
        )
        review = value
        sync()
        return value
    }

    /// Cevap paneli kapandığında: dersin normal çıkışı. `isOver` bayrağı
    /// sayesinde sonuç buradan da, `abandon()`'dan da **toplamda bir kez**
    /// dönüyor.
    ///
    /// - Returns: Ders bittiyse sonuç, bitmediyse `nil`.
    func advance() -> LatvianLessonOutcome? {
        guard !isOver, review != nil else { return nil }

        // Başarısız derste oturum donuk: `advance()` bilerek hiçbir şey yapmaz.
        session.advance()

        if session.isFinished || session.isFailed {
            isOver = true
            return makeOutcome(wasAbandoned: false)
        }

        review = nil
        presentationIndex += 1
        sync()
        return nil
    }

    /// `LatvianLessonOutcome`'ın tek kurulduğu yer; `wasAbandoned` bilerek
    /// varsayılansız, çünkü hangi çıkıştan gelindiği her çağrı yerinde okunmalı.
    private func makeOutcome(wasAbandoned: Bool) -> LatvianLessonOutcome {
        LatvianLessonOutcome(
            xp: session.xpEarned,
            accuracy: session.accuracy,
            isFailed: session.isFailed,
            wasAbandoned: wasAbandoned,
            answers: answers
        )
    }

    private func sync() {
        current = session.current
        progress = session.progress
        heartsLeft = session.heartsLeft
        comboCount = session.comboCount
    }
}
