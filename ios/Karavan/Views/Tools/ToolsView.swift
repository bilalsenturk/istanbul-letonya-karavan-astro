import SwiftUI
import UIKit

// Araçlar sekmesi: kamera/ses masraf girişi, belge kasası, vinyet, foto günlüğü,
// tabela çevirisi, konum paylaşımı ve Siri/Focus ipuçları — tek yerde.
struct ToolsView: View {
    @EnvironmentObject var expenses: ExpenseStore
    @EnvironmentObject var loc: LocationManager
    @EnvironmentObject var nav: NavProgressStore
    @EnvironmentObject private var account: AccountSessionStore
    @EnvironmentObject private var workspace: TripWorkspaceStore

    @State private var showJourneyMenu = false
    @State private var showExpenseScanner = false
    @State private var showTextScanner = false
    @State private var showVoice = false
    @State private var scannedAmount: Double?
    @State private var scannedNote = ""
    @State private var showPrefilledSheet = false

    var body: some View {
        NavigationStack {
            List {
                Section("Yolculuk") {
                    Button { showJourneyMenu = true } label: {
                        toolLabel(
                            account.isSignedIn ? "person.crop.circle.fill" : "person.crop.circle",
                            "Hesap ve yolculuk",
                            journeySubtitle
                        )
                    }
                }

                Section("Masraf") {
                    Button { showExpenseScanner = true } label: {
                        toolLabel("text.viewfinder", "Tutar tara", "Fiş veya pompa tutarı")
                    }
                    Button { showVoice = true } label: {
                        toolLabel("mic.fill", "Sesli ekle", "Harcama dikte et")
                    }
                }

                Section("Belgeler") {
                    NavigationLink { DocumentVaultView() } label: {
                        toolLabel("lock.shield.fill", "Belge kasası", "Pasaport · sigorta · ruhsat")
                    }
                    NavigationLink { VignettesView() } label: {
                        toolLabel("road.lanes", "Vinyet takibi", "Ülke geçiş izinleri")
                    }
                }

                Section("Yolculuk içeriği") {
                    NavigationLink { MusicView() } label: {
                        toolLabel("music.note.list", "Yolculuk müziği", "Çevrimdışı parçalar")
                    }
                    NavigationLink { LatvianLearningView() } label: {
                        toolLabel("character.bubble.fill", "Letonca oyunu", "Başlangıç alıştırmaları")
                    }
                }

                Section("Yol") {
                    NavigationLink { PhotoJournalView() } label: {
                        toolLabel("photo.stack.fill", "Foto günlüğü", "Konumlu fotoğraflar")
                    }
                    Button { showTextScanner = true } label: {
                        toolLabel("character.book.closed.fill", "Tabela çevirisi", "Kamerayla metin oku")
                    }
                    Button { shareLocationViaSMS() } label: {
                        toolLabel("message.fill", "Konumu paylaş", "SMS mesajı hazırla")
                    }
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(Theme.bg)
            .tint(Theme.c2)
            .navigationTitle("Araçlar")
            .navigationBarTitleDisplayMode(.large)
        }
        .sheet(isPresented: $showExpenseScanner, onDismiss: {
            // Tutar sayfasını tarayıcı TAM KAPANDIKTAN sonra aç — kapanış
            // sürerken istenen ikinci sheet sessizce düşer ve tutar kaybolur.
            if scannedAmount != nil { showPrefilledSheet = true }
        }) {
            ScannerView(mode: .expense) { amount, hint in
                scannedAmount = amount
                scannedNote = hint
            }
        }
        .sheet(isPresented: $showTextScanner) {
            ScannerView(mode: .text)
        }
        .sheet(isPresented: $showVoice) {
            VoiceExpenseView()
        }
        .sheet(isPresented: $showJourneyMenu) {
            JourneyMenuView()
        }
        .sheet(isPresented: $showPrefilledSheet, onDismiss: {
            scannedAmount = nil   // tüketildi — sonraki taramada bayat tutar açılmasın
            scannedNote = ""
        }) {
            AddExpenseSheet(
                prefillAmount: scannedAmount,
                prefillCategory: scannedNote.contains("Yakıt") ? .yakit : .diger,
                prefillNote: scannedNote
            ) { expenses.add($0) }
        }
        .preferredColorScheme(.dark)
    }

    // MARK: - SMS konum paylaşımı

    private var journeySubtitle: String {
        if account.isRestoring { return "Hesap yükleniyor" }
        if !account.isSignedIn { return "Apple ile giriş yap" }
        return workspace.selectedTrip?.name ?? "Rotalarım"
    }

    private func shareLocationViaSMS() {
        var lines = ["Kuzey 🚐 İstanbul→Riga canlı takip: https://istanbul-letonya-karavan-astro.vercel.app"]
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

    private func toolLabel(_ icon: String, _ title: String, _ subtitle: String) -> some View {
        Label {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Theme.text)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(Theme.muted)
                    .lineLimit(1)
            }
        } icon: {
            Image(systemName: icon)
                .font(.system(size: 19, weight: .semibold))
                .foregroundStyle(Theme.c2)
                .frame(width: 28)
        }
        .padding(.vertical, 4)
    }

}
