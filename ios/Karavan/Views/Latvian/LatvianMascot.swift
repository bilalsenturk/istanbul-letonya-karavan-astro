import SwiftUI

/// Maskotun ruh hali. Sonraki görevler yalnızca bu arayüze bağlı; çizimin
/// kendisi serbestçe değişebilir.
enum LatvianMascotMood: String, Hashable, CaseIterable {
    case idle
    case thinking
    case correct
    case wrong
    case celebrate
}

/// **Vaşak** — Kuzey'in yol arkadaşı.
///
/// Neden vaşak: hem Toros dağlarının hem Letonya ormanlarının hayvanı, yani
/// İstanbul–Riga yolunun iki ucunda da yaşıyor. Boynundaki atkı onu "orman
/// hayvanı" değil "yolcu" yapıyor.
///
/// Tamamı SwiftUI şekli; harici varlık, PNG veya animasyon dosyası yok.
///
/// ## Küçükte de okunsun diye
///
/// Maskot rota haritasında 38pt, ders bitiş ekranında 132pt görünüyor. Bu
/// yüzden:
/// - Gövde yok, yalnızca büyük bir kafa: 38pt'de gövde çizgiye dönüşürdü.
/// - Siluet üç parçadan kuruluyor (sivri kulaklar + yuvarlak kafa + turkuaz
///   atkı); üçü de 38pt'de ayırt edilebilecek kadar büyük.
/// - Yüz koyu (`Theme.bg`), kafa sıcak degrade: en yüksek kontrast.
/// - `isCompact` (56pt altı) ışıltıları ve dili gizler — o boyutta piksel
///   çöpüne dönüşüyorlar.
///
/// ## Hareket
///
/// - Nefes ve göz kırpma yalnızca `.task(id:)` içindeki tek bir döngüden gelir.
///   `Timer.scheduledTimer` bilerek kullanılmadı: run loop zamanlayıcıyı
///   tutuyor, görünüm kaybolunca durmuyor ve ekran ikinci kez açıldığında
///   ikinci bir zamanlayıcı daha kuruluyor.
/// - Nefes ölçeği, ruh hali animasyonunun **dışında** bir katmanda duruyor;
///   aynı `scaleEffect` üzerinde `repeatForever` ile `spring` karışırsa ölçek
///   takılı kalıyor.
/// - Ruh hali geçişleri kesilebilir: hızlı cevap veren biri animasyon
///   ortasında ruh halini değiştirir, `.animation(_:value:)` yayı yeniden
///   hedefler.
/// - Reduce Motion açıkken nefes ve kırpma durur, ruh hali geçişi sıçramasız
///   kısa bir `easeOut`'a döner — ama kaybolmaz.
struct LatvianMascot: View {
    let mood: LatvianMascotMood
    var size: CGFloat = 88

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var breathing = false
    @State private var blinking = false

    /// Bu boyutun altında ince süsler çizilmez.
    private var isCompact: Bool { size < 56 }

    /// Oran → punto.
    private func u(_ fraction: CGFloat) -> CGFloat { size * fraction }

    /// Çizgi kalınlığı hiçbir boyutta saç teline dönmesin.
    private var stroke: CGFloat { max(u(0.05), 1.5) }

    var body: some View {
        ZStack {
            if !isCompact { sparkles }
            ears
            head
            scarf
            face
        }
        .frame(width: size, height: size)
        .scaleEffect(moodScale)
        .rotationEffect(.degrees(tilt))
        .offset(y: bounce)
        .animation(LatvianMotion.adaptive(LatvianMotion.pop, reduceMotion: reduceMotion), value: mood)
        // Nefes, ruh hali animasyonunun dışında: iki animasyon aynı ölçeğe
        // binerse `repeatForever` yayı yutuyor.
        .scaleEffect(breathing ? 1.025 : 1.0)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
        .task(id: reduceMotion) { await runIdleLoop() }
    }

    // MARK: - Parçalar

    private var head: some View {
        RoundedRectangle(cornerRadius: u(0.28), style: .continuous)
            .fill(Theme.gradWarm)
            .frame(width: u(0.68), height: u(0.60))
            .overlay(
                // Alın ışığı — düz degradeye hacim katıyor.
                Ellipse()
                    .fill(Theme.text.opacity(0.13))
                    .frame(width: u(0.34), height: u(0.15))
                    .offset(y: -u(0.19))
            )
            .offset(y: -u(0.04))
    }

    private var ears: some View {
        ZStack {
            ear.rotationEffect(.degrees(-earAngles.left), anchor: .bottom)
                .offset(x: -u(0.19), y: -u(0.385))
            ear.rotationEffect(.degrees(earAngles.right), anchor: .bottom)
                .offset(x: u(0.19), y: -u(0.385))
        }
    }

    private var ear: some View {
        LatvianEarShape()
            .fill(Theme.c1)
            .frame(width: u(0.20), height: u(0.21))
            .overlay(
                LatvianEarShape()
                    .fill(Theme.c2)
                    .frame(width: u(0.10), height: u(0.105))
                    .offset(y: u(0.042))
            )
    }

    /// Boyun fuları — maskotu "orman hayvanı" değil "yolcu" yapan parça.
    ///
    /// Yatay bir bant denendi ve çalışmadı: yuvarlak kafada boyun olmadığı için
    /// bant çenenin altında havada duran bir kütüğe benziyor. Çeneyi saran ve
    /// aşağı doğru sivrilen üçgen fular hem düğümüyle okunuyor hem de 38pt'de
    /// tek bir turkuaz üçgen olarak siluete giriyor.
    private var scarf: some View {
        ZStack {
            LatvianScarfShape()
                .fill(Theme.gradCool)
                .frame(width: u(0.60), height: u(0.26))
                .offset(y: u(0.285))

            // Düğüm — fuların çeneye tutunduğu nokta. Üçgenin orta noktadaki üst
            // kenarı 0.20'de; düğüm bunun biraz üstüne taşarak bağlanmış görünüyor.
            // Daha yukarısı kutlama ağzının diline değiyor.
            Capsule(style: .continuous)
                .fill(Theme.c4)
                .frame(width: u(0.15), height: u(0.10))
                .offset(y: u(0.22))
        }
        .rotationEffect(.degrees(scarfAngle), anchor: .top)
    }

    private var face: some View {
        ZStack {
            // Ağız bölgesi — burun ve ağzın oturduğu açık alan. Sıcak degradenin
            // üstünde okunması için saydamlık yüksek tutuldu.
            Ellipse()
                .fill(Theme.text.opacity(0.34))
                .frame(width: u(0.34), height: u(0.20))
                .offset(y: u(0.02))

            eyes
            nose
            mouth
        }
    }

    private var eyes: some View {
        HStack(spacing: u(0.13)) {
            eye
            eye
        }
        .offset(x: eyeShift, y: -u(0.14))
    }

    private var eye: some View {
        Group {
            if mood == .correct || mood == .celebrate {
                // Gülen göz: yukarı bakan yay.
                LatvianCurveShape()
                    .stroke(Theme.bg, style: StrokeStyle(lineWidth: stroke, lineCap: .round))
                    .rotationEffect(.degrees(180))
                    .frame(width: u(0.15), height: u(0.075))
            } else {
                Capsule(style: .continuous)
                    .fill(Theme.bg)
                    .frame(width: u(0.10), height: u(0.14))
                    // Kırpma ölçekle yapılıyor; yükseklik değişseydi yerleşim
                    // her karede yeniden hesaplanır, ağız yukarı aşağı oynardı.
                    .scaleEffect(x: 1, y: blinking ? 0.12 : 1, anchor: .center)
            }
        }
        .frame(width: u(0.15), height: u(0.14))
    }

    private var nose: some View {
        LatvianNoseShape()
            .fill(Theme.bg)
            .frame(width: u(0.08), height: u(0.055))
            .offset(y: -u(0.035))
    }

    private var mouth: some View {
        Group {
            switch mood {
            case .idle:
                LatvianCurveShape()
                    .stroke(Theme.bg, style: StrokeStyle(lineWidth: stroke, lineCap: .round))
                    .frame(width: u(0.15), height: u(0.045))
            case .thinking:
                // Eğik düz çizgi: düz yatay çizgi "eksik diş" gibi okunuyordu.
                Capsule()
                    .fill(Theme.bg)
                    .frame(width: u(0.12), height: stroke)
                    .rotationEffect(.degrees(-14))
            case .correct:
                LatvianCurveShape()
                    .stroke(Theme.bg, style: StrokeStyle(lineWidth: stroke, lineCap: .round))
                    .frame(width: u(0.21), height: u(0.085))
            case .wrong:
                LatvianCurveShape()
                    .stroke(Theme.bg, style: StrokeStyle(lineWidth: stroke, lineCap: .round))
                    .rotationEffect(.degrees(180))
                    .frame(width: u(0.17), height: u(0.06))
            case .celebrate:
                ZStack {
                    LatvianCurveShape(closed: true)
                        .fill(Theme.bg)
                        .frame(width: u(0.21), height: u(0.115))
                    if !isCompact {
                        Capsule()
                            .fill(Theme.c2)
                            .frame(width: u(0.095), height: u(0.045))
                            .offset(y: u(0.038))
                    }
                }
            }
        }
        .frame(width: u(0.22), height: u(0.12))
        .offset(y: u(0.07))
    }

    /// Kutlamada kafanın çevresine dağılan ışıltılar.
    ///
    /// Kaldırılmış pençeler de denendi; gövdesi olmayan bir maskotta kafanın
    /// iki yanına konan daireler pençe değil düğme gibi okunuyor. Kutlamayı
    /// açık ağız + gülen göz + sıçrama + ışıltılar zaten yeterince anlatıyor.
    private var sparkles: some View {
        Group {
            if mood == .celebrate {
                ZStack {
                    sparkle(u(0.10)).offset(x: -u(0.40), y: -u(0.20))
                    sparkle(u(0.085)).offset(x: u(0.41), y: -u(0.26))
                    sparkle(u(0.065)).offset(x: -u(0.30), y: -u(0.42))
                    sparkle(u(0.07)).offset(x: u(0.38), y: u(0.12))
                }
                .transition(reduceMotion ? .opacity : .scale(scale: 0.4).combined(with: .opacity))
            }
        }
    }

    private func sparkle(_ side: CGFloat) -> some View {
        LatvianSparkleShape()
            .fill(Theme.warn)
            .frame(width: side, height: side)
    }

    // MARK: - Ruh haline bağlı dönüşümler

    /// Reduce Motion açıkken ölçek oynaması dörtte bire iniyor: ruh hali zaten
    /// yüzden okunuyor, büyüyüp küçülmeye gerek yok.
    private var moodScale: CGFloat {
        let full: CGFloat
        switch mood {
        case .celebrate: full = 1.10
        case .correct: full = 1.05
        case .wrong: full = 0.97
        case .idle, .thinking: full = 1.0
        }
        return reduceMotion ? 1 + (full - 1) * 0.25 : full
    }

    private var tilt: Double {
        switch mood {
        case .thinking: return -9
        case .wrong: return 7
        case .idle, .correct, .celebrate: return 0
        }
    }

    /// Reduce Motion açıkken sıçrama tamamen kapalı: yer değiştiren nesne tam da
    /// bu ayarın kapatmak istediği şey. Yüz ifadesi, kulaklar ve eğim durduğu
    /// için ruh hali yine anlaşılıyor.
    private var bounce: CGFloat {
        guard !reduceMotion else { return 0 }
        switch mood {
        case .correct: return -u(0.07)
        case .celebrate: return -u(0.12)
        case .wrong: return u(0.02)
        case .idle, .thinking: return 0
        }
    }

    /// Kulaklar dışa doğru açılır. Düşünürken asimetrik — tek kulak dikilmiş.
    private var earAngles: (left: Double, right: Double) {
        switch mood {
        case .idle: return (8, 8)
        case .thinking: return (22, 2)
        case .correct: return (0, 0)
        case .wrong: return (42, 42)
        case .celebrate: return (-10, -10)
        }
    }

    /// Fuların savrulması. Küçük tutuluyor: büyük açı üst kenarı çeneden
    /// kaldırıp sarılmışlık izlenimini bozuyor.
    private var scarfAngle: Double {
        switch mood {
        case .celebrate: return -5
        case .correct: return -3
        case .wrong: return 4
        case .idle, .thinking: return 0
        }
    }

    /// Düşünürken gözler yana kayıyor.
    private var eyeShift: CGFloat {
        mood == .thinking ? u(0.03) : 0
    }

    private var accessibilityText: String {
        switch mood {
        case .idle: return "Yol arkadaşın vaşak bekliyor"
        case .thinking: return "Yol arkadaşın vaşak düşünüyor"
        case .correct: return "Yol arkadaşın vaşak seviniyor"
        case .wrong: return "Yol arkadaşın vaşak üzgün"
        case .celebrate: return "Yol arkadaşın vaşak kutluyor"
        }
    }

    // MARK: - Boştaki döngü

    private static let breathPeriod: TimeInterval = 1.8
    private static let blinkClose: TimeInterval = 0.07
    private static let blinkHold: TimeInterval = 0.10
    private static let blinkOpen: TimeInterval = 0.09

    /// `.task(id: reduceMotion)` çağırıyor: görünüm kaybolunca iptal olur,
    /// ikinci kez göründüğünde tek bir döngü daha başlar, Reduce Motion
    /// değişince yeniden değerlendirilir.
    @MainActor
    private func runIdleLoop() async {
        guard !reduceMotion else {
            // Hareket kapalıysa maskot canlı ama sabit; kırpma açık gözle biter.
            breathing = false
            blinking = false
            return
        }

        withAnimation(.easeInOut(duration: Self.breathPeriod).repeatForever(autoreverses: true)) {
            breathing = true
        }

        while !Task.isCancelled {
            // Düzenli aralık mekanik görünüyor; biraz dağıtmak canlı yapıyor.
            do {
                try await Task.sleep(for: .seconds(Double.random(in: 3.2...5.6)))
            } catch {
                break
            }
            withAnimation(.linear(duration: Self.blinkClose)) { blinking = true }
            do {
                try await Task.sleep(for: .seconds(Self.blinkClose + Self.blinkHold))
            } catch {
                break
            }
            withAnimation(.linear(duration: Self.blinkOpen)) { blinking = false }
        }

        // İptalde göz kapalı kalmasın; nefes de dursun ki bir sonraki
        // görünüşte `repeatForever` sıfırdan kurulsun.
        blinking = false
        breathing = false
    }
}

// MARK: - Şekiller

/// Aşağı doğru şişen yay: gülümseme. 180° çevrilince gülen göz / asık ağız.
/// `closed` doldurulabilir hale getirir (açık ağız).
private struct LatvianCurveShape: Shape {
    var closed = false

    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX, y: rect.minY),
            control: CGPoint(x: rect.midX, y: rect.minY + rect.height * 2)
        )
        if closed { path.closeSubpath() }
        return path
    }
}

/// Boyun fuları: üst kenarı çeneyi saracak biçimde aşağı kavisli, ucu sağa
/// kaçık bir üçgen.
private struct LatvianScarfShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let apex = CGPoint(x: rect.midX + rect.width * 0.07, y: rect.maxY)
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX, y: rect.minY),
            control: CGPoint(x: rect.midX, y: rect.minY + rect.height * 0.36)
        )
        path.addQuadCurve(
            to: apex,
            control: CGPoint(x: rect.maxX - rect.width * 0.11, y: rect.midY)
        )
        path.addQuadCurve(
            to: CGPoint(x: rect.minX, y: rect.minY),
            control: CGPoint(x: rect.minX + rect.width * 0.11, y: rect.midY)
        )
        path.closeSubpath()
        return path
    }
}

/// Vaşak kulağı: kenarları hafif içbükey, sivri üçgen.
private struct LatvianEarShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.addQuadCurve(
            to: CGPoint(x: rect.midX, y: rect.minY),
            control: CGPoint(x: rect.minX + rect.width * 0.17, y: rect.midY)
        )
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX, y: rect.maxY),
            control: CGPoint(x: rect.maxX - rect.width * 0.17, y: rect.midY)
        )
        path.closeSubpath()
        return path
    }
}

/// Yuvarlatılmış köşeli, aşağı bakan üçgen burun.
private struct LatvianNoseShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let inset = rect.width * 0.18
        path.move(to: CGPoint(x: rect.minX, y: rect.minY + inset))
        path.addQuadCurve(
            to: CGPoint(x: rect.minX + inset, y: rect.minY),
            control: CGPoint(x: rect.minX, y: rect.minY)
        )
        path.addLine(to: CGPoint(x: rect.maxX - inset, y: rect.minY))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX, y: rect.minY + inset),
            control: CGPoint(x: rect.maxX, y: rect.minY)
        )
        path.addQuadCurve(
            to: CGPoint(x: rect.midX, y: rect.maxY),
            control: CGPoint(x: rect.maxX - inset, y: rect.maxY - inset)
        )
        path.addQuadCurve(
            to: CGPoint(x: rect.minX, y: rect.minY + inset),
            control: CGPoint(x: rect.minX + inset, y: rect.maxY - inset)
        )
        path.closeSubpath()
        return path
    }
}

/// Dört uçlu ışıltı.
private struct LatvianSparkleShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let rx = rect.width / 2
        let ry = rect.height / 2
        let pull: CGFloat = 0.26   // uçları inceltir

        path.move(to: CGPoint(x: center.x, y: center.y - ry))
        path.addQuadCurve(
            to: CGPoint(x: center.x + rx, y: center.y),
            control: CGPoint(x: center.x + rx * pull, y: center.y - ry * pull)
        )
        path.addQuadCurve(
            to: CGPoint(x: center.x, y: center.y + ry),
            control: CGPoint(x: center.x + rx * pull, y: center.y + ry * pull)
        )
        path.addQuadCurve(
            to: CGPoint(x: center.x - rx, y: center.y),
            control: CGPoint(x: center.x - rx * pull, y: center.y + ry * pull)
        )
        path.addQuadCurve(
            to: CGPoint(x: center.x, y: center.y - ry),
            control: CGPoint(x: center.x - rx * pull, y: center.y - ry * pull)
        )
        path.closeSubpath()
        return path
    }
}

#Preview("Maskot — beş ruh hali") {
    VStack(spacing: 26) {
        ForEach(LatvianMascotMood.allCases, id: \.self) { mood in
            HStack(spacing: 34) {
                LatvianMascot(mood: mood, size: 38)
                LatvianMascot(mood: mood, size: 88)
                Text(mood.rawValue)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(Theme.muted)
            }
        }
    }
    .padding(40)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(Theme.bg)
}
