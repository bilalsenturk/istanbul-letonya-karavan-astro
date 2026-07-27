import SwiftUI

/// Rota üzerindeki tek bir durak — bir sahnenin ekrandaki karşılığı.
///
/// Alanların hepsi **önceden hesaplanmış**: `LatvianLessonBuilder.masteryRatio`
/// sahne başına bütün kelimeleri geziyor ve gövde değerlendirmesi başına on iki
/// kez çağrılamaz. Hesap `LatvianCourseModel.refreshDerived` içinde bir kez
/// yapılıp buraya taşınıyor.
struct LatvianRouteStop: Identifiable, Equatable {
    let id: String
    let title: String
    /// Pakete göre 1'den başlayan sıra.
    let index: Int
    let isUnlocked: Bool
    /// Sahne bir kez geçildi mi (hakim olundu ya da daha önce tamamlandı).
    let isCleared: Bool
    /// 0-1: kelimelerinin kaçı hem tanıma hem üretim tarafında kalıcı öğrenildi.
    let masteryRatio: Double
}

/// İstanbul'dan Riga'ya uzanan yol üzerinde duraklar.
///
/// Duraklar dikey bir dalga boyunca diziliyor (`wave`) ve ardışık iki durak
/// eğik bir çubukla bağlanıyor. Dalga bilerek dar: 375 pt genişlikte en dıştaki
/// durak bile kenara değmiyor (durak 190 pt + 52 pt sapma = 294 < 335 pt
/// kullanılabilir genişlik).
struct LatvianRouteMap: View {
    let stops: [LatvianRouteStop]
    /// Öğrencinin şu an durduğu durak; maskot burada bekliyor.
    let currentStopId: String?
    let onSelect: (LatvianRouteStop) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Durakların merkeze göre yatay sapması (pt). Sekizlik desen tekrar ediyor.
    /// Genlik dar tutuldu: ardışık iki durak arasındaki en büyük yana kayma 26 pt,
    /// dolayısıyla bağlantı çubuğu 33 dereceden fazla eğilmiyor.
    private static let wave: [CGFloat] = [0, 26, 40, 26, 0, -26, -40, -26]
    private static let nodeWidth: CGFloat = 190
    private static let discSize: CGFloat = 62
    private static let ringSize: CGFloat = 72
    /// İki durak arasındaki dikey açıklık.
    private static let drop: CGFloat = 40

    var body: some View {
        VStack(spacing: 0) {
            if !stops.isEmpty {
                endpoint("İstanbul", symbol: "location.fill", tone: Theme.c1)
                connector(from: 0, to: offset(at: 0), isDrawn: false)
                ForEach(Array(stops.enumerated()), id: \.element.id) { position, stop in
                    node(stop, at: offset(at: position))
                    if position < stops.count - 1 {
                        connector(
                            from: offset(at: position),
                            to: offset(at: position + 1),
                            isDrawn: stop.isCleared
                        )
                    }
                }
                connector(
                    from: offset(at: stops.count - 1),
                    to: 0,
                    isDrawn: stops.last?.isCleared ?? false
                )
                endpoint("Rīga", symbol: "flag.checkered", tone: Theme.c4)
            }
        }
        // Genişliği doldurmak şart: doldurmayınca kaydırma görünümünün içeriği
        // 230 pt kalıyor ve `ScrollView` kaydırma çubuğunu içeriğin sağ kenarına,
        // yani ekranın ortasına çiziyordu.
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 20)
    }

    private func offset(at position: Int) -> CGFloat {
        Self.wave[((position % Self.wave.count) + Self.wave.count) % Self.wave.count]
    }

    // MARK: - Durak

    private func node(_ stop: LatvianRouteStop, at horizontal: CGFloat) -> some View {
        Button {
            onSelect(stop)
        } label: {
            VStack(spacing: 8) {
                disc(stop)
                    .overlay(alignment: .leading) {
                        if stop.id == currentStopId {
                            LatvianMascot(mood: .idle, size: 44)
                                .offset(x: -38)
                                .accessibilityHidden(true)
                        }
                    }
                Text(stop.title)
                    .font(.system(size: 14, weight: .heavy, design: .rounded))
                    .foregroundStyle(stop.isUnlocked ? Theme.text : Theme.muted)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
                Text(caption(stop))
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.muted)
            }
            .frame(width: Self.nodeWidth)
            .padding(.bottom, 4)
        }
        .buttonStyle(.plain)
        .offset(x: horizontal)
        .accessibilityLabel(accessibilityLabel(stop))
        .accessibilityHint(stop.isUnlocked ? "Bu durağın dersini başlatır." : "")
    }

    private func disc(_ stop: LatvianRouteStop) -> some View {
        ZStack {
            Circle()
                .fill(fill(stop))
                .frame(width: Self.discSize, height: Self.discSize)
                .overlay(Circle().strokeBorder(Theme.line, lineWidth: stop.isUnlocked ? 0 : 1))

            Circle()
                .stroke(Theme.line, lineWidth: 3.5)
                .frame(width: Self.ringSize, height: Self.ringSize)
            Circle()
                .trim(from: 0, to: min(max(stop.masteryRatio, 0), 1))
                .stroke(Theme.ok, style: StrokeStyle(lineWidth: 3.5, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .frame(width: Self.ringSize, height: Self.ringSize)
                .animation(motion(LatvianMotion.slide), value: stop.masteryRatio)

            emblem(stop)
        }
        .frame(width: Self.ringSize, height: Self.ringSize)
    }

    @ViewBuilder
    private func emblem(_ stop: LatvianRouteStop) -> some View {
        if !stop.isUnlocked {
            Image(systemName: "lock.fill")
                .font(.system(size: 19, weight: .bold))
                .foregroundStyle(Theme.muted)
        } else if stop.isCleared {
            Image(systemName: "checkmark")
                .font(.system(size: 23, weight: .black))
                .foregroundStyle(Theme.bg)
        } else {
            Text("\(stop.index)")
                .font(.system(size: 23, weight: .black, design: .rounded))
                .foregroundStyle(Theme.text)
        }
    }

    private func fill(_ stop: LatvianRouteStop) -> AnyShapeStyle {
        if !stop.isUnlocked { return AnyShapeStyle(Theme.panel) }
        return stop.isCleared ? AnyShapeStyle(Theme.ok) : AnyShapeStyle(Theme.gradWarm)
    }

    private func caption(_ stop: LatvianRouteStop) -> String {
        guard stop.isUnlocked else { return "Kilitli" }
        return "%\(Int((min(max(stop.masteryRatio, 0), 1) * 100).rounded())) öğrenildi"
    }

    private func accessibilityLabel(_ stop: LatvianRouteStop) -> String {
        let state = stop.isUnlocked ? (stop.isCleared ? "geçildi" : "açık") : "kilitli"
        return "\(stop.index). durak, \(stop.title), \(state), \(caption(stop))"
    }

    // MARK: - Yol

    /// İki durağı birleştiren eğik çubuk.
    ///
    /// Dikey bir kapsül döndürülüyor: SwiftUI'da y aşağı baktığı için pozitif
    /// dönüş saat yönünde, dolayısıyla (0, uzunluk) vektörü `-atan2(dx, dy)`
    /// kadar döndürüldüğünde alt ucu tam `dx` kadar yana kayıyor.
    ///
    /// Yerleşimdeki payı **döndürülmemiş** uzunluk kadar, `drop` kadar değil:
    /// `drop`'a kırpılınca eğik çubuğun uçları satır sınırlarını taşıyor ve
    /// üstteki durağın "%100 öğrenildi" satırını çiziyordu. Çizilen dikey
    /// açıklık yine `drop`; fazlalık boşluk olarak kalıyor.
    private func connector(from start: CGFloat, to end: CGFloat, isDrawn: Bool) -> some View {
        let dx = end - start
        let length = (dx * dx + Self.drop * Self.drop).squareRoot()
        return Capsule()
            .fill(isDrawn ? AnyShapeStyle(Theme.gradWarm) : AnyShapeStyle(Theme.line))
            .frame(width: 5, height: length)
            .rotationEffect(.radians(-atan2(Double(dx), Double(Self.drop))))
            .offset(x: (start + end) / 2)
            .animation(motion(LatvianMotion.slide), value: isDrawn)
            .accessibilityHidden(true)
    }

    private func endpoint(_ title: String, symbol: String, tone: Color) -> some View {
        HStack(spacing: 6) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(tone)
            Text(title)
                .font(.system(size: 12, weight: .heavy, design: .rounded))
                .foregroundStyle(Theme.dim)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(Theme.panel, in: Capsule())
        .overlay(Capsule().strokeBorder(Theme.line, lineWidth: 1))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
    }

    private func motion(_ base: Animation) -> Animation {
        LatvianMotion.adaptive(base, reduceMotion: reduceMotion)
    }
}

#Preview("Rota") {
    ScrollView {
        LatvianRouteMap(
            stops: (1...12).map { index in
                LatvianRouteStop(
                    id: "s\(index)",
                    title: index == 8 ? "Hava ve yol durumu" : "Durak \(index)",
                    index: index,
                    isUnlocked: index <= 4,
                    isCleared: index <= 2,
                    masteryRatio: index <= 2 ? 1 : (index == 3 ? 0.45 : 0)
                )
            },
            currentStopId: "s3",
            onSelect: { _ in }
        )
        .padding(.vertical, 24)
    }
    .background(Theme.bg)
}
