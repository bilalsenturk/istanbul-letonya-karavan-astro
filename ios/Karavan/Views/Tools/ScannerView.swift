import SwiftUI
import VisionKit

// Kamera metin tarayıcı (VisionKit DataScanner) — iki mod:
// • .expense: pompa/fiş üzerindeki tutarları yakala → tek dokunuşla masraf ekle
// • .text:    tabela/menü metnini topla → paylaş sayfasındaki sistem "Çevir" ile çevir
// Simülatörde kamera yoktur; desteklenmiyorsa açıklayıcı boş durum gösterilir.
struct ScannerView: View {
    enum Mode { case expense, text }
    let mode: Mode
    var onAmount: ((Double, String) -> Void)? = nil   // (tutar, ipucu notu)

    @Environment(\.dismiss) private var dismiss
    @State private var recognized: [String] = []
    @State private var scanFailed = false

    private var supported: Bool {
        DataScannerViewController.isSupported && DataScannerViewController.isAvailable
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.bg.ignoresSafeArea()
                if supported {
                    VStack(spacing: 0) {
                        if scanFailed {
                            // startScanning fırlattı (izin reddi vb.) — ölü panelde bırakma.
                            VStack(spacing: 12) {
                                Image(systemName: "camera.fill")
                                    .font(.system(size: 40))
                                    .foregroundStyle(Theme.muted)
                                Text("Kamera başlatılamadı.\nAyarlar'dan kamera iznini açıp tekrar dene.")
                                    .font(.system(size: 14))
                                    .foregroundStyle(Theme.dim)
                                    .multilineTextAlignment(.center)
                            }
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .padding(24)
                        } else {
                            DataScannerRepresentable(onFailure: { scanFailed = true }) { texts in
                                recognized = texts
                            }
                            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                            .padding(12)
                        }
                        bottomPanel
                    }
                } else {
                    VStack(spacing: 12) {
                        Image(systemName: "camera.on.rectangle")
                            .font(.system(size: 40))
                            .foregroundStyle(Theme.muted)
                        Text("Kamera taraması bu cihazda kullanılamıyor.\n(Simülatörde kamera yoktur — gerçek iPhone'da çalışır.)")
                            .font(.system(size: 14))
                            .foregroundStyle(Theme.dim)
                            .multilineTextAlignment(.center)
                    }
                    .padding(24)
                }
            }
            .navigationTitle(mode == .expense ? "Tutar Tara" : "Metin Tara & Çevir")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Kapat") { dismiss() }.tint(Theme.muted)
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    // MARK: - Alt panel

    @ViewBuilder private var bottomPanel: some View {
        switch mode {
        case .expense:
            let amounts = Self.parseAmounts(from: recognized)
            VStack(alignment: .leading, spacing: 10) {
                MonoLabel(text: amounts.isEmpty ? "Kamerayı tutara doğrult…" : "Okunan tutarlar — dokun, ekle", color: Theme.c1)
                if !amounts.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(amounts, id: \.self) { value in
                                Button {
                                    // Önce tutarı ilet, sonra kapat — üst view
                                    // sonraki sheet'i kapanış bitince açar (onDismiss).
                                    onAmount?(value, Self.fuelHint(in: recognized) ? "Yakıt (taramadan)" : "Taramadan")
                                    dismiss()
                                } label: {
                                    Text("€\(value, specifier: value.truncatingRemainder(dividingBy: 1) == 0 ? "%.0f" : "%.2f")")
                                        .font(.system(size: 17, weight: .heavy, design: .rounded))
                                        .foregroundStyle(.black.opacity(0.85))
                                        .padding(.horizontal, 16).padding(.vertical, 10)
                                        .background(Theme.c1, in: Capsule())
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
            }
            .padding(14)
        case .text:
            let text = recognized.joined(separator: "\n")
            VStack(alignment: .leading, spacing: 10) {
                MonoLabel(text: recognized.isEmpty ? "Kamerayı metne doğrult…" : "Okunan metin", color: Theme.c4)
                if !text.isEmpty {
                    ScrollView {
                        Text(text)
                            .font(.system(size: 13))
                            .foregroundStyle(Theme.dim)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(maxHeight: 110)
                    // Paylaş sayfasında sistemin "Çevir" eylemi ile anında çeviri.
                    ShareLink(item: text) {
                        Label("Paylaş → Çevir", systemImage: "character.book.closed.fill")
                            .font(.system(size: 15, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity).padding(.vertical, 12)
                            .background(Theme.gradCool, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
                    }
                }
            }
            .padding(14)
        }
    }

    // MARK: - Ayrıştırma

    /// Metinden makul harcama tutarlarını çıkar (1–99.999, opsiyonel 2 hane kuruş).
    /// Sınırlar: sayının öncesinde/sonrasında rakam ya da ., olamaz — "12.07.2026"
    /// gibi tarihlerden "12.07" ve "2026" tutarı uydurulmasın.
    /// Binlik ayracı: "1.234,56" (TR) / "1,234.56" — son ayraç 1–2 haneliyse
    /// ondalık, tek ayraç + 3 hane ise binlik sayılır.
    static func parseAmounts(from texts: [String]) -> [Double] {
        let joined = texts.joined(separator: " ")
        guard let regex = try? NSRegularExpression(
            pattern: #"(?<![\d.,])\d{1,3}(?:[.,]\d{3})+(?:[.,]\d{1,2})?(?![\d.,])|(?<![\d.,])\d{1,5}(?:[.,]\d{1,2})?(?![\d.,])"#
        ) else { return [] }
        let range = NSRange(joined.startIndex..., in: joined)
        var values = Set<Double>()
        for match in regex.matches(in: joined, range: range) {
            guard let r = Range(match.range, in: joined) else { continue }
            let raw = String(joined[r])
            guard let v = parseNumber(raw), v >= 1, v < 100_000 else { continue }
            // Fişteki tarih parçası gibi duran çıplak yıllar tutar değildir.
            if raw.allSatisfy(\.isNumber), (1900 ... 2100).contains(Int(v)) { continue }
            values.insert(v)
        }
        return values.sorted(by: >).prefix(6).map { $0 }
    }

    /// "1.234,56" → 1234.56 · "1,234.56" → 1234.56 · "1.234" → 1234 (binlik) · "45,50" → 45.5
    private static func parseNumber(_ raw: String) -> Double? {
        let seps = raw.indices.filter { raw[$0] == "." || raw[$0] == "," }
        guard let last = seps.last else { return Double(raw) }
        let decimals = raw.distance(from: raw.index(after: last), to: raw.endIndex)
        if seps.count == 1, decimals == 3 {
            return Double(raw.filter(\.isNumber))   // tek ayraç + 3 hane = binlik
        }
        guard decimals >= 1, decimals <= 2 else { return nil }
        let intPart = raw[..<last].filter(\.isNumber)
        let decPart = raw[raw.index(after: last)...]
        return Double("\(intPart).\(decPart)")
    }

    static func fuelHint(in texts: [String]) -> Bool {
        let joined = texts.joined(separator: " ").lowercased()
        if ["diesel", "dizel", "motorin", "benzin", "petrol", "l/100"].contains(where: { joined.contains($0) }) { return true }
        // "lt/litre/liter" yalnız ayrık kelimeyken ipucu — kültür/filtre/bolt sayılmaz.
        guard let re = try? NSRegularExpression(pattern: #"\b(?:lt|litre|liter)\b"#) else { return false }
        return re.firstMatch(in: joined, range: NSRange(joined.startIndex..., in: joined)) != nil
    }
}

// MARK: - VisionKit sarmalayıcı

private struct DataScannerRepresentable: UIViewControllerRepresentable {
    let onFailure: () -> Void
    let onTexts: ([String]) -> Void

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let vc = DataScannerViewController(
            recognizedDataTypes: [.text()],
            qualityLevel: .balanced,
            recognizesMultipleItems: true,
            isHighlightingEnabled: true
        )
        vc.delegate = context.coordinator
        return vc
    }

    func updateUIViewController(_ vc: DataScannerViewController, context: Context) {
        guard !vc.isScanning, !context.coordinator.failed else { return }
        do {
            try vc.startScanning()
        } catch {
            // İzin reddi / donanım hatası: yutma, panele bildir.
            context.coordinator.failed = true
            onFailure()
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(onTexts: onTexts) }

    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        let onTexts: ([String]) -> Void
        var failed = false
        init(onTexts: @escaping ([String]) -> Void) { self.onTexts = onTexts }

        private func report(_ items: [RecognizedItem]) {
            let texts = items.compactMap { item -> String? in
                if case .text(let t) = item { return t.transcript }
                return nil
            }
            onTexts(texts)
        }

        func dataScanner(_ scanner: DataScannerViewController, didAdd added: [RecognizedItem], allItems: [RecognizedItem]) {
            report(allItems)
        }

        func dataScanner(_ scanner: DataScannerViewController, didUpdate updated: [RecognizedItem], allItems: [RecognizedItem]) {
            report(allItems)
        }

        func dataScanner(_ scanner: DataScannerViewController, didRemove removed: [RecognizedItem], allItems: [RecognizedItem]) {
            report(allItems)
        }
    }
}
