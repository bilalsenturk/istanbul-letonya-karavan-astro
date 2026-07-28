import SwiftUI

/// Cevaptan sonra alttan gelen panel.
///
/// Panelin tek çıkışı düğmesi: sonraki soruya başka hiçbir yoldan geçilmiyor.
/// Kaydırarak kapatma, dışına dokunma, geri hareketi — hiçbiri yok. Sebebi
/// görgü değil muhasebe: kuyruğu yalnızca `LatvianLessonSession.advance()`
/// ilerletiyor, paneli ondan bağımsız kapatan her yol kuyrukla ekranı ayırırdı.
///
/// Panel oturuma bakmıyor; gönderim anında dondurulmuş `LatvianAnswerReview`'ü
/// çiziyor.
///
/// ## Neden doğru cevapta da doğru cevap yazıyor
///
/// Panel eskiden yalnızca **yanlış** cevapta metin gösteriyordu; doğru cevap
/// veren öğrenci hiçbir şey öğrenmeden geçiyordu. Üç şikâyetin üçü de buradan
/// geliyordu: (1) Letonca sorulan şeyin Türkçesi hiç görünmüyordu, (2) yazarak
/// verilen cevabın telaffuzu duyulamıyordu, (3) `ludzu` yazıp doğru sayılan
/// öğrenci `lūdzu`'yu hiç görmüyordu. Üçü de tek bir kararla kapanıyor: cevap
/// bloğu her zaman çiziliyor.
///
/// ## Neden klip kendiliğinden çalmıyor
///
/// Panel açılırken `LatvianFeedback.correct()` zaten bir ses ve haptic
/// tetikliyor; üstüne bir klip bindirmek ikisini de bozardı ve aynı cevap için
/// iki kez çalmayı engelleyen bir kilit gerektirirdi. Düğme yeterli.
struct LatvianAnswerPanel: View {
    let isCorrect: Bool
    let correctAnswer: String
    /// Doğru cevabın Türkçesi. Cevabın kendisi zaten Türkçeyse (`lvToTr`) ya da
    /// Türkçeyi içeriyorsa (`match`) `nil` gelir.
    let glossTr: String?
    /// Doğru cevabı seslendiren klip; yoksa (ya da inmemişse) `nil` gelir ve
    /// düğme hiç çizilmez.
    let answerAudioId: String?
    @ObservedObject var audio: LatvianAudioStore
    @ObservedObject var feedback: LatvianFeedback
    /// Kombo eşiği geçildiyse üst üste doğru sayısı.
    ///
    /// Rozet başta üst şeritte yüzüyordu ve orada sorunun ilk kartının üstüne
    /// biniyordu (ekran görüntüsüyle yakalandı). Buraya taşındı: öğrencinin
    /// zaten baktığı yer burası, çarpışacak bir şey yok ve panelle birlikte
    /// gidip geldiği için ayrıca bir zamanlayıcı gerekmiyor.
    let comboMilestone: Int?
    /// Bu cevap dersi bitiriyorsa düğme "Bitir" der.
    let isLastQuestion: Bool
    let onContinue: () -> Void

    private var tint: Color { isCorrect ? Theme.ok : Theme.bad }

    private var title: String { isCorrect ? "Doğru!" : "Doğru cevap" }

    private var buttonTitle: String { isLastQuestion ? "Bitir" : "Devam" }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            answerBlock
            listenButton
            continueButton
        }
        .padding(.horizontal, 20)
        .padding(.top, 18)
        .padding(.bottom, 16)
        .frame(maxWidth: .infinity)
        .background { panelBackground }
        // Panel açılınca VoiceOver odağı buraya gelsin: doğru cevabı okumadan
        // "Devam"a basılmasın.
        .accessibilityElement(children: .contain)
        .accessibilitySortPriority(1)
    }

    // MARK: - Parçalar

    private var header: some View {
        HStack(spacing: 10) {
            HStack(spacing: 11) {
                Image(systemName: isCorrect ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .font(.system(size: 27, weight: .bold))
                    .foregroundStyle(tint)
                Text(title)
                    .font(.system(size: 21, weight: .heavy, design: .rounded))
                    .foregroundStyle(Theme.text)
            }
            .accessibilityElement(children: .ignore)
            // Doğru cevap artık hemen altında kendi öğesi olarak duruyor ve
            // kendi etiketiyle okunuyor; başlıkta tekrarlamak VoiceOver'da aynı
            // metni iki kez söyletirdi.
            .accessibilityLabel(isCorrect ? "Doğru cevap verdin" : "Yanlış cevap")
            .accessibilityAddTraits(.isHeader)

            Spacer(minLength: 0)
            comboBadge
        }
    }

    /// Doğru cevap ve altında Türkçesi. **Cevabın doğruluğuna bakmıyor**: panelin
    /// öğrettiği tek şey bu blok.
    ///
    /// Yükseklik ölçüsü (375 pt genişlik, 20 pt yan dolgu → 335 pt yazı alanı):
    /// paketteki en uzun cevap 133 karakterlik bir `match` dizisi ("… → …" dört
    /// çift), 19 pt yuvarlak kalınla ~5 satır, yani ~115 pt. En uzun `glossTr`
    /// 45 karakter, 15 pt ile tek satır. Paneldeki en yüksek hâl (başlık + cevap
    /// + Türkçe + iki düğme + dolgular) ~300 pt; 667 pt'lik ekranda üst şerit
    /// 66 pt olduğuna göre soru alanına 300 pt'den fazlası kalıyor ve o alan
    /// zaten kaydırılabilir. Yazı tipleri sabit punto olduğu için Dynamic Type
    /// bu hesabı büyütmüyor. Bu yüzden satır sınırı **yok**: kırpmak, cevabın bir
    /// kısmını gizlemek demek olurdu.
    @ViewBuilder
    private var answerBlock: some View {
        if !correctAnswer.isEmpty {
            Text(correctAnswer)
                .font(.system(size: 19, weight: .bold, design: .rounded))
                .foregroundStyle(Theme.text)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityLabel("Doğru cevap: \(correctAnswer)")
        }

        if let glossTr, !glossTr.isEmpty {
            Text(glossTr)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Theme.dim)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityLabel("Türkçesi: \(glossTr)")
        }
    }

    /// Cevabın telaffuzu. Ders ekranındaki soru düğmesiyle aynı bileşen:
    /// öğrencinin sorunun üstünde bastığı düğmenin aynısı burada da çıkıyor.
    @ViewBuilder
    private var listenButton: some View {
        if let answerAudioId {
            LatvianListenButton(
                audioId: answerAudioId, audio: audio, feedback: feedback,
                title: "Cevabı dinle"
            )
        }
    }

    @ViewBuilder
    private var comboBadge: some View {
        if let comboMilestone {
            VStack(spacing: 1) {
                Text("\(comboMilestone) üst üste")
                    .font(.system(size: 11, weight: .heavy, design: .rounded))
                Text("+\(LatvianLessonSession.comboBonusXP) XP")
                    .font(.system(size: 13, weight: .black, design: .rounded))
            }
            .foregroundStyle(Theme.c1)
            .padding(.horizontal, 11)
            .padding(.vertical, 6)
            .background(Theme.c1.opacity(0.16), in: Capsule())
            .overlay(Capsule().stroke(Theme.c1.opacity(0.45), lineWidth: 1))
            .fixedSize()
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(
                "\(comboMilestone) doğru üst üste, \(LatvianLessonSession.comboBonusXP) XP bonus"
            )
        }
    }

    private var continueButton: some View {
        Button(action: onContinue) {
            Text(buttonTitle)
                .font(.system(size: 17, weight: .heavy, design: .rounded))
                // Her iki dolgu da parlak; en yüksek kontrast koyu zemin rengi.
                .foregroundStyle(Theme.bg)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(tint, in: RoundedRectangle(cornerRadius: 15, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isLastQuestion ? "Dersi bitir" : "Sonraki soruya geç")
        .accessibilityAddTraits(.isButton)
    }

    /// Alt kenara yapışan zemin. `ignoresSafeArea` yalnızca **zeminde**: içerik
    /// güvenli alanda kalıyor, yani "Devam" düğmesi ana ekran çubuğunun altına
    /// kaçmıyor, ama renk ekranın dibine kadar iniyor.
    private var panelBackground: some View {
        UnevenRoundedRectangle(topLeadingRadius: 22, topTrailingRadius: 22, style: .continuous)
            .fill(tint.opacity(0.13))
            .overlay(alignment: .top) {
                Rectangle()
                    .fill(tint)
                    .frame(height: 2)
            }
            .clipShape(
                UnevenRoundedRectangle(topLeadingRadius: 22, topTrailingRadius: 22, style: .continuous)
            )
            .ignoresSafeArea(edges: .bottom)
    }
}

#Preview("Cevap paneli") {
    let audio = LatvianAudioStore()
    let feedback = LatvianFeedback()
    return VStack(spacing: 0) {
        Spacer()
        LatvianAnswerPanel(
            isCorrect: true, correctAnswer: "lūdzu", glossTr: "lütfen",
            answerAudioId: "lv-ludzu", audio: audio, feedback: feedback,
            comboMilestone: 5, isLastQuestion: false, onContinue: {}
        )
        LatvianAnswerPanel(
            isCorrect: false, correctAnswer: "ātrā palīdzība", glossTr: "ambulans",
            answerAudioId: nil, audio: audio, feedback: feedback,
            comboMilestone: nil, isLastQuestion: true, onContinue: {}
        )
    }
    .background(Theme.bg)
}
