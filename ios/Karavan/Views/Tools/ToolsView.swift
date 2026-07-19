import SwiftUI
import UIKit

// Araçlar sekmesi: kamera/ses masraf girişi, belge kasası, vinyet, foto günlüğü,
// tabela çevirisi, konum paylaşımı ve Siri/Focus ipuçları — tek yerde.
struct ToolsView: View {
    @EnvironmentObject var expenses: ExpenseStore
    @EnvironmentObject var loc: LocationManager
    @EnvironmentObject var nav: NavProgressStore

    @State private var showExpenseScanner = false
    @State private var showTextScanner = false
    @State private var showVoice = false
    @State private var scannedAmount: Double?
    @State private var scannedNote = ""
    @State private var showPrefilledSheet = false

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.bg.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        section("Masraf", Theme.c1) {
                            toolRow("text.viewfinder", "Tutar tara", "Pompa/fiş tutarını kamerayla oku") {
                                showExpenseScanner = true
                            }
                            toolRow("mic.fill", "Sesli ekle", "“45 euro yakıt” de, gerisini bırak") {
                                showVoice = true
                            }
                            hintRow("waveform.badge.mic", "Siri: “Hey Siri, Kuzey harcama ekle”")
                        }

                        section("Belgeler", Theme.c4) {
                            navRow("lock.shield.fill", "Belge kasası", "Pasaport · sigorta · ruhsat (Face ID)") {
                                DocumentVaultView()
                            }
                            navRow("road.lanes", "Vinyet takibi", "Ülke geçiş izinleri + bitiş uyarısı") {
                                VignettesView()
                            }
                        }

                        section("Yol", Theme.c3) {
                            navRow("photo.stack.fill", "Foto günlüğü", "Konumlu fotoğraflar rota haritasında") {
                                PhotoJournalView()
                            }
                            toolRow("character.book.closed.fill", "Tabela çevirisi", "Kamerayla metni oku → sistem çevirisi") {
                                showTextScanner = true
                            }
                            toolRow("message.fill", "Konumu SMS'le paylaş", "Canlı harita linkiyle mesaj hazırla") {
                                shareLocationViaSMS()
                            }
                            hintRow("moon.circle.fill", "Sürüş Focus'una \"Kuzey Sade Mod\" filtresi eklenebilir (Ayarlar → Odak)")
                        }
                    }
                    .padding(16)
                }
            }
            .navigationTitle("Araçlar")
            .navigationBarTitleDisplayMode(.large)
        }
        .sheet(isPresented: $showExpenseScanner) {
            ScannerView(mode: .expense) { amount, hint in
                scannedAmount = amount
                scannedNote = hint
                showPrefilledSheet = true
            }
        }
        .sheet(isPresented: $showTextScanner) {
            ScannerView(mode: .text)
        }
        .sheet(isPresented: $showVoice) {
            VoiceExpenseView()
        }
        .sheet(isPresented: $showPrefilledSheet) {
            AddExpenseSheet(
                prefillAmount: scannedAmount,
                prefillCategory: scannedNote.contains("Yakıt") ? .yakit : .diger,
                prefillNote: scannedNote
            ) { expenses.add($0) }
        }
        .preferredColorScheme(.dark)
    }

    // MARK: - SMS konum paylaşımı

    private func shareLocationViaSMS() {
        var lines = ["Kuzey 🚐 İstanbul→Riga canlı takip: https://istanbul-riga.vercel.app"]
        if let l = loc.location {
            lines.append("Şu an: https://maps.apple.com/?ll=\(l.coordinate.latitude),\(l.coordinate.longitude)")
        }
        if let next = nav.nextStop, let km = nav.remainingKm {
            lines.append("Sıradaki: \(next.name) · \(km) km")
        }
        let body = lines.joined(separator: "\n")
        var comps = URLComponents(string: "sms:")!
        comps.queryItems = [URLQueryItem(name: "body", value: body)]
        if let url = comps.url { UIApplication.shared.open(url) }
    }

    // MARK: - Yapı taşları

    private func section(_ title: String, _ color: Color, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            MonoLabel(text: title, color: color)
            VStack(spacing: 8, content: content)
        }
    }

    private func toolRow(_ icon: String, _ title: String, _ subtitle: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { rowLabel(icon, title, subtitle, chevron: "arrow.up.right") }
            .buttonStyle(.plain)
    }

    private func navRow(_ icon: String, _ title: String, _ subtitle: String,
                        @ViewBuilder destination: () -> some View) -> some View {
        NavigationLink { destination() } label: { rowLabel(icon, title, subtitle, chevron: "chevron.right") }
            .buttonStyle(.plain)
    }

    private func rowLabel(_ icon: String, _ title: String, _ subtitle: String, chevron: String) -> some View {
        HStack(spacing: 13) {
            ZStack {
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(Theme.c2.opacity(0.14)).frame(width: 42, height: 42)
                Image(systemName: icon).font(.system(size: 17)).foregroundStyle(Theme.c2)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 15.5, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.text)
                Text(subtitle)
                    .font(.system(size: 12)).foregroundStyle(Theme.muted)
                    .lineLimit(1)
            }
            Spacer()
            Image(systemName: chevron).font(.system(size: 12, weight: .bold)).foregroundStyle(Theme.muted)
        }
        .padding(12)
        .background(Theme.panel, in: RoundedRectangle(cornerRadius: 15, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 15, style: .continuous).strokeBorder(Theme.line, lineWidth: 1))
    }

    private func hintRow(_ icon: String, _ text: String) -> some View {
        HStack(spacing: 9) {
            Image(systemName: icon).font(.system(size: 13)).foregroundStyle(Theme.muted)
            Text(text).font(.system(size: 12)).foregroundStyle(Theme.muted)
            Spacer()
        }
        .padding(.horizontal, 4)
    }
}
