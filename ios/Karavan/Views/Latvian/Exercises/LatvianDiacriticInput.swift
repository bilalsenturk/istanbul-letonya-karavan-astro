import SwiftUI

/// Letonca yazılan her alanın yanında duran iki parça: alanın **üstünde** duran
/// güvence notu ve klavyenin üstüne oturan harf şeridi.
///
/// ## Neden ortak bir bileşen
///
/// Şikâyet aynen şuydu: *"benden letonca bir şey yazmamı istiyor. ama alfabe
/// yok."* Notlayıcı (`LatvianGrader.normalize`) diakritikleri zaten katlıyor,
/// yani `ludzu` yazan öğrenci `lūdzu` yazmış sayılıyor — ama bunu ekranda kimse
/// söylemiyordu. Üstelik hedef kelime tam diakritikle yukarıda duruyordu;
/// okunuşu "bunu birebir yazmam gerekiyor, yazamıyorum" oluyordu.
///
/// Şerit ve not `LatvianTypingExerciseView` içinde yaşıyordu, dolayısıyla
/// `LatvianSpeakExerciseView`'ün yazarak gönderme alanı ikisinden de yoksundu.
/// Kural artık dosya başına duruyor, ekran başına değil: **Letonca isteyen her
/// alan bu bileşeni de çiziyor.** Yeni bir alan eklendiğinde unutulacak şey tek
/// bir satır.
///
/// ## Yerleşim
///
/// Not alanın üstünde. Altındayken 375×667'lik bir ekranda klavye açıkken
/// kaydırılabilir alanın dışında kalıyordu; öğrenci onu ancak yanlış cevap
/// verdikten sonra, klavye kapanınca görebiliyordu — yani tam da geç kalmış
/// olarak. Üstte, odaklanan alan görünür olduğu sürece o da görünür.
///
/// Şerit klavye çubuğunda (`ToolbarItemGroup(placement: .keyboard)`), yani
/// öğrencinin eli zaten oradayken parmağının hemen üstünde. Aynı anda ekranda
/// tek bir soru görünümü olduğu için iki klavye çubuğu çakışmıyor.
///
/// Şerit metnin **sonuna** ekliyor: SwiftUI `TextField`'ı imleç konumunu dışarı
/// vermiyor. Soldan sağa yazarken imleç zaten sonda oluyor, dolayısıyla pratikte
/// fark eden bir durum değil.
struct LatvianDiacriticInput: View {
    /// Şeridin harf eklediği metin — alanın kendi bağlantısı.
    @Binding var text: String
    @ObservedObject var feedback: LatvianFeedback

    /// Letoncanın Türkçe klavyede bulunmayan harfleri.
    private static let diacritics = ["ā", "č", "ē", "ģ", "ī", "ķ", "ļ", "ņ", "š", "ū", "ž"]

    /// Notun söylediği şey notlayıcının yaptığı şey: `normalize` diakritikleri
    /// katlıyor, dolayısıyla `ludzu` gerçekten de `lūdzu` kadar doğru. Söz
    /// verilenden fazlası da yok — `ž` yerine `j` yazmak hâlâ yanlış, çünkü o
    /// diakritik değil başka bir harf.
    static let noticeText =
        "Klavyende Letonca harfler yoksa düz yaz — \"ludzu\" da \"lūdzu\" kadar doğru."
        + " Harfleri klavyenin üstündeki şeritten de seçebilirsin."

    var body: some View {
        Text(Self.noticeText)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(Theme.dim)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    letterStrip
                }
            }
    }

    // MARK: - Harf şeridi

    /// On bir harf, 375 pt'lik ekrana kaydırmadan sığacak ölçüde.
    ///
    /// İlk denemede tuşlar 34 pt genişti ve son üçü (š ū ž) ekran dışında
    /// kalıyordu — kimse orada kaydırılacak bir şey olduğunu tahmin edemezdi.
    /// `maxWidth: .infinity` ile eşit paylaştırmak ise klavye çubuğunda
    /// çalışmıyor: `ToolbarItemGroup` genişlik teklif etmediği için şerit tek
    /// bir yumruya çöküyordu. Sabit ölçü + kaydırma, ikisinin de olmadığı hâl.
    private var letterStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 3) {
                ForEach(Self.diacritics, id: \.self) { letter in
                    Button {
                        feedback.tap()
                        text.append(letter)
                    } label: {
                        Text(letter)
                            .font(.system(size: 18, weight: .bold, design: .rounded))
                            .foregroundStyle(Theme.text)
                            .frame(width: 28, height: 40)
                            .background(Theme.panel, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .stroke(Theme.line, lineWidth: 1)
                            )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(letter) harfini ekle")
                }
            }
            .padding(.horizontal, 2)
        }
    }
}
