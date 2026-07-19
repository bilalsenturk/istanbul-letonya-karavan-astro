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

    private var supported: Bool {
        DataScannerViewController.isSupported && DataScannerViewController.isAvailable
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.bg.ignoresSafeArea()
                if supported {
                    VStack(spacing: 0) {
                        DataScannerRepresentable { texts in
                            recognized = texts
                        }
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .padding(12)
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
    static func parseAmounts(from texts: [String]) -> [Double] {
        let joined = texts.joined(separator: " ")
        guard let regex = try? NSRegularExpression(pattern: #"(\d{1,5}(?:[.,]\d{1,2})?)"#) else { return [] }
        let range = NSRange(joined.startIndex..., in: joined)
        var values = Set<Double>()
        for match in regex.matches(in: joined, range: range) {
            guard let r = Range(match.range(at: 1), in: joined) else { continue }
            let normalized = joined[r].replacingOccurrences(of: ",", with: ".")
            if let v = Double(normalized), v >= 1, v < 100_000 { values.insert(v) }
        }
        return values.sorted(by: >).prefix(6).map { $0 }
    }

    static func fuelHint(in texts: [String]) -> Bool {
        let joined = texts.joined(separator: " ").lowercased()
        return ["diesel", "dizel", "motorin", "benzin", "petrol", "lt", "litre", "l/100"]
            .contains { joined.contains($0) }
    }
}

// MARK: - VisionKit sarmalayıcı

private struct DataScannerRepresentable: UIViewControllerRepresentable {
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
        if !vc.isScanning { try? vc.startScanning() }
    }

    func makeCoordinator() -> Coordinator { Coordinator(onTexts: onTexts) }

    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        let onTexts: ([String]) -> Void
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
