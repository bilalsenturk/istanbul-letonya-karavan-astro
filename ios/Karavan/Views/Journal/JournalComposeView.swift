import CoreLocation
import SwiftUI
#if canImport(JournalingSuggestions)
import JournalingSuggestions
#endif

// Günlük kaydı oluşturma. Sürerken tek elle kullanılabilir olmalı:
// büyük dokunma hedefleri, tek dokunuşla dikte başlat/bitir.
struct JournalComposeView: View {
    @EnvironmentObject var journal: JournalStore
    @EnvironmentObject var loc: LocationManager
    @EnvironmentObject var nav: NavProgressStore
    @Environment(\.dismiss) private var dismiss

    @StateObject private var speech = SpeechRecorder()
    @State private var text: String
    @State private var mood: String?
    @State private var photos: [Data] = []
    @State private var showPhotoPicker = false
    @State private var showCamera = false
    @State private var textBeforeDictation = ""

    private let moods = ["keyifli", "yorgun", "heyecanlı", "sakin", "sinirli"]

    init(prefillText: String = "") {
        _text = State(initialValue: prefillText)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.bg.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        contextRow
                        editor
                        dictateButton
                        moodRow
                        photoRow
                        suggestionsRow
                    }
                    .padding(16)
                }
            }
            .navigationTitle("Günlüğe yaz")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Vazgeç") { speech.stop(); dismiss() }.tint(Theme.muted)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Kaydet") { save() }
                        .font(.system(size: 16, weight: .bold))
                        .tint(Theme.c2)
                        .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .sheet(isPresented: $showPhotoPicker) {
                JournalPhotoPicker { data in photos.append(contentsOf: data) }
            }
            .sheet(isPresented: $showCamera) {
                JournalCamera { data in photos.append(data) }
                    .ignoresSafeArea()
            }
        }
        .preferredColorScheme(.dark)
        .onChange(of: speech.transcript) { _, new in
            if !new.isEmpty {
                // Dikte sırasında tanıma sonuçları güncellenirken, mevcut metne append et.
                // Metin boşsa tanımayı doğrudan yaz, doluysa araya boşluk girsin.
                if textBeforeDictation.isEmpty {
                    text = new
                } else {
                    text = textBeforeDictation + " " + new
                }
            }
        }
        .onDisappear {
            // Sheet kapatılırken bile ses oturumunu kapat — AV kategorisinin .record'da takılı kalmasını engelle.
            speech.stop()
        }
    }

    // MARK: - Parçalar

    private var contextRow: some View {
        HStack(spacing: 8) {
            if let city = nav.currentCity {
                tag("mappin.and.ellipse", city)
            }
            if let next = nav.nextStop, let km = nav.remainingKm {
                tag("arrow.triangle.turn.up.right.circle", "\(next.name) \(km) km")
            }
            Spacer()
        }
    }

    private var editor: some View {
        TextEditor(text: $text)
            .scrollContentBackground(.hidden)
            .frame(minHeight: 180)
            .font(.system(size: 16))
            .foregroundStyle(Theme.text)
            .padding(10)
            .background(Theme.panel, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Theme.line, lineWidth: 1))
    }

    private var dictateButton: some View {
        Button {
            if speech.recording {
                speech.stop()
            } else {
                // Dikte başlamadan önce mevcut metni hatırla — tanıma sonucunu üzerine yazacağız.
                textBeforeDictation = text
                try? speech.start()
            }
        } label: {
            HStack(spacing: 9) {
                Image(systemName: speech.recording ? "stop.circle.fill" : "mic.fill")
                    .font(.system(size: 18, weight: .bold))
                Text(speech.recording ? "Dinliyorum — bitir" : "Sesli yaz")
                    .font(.system(size: 16, weight: .heavy, design: .rounded))
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 15)
            .background(speech.recording ? AnyShapeStyle(Theme.bad) : AnyShapeStyle(Theme.gradWarm),
                        in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private var moodRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            MonoLabel(text: "Nasıldın", color: Theme.c4)
            HStack(spacing: 7) {
                ForEach(moods, id: \.self) { m in
                    Button { mood = (mood == m) ? nil : m } label: {
                        Text(m)
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                            .foregroundStyle(mood == m ? .white : Theme.muted)
                            .padding(.horizontal, 12).padding(.vertical, 8)
                            .background(mood == m ? AnyShapeStyle(Theme.c1) : AnyShapeStyle(Theme.panel),
                                        in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var photoRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            MonoLabel(text: "Fotoğraf · \(photos.count)", color: Theme.c3)
            HStack(spacing: 8) {
                Button { showCamera = true } label: {
                    HStack(spacing: 7) {
                        Image(systemName: "camera.fill").font(.system(size: 15))
                        Text("Çek").font(.system(size: 14, weight: .semibold, design: .rounded))
                    }
                    .foregroundStyle(Theme.c1)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 13)
                    .background(Theme.panel, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(.plain)

                Button { showPhotoPicker = true } label: {
                    HStack(spacing: 7) {
                        Image(systemName: "photo.badge.plus").font(.system(size: 15))
                        Text("Seç").font(.system(size: 14, weight: .semibold, design: .rounded))
                    }
                    .foregroundStyle(Theme.c3)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 13)
                    .background(Theme.panel, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
    }

    // Apple'ın öneri seçicisi (iOS 17.2+). Seçici ayrı bir süreçte çalışır;
    // yalnızca kullanıcının orada seçtiği içerik uygulamaya geçer, bu yüzden
    // ayrıca fotoğraf/konum izni istemez.
    // ÖNEMLİ: JournalingSuggestions TEK YÖNLÜDÜR — Apple'ın Günlük uygulamasına
    // yazmak için kullanılamaz, üçüncü taraf hiçbir uygulama oraya giriş ekleyemez.
    // Bu çerçeve yalnızca Apple'ın o gün için ürettiği önerileri (nerede
    // olunduğu, kaç fotoğraf çekildiği, kaç km yol gidildiği) bizim günlüğümüze
    // taşımaya yarar. Dağıtım hedefi iOS 17.0 olduğundan hem canImport hem
    // #available koruması şart; 17.0–17.1 cihazlarda bölüm sessizce kaybolur,
    // çökme olmaz.
    @ViewBuilder private var suggestionsRow: some View {
        #if canImport(JournalingSuggestions)
        if #available(iOS 17.2, *) {
            VStack(alignment: .leading, spacing: 8) {
                MonoLabel(text: "Bugünden öneriler", color: Theme.c2)
                JournalingSuggestionsPicker {
                    HStack(spacing: 8) {
                        Image(systemName: "sparkles").font(.system(size: 15))
                        Text("Apple önerilerinden ekle")
                            .font(.system(size: 15, weight: .semibold, design: .rounded))
                        Spacer()
                    }
                    .foregroundStyle(Theme.c2)
                    .padding(13)
                    .background(Theme.panel, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                } onCompletion: { suggestion in
                    let title = suggestion.title
                    await MainActor.run {
                        // Dikte birleştirme mantığıyla tutarlı: kullanıcının yazdığı
                        // metnin üzerine yazmak yerine sona ekle, boşsa doğrudan yaz.
                        if text.isEmpty {
                            text = title
                        } else {
                            text += "\n\n" + title
                        }
                    }
                }
                .buttonStyle(.plain)
            }
        }
        #endif
    }

    private func tag(_ icon: String, _ label: String) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon).font(.system(size: 11))
            Text(label).font(.system(size: 12, weight: .semibold))
        }
        .foregroundStyle(Theme.muted)
        .padding(.horizontal, 10).padding(.vertical, 6)
        .background(Theme.panel, in: Capsule())
    }

    private func save() {
        speech.stop()
        let entry = JournalEntry(
            text: text.trimmingCharacters(in: .whitespacesAndNewlines),
            latitude: loc.location?.coordinate.latitude,
            longitude: loc.location?.coordinate.longitude,
            stopId: nav.nextStop?.id,
            mood: mood
        )
        journal.add(entry, photos: photos)
        dismiss()
    }
}
