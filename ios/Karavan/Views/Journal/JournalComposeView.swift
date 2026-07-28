import AVFoundation
import CoreLocation
import Speech
import SwiftUI
#if canImport(UIKit)
import UIKit
#endif
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
    /// Dikteyle metne en son yazılan kısmi sonuç. Dikte sürerken kullanıcının
    /// elle yaptığı düzenlemeleri bir sonraki kısmi sonuçtan ayırt etmek için
    /// tutulur (bkz. onChange(of: text)).
    @State private var lastTranscript = ""
    /// Mikrofon/konuşma izni reddedildi ya da dikte başlatılamadı — sessiz
    /// kalmak düğmeyi ölü gösterir, kullanıcıya söylenir.
    @State private var speechDenied = false
    /// "Kaydet" çift dokunuş koruması: sheet kapanana kadar ikinci bir
    /// dokunuş aynı kaydı iki kez eklemesin.
    @State private var saved = false
    @FocusState private var editorFocused: Bool

    private let moods = ["keyifli", "yorgun", "heyecanlı", "sakin", "sinirli"]
    private let starterPrompts = [
        "Bugün aklımda kalan şey:",
        "Leyla için not:",
        "Yoldaki en iyi an:",
        "Kampa vardığımızda:"
    ]

    init(prefillText: String = "") {
        _text = State(initialValue: prefillText)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.bg.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        composeHeader
                        promptRow
                        editor
                        dictateButton
                        if speechDenied {
                            Text("Sesli yazma başlatılamadı — mikrofon/konuşma iznini Ayarlar'dan açabilirsin.")
                                .font(.system(size: 13))
                                .foregroundStyle(Theme.bad)
                        }
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
                        .disabled(saved || text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
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
            // Dikte BİTTİKTEN sonra gelebilecek gecikmiş bir sonuç,
            // kullanıcının az önce elle yaptığı düzenlemeleri ezer — yalnızca
            // kayıt sürerken uygula (SpeechRecorder tarafı da aynı kontrolü
            // yapar; burası ikinci güvence).
            guard speech.recording, !new.isEmpty else { return }
            // Dikte sırasında tanıma sonuçları güncellenirken, mevcut metne append et.
            // Metin boşsa tanımayı doğrudan yaz, doluysa araya boşluk girsin.
            if textBeforeDictation.isEmpty {
                text = new
            } else {
                text = textBeforeDictation + " " + new
            }
            lastTranscript = new
        }
        .onChange(of: text) { _, newValue in
            // Dikte SÜRERKEN kullanıcı elle de yazabilir. Eskiden bir sonraki
            // kısmi tanıma sonucu metni `textBeforeDictation + transcript`
            // olarak baştan kurduğu için elle yazılanlar sessizce siliniyordu.
            // Elle düzenleme algılanınca (metin, bizim son çıktımızdan
            // farklıysa) dikte kısmını çıkarıp kalanı yeni taban yap — böylece
            // kullanıcının yazdıkları bir sonraki kısmi sonuçta korunur.
            //
            // lastTranscript BOŞKEN de (dikte başladı, ilk kısmi sonuç henüz
            // gelmedi) taban takip edilmeli: eskiden guard boş transcript'i
            // reddettiği için bu aralıkta yazılanlar ilk kısmi sonuçta
            // kayboluyordu.
            guard speech.recording else { return }
            let rendered = lastTranscript.isEmpty
                ? textBeforeDictation
                : (textBeforeDictation.isEmpty
                    ? lastTranscript
                    : textBeforeDictation + " " + lastTranscript)
            guard newValue != rendered else { return }
            // Sondan GERİYE ara: dikte edilen ifade kullanıcının kendi
            // metninde de geçiyorsa ilk eşleşme (range(of:)) yanlışlıkla
            // kullanıcının kendi kelimelerini silerdi; dikte kısmı her zaman
            // SONA eklendiği için doğru eşleşme sondakidir.
            if !lastTranscript.isEmpty,
               let range = newValue.range(of: lastTranscript, options: .backwards) {
                // Dikte kısmı hâlâ metinde — onu çıkar, kalan (kullanıcının
                // elle yazdıkları) yeni taban olsun.
                var base = newValue
                base.removeSubrange(range)
                textBeforeDictation = base.trimmingCharacters(in: .whitespaces)
            } else {
                // Kullanıcı dikte edilen kısmı silmiş/değiştirmiş ya da ilk
                // kısmi sonuçtan önce elle yazmış — metnin tamamını taban yap
                // ki yazdıkları bir sonraki kısmi sonuçta geri alınmasın
                // (yeni kısmi sonuç yine sona eklenir).
                textBeforeDictation = newValue
            }
        }
        .onDisappear {
            // Sheet kapatılırken bile ses oturumunu kapat — AV kategorisinin .record'da takılı kalmasını engelle.
            speech.stop()
        }
    }

    // MARK: - Parçalar

    private var composeHeader: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 5) {
                    MonoLabel(text: "Yol günlüğü", color: Theme.c2)
                    Text(Date.now.formatted(.dateTime.day().month(.wide).hour().minute()))
                        .font(.system(size: 24, weight: .heavy, design: .rounded))
                        .foregroundStyle(Theme.text)
                }
                Spacer()
                Image(systemName: "square.and.pencil")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(Theme.c2)
                    .frame(width: 38, height: 38)
                    .background(Theme.c2.opacity(0.13), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }

            HStack(spacing: 8) {
                if let city = nav.currentCity {
                    tag("mappin.and.ellipse", city)
                }
                if let next = nav.nextStop {
                    tag("arrow.triangle.turn.up.right.circle", next.name)
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(14)
        .background(Theme.panel, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Theme.line, lineWidth: 1))
    }

    private var promptRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            MonoLabel(text: "Başlangıç", color: Theme.c4)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 148), spacing: 8)], spacing: 8) {
                ForEach(starterPrompts, id: \.self) { prompt in
                    Button { insertPrompt(prompt) } label: {
                        Text(prompt)
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                            .foregroundStyle(Theme.text)
                            .lineLimit(2)
                            .minimumScaleFactor(0.78)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                            .background(Theme.panel, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Theme.line, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var editor: some View {
        VStack(alignment: .leading, spacing: 10) {
            ZStack(alignment: .topLeading) {
                TextEditor(text: $text)
                    .focused($editorFocused)
                    .scrollContentBackground(.hidden)
                    .frame(minHeight: 240)
                    .font(.system(size: 17, weight: .regular, design: .rounded))
                    .foregroundStyle(Theme.text)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 2)

                if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text("Bugün yolda ne oldu?")
                        .font(.system(size: 17, weight: .medium, design: .rounded))
                        .foregroundStyle(Theme.muted.opacity(0.78))
                        .padding(.horizontal, 9)
                        .padding(.vertical, 10)
                        .allowsHitTesting(false)
                }
            }

            HStack {
                Text("\(text.trimmingCharacters(in: .whitespacesAndNewlines).count) karakter")
                Spacer()
                Text(speech.recording ? "Dikte açık" : "Yazı kaydı")
            }
            .font(.system(size: 11, weight: .semibold, design: .monospaced))
            .foregroundStyle(Theme.dim)
        }
        .padding(12)
        .background(Theme.panel, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
            .strokeBorder(editorFocused ? Theme.c2.opacity(0.75) : Theme.line, lineWidth: 1))
    }

    private var dictateButton: some View {
        Button {
            if speech.recording {
                speech.stop()
            } else {
                startDictation()
            }
        } label: {
            HStack(spacing: 9) {
                Image(systemName: speech.recording ? "stop.circle.fill" : "mic.fill")
                    .font(.system(size: 18, weight: .bold))
                Text(speech.recording ? "Dikteyi bitir" : "Sesli yaz")
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

    /// Dikte ancak konuşma tanıma + mikrofon izni verildiyse başlar. Eskiden
    /// izin hiç istenmiyor ve `try? speech.start()` hatayı yutuyordu — izinsiz
    /// cihazda düğme ölü kalıyordu. VoiceExpenseView ile aynı izin akışı.
    private func startDictation() {
        SFSpeechRecognizer.requestAuthorization { status in
            DispatchQueue.main.async {
                guard status == .authorized else { speechDenied = true; return }
                AVAudioApplication.requestRecordPermission { granted in
                    DispatchQueue.main.async {
                        guard granted else { speechDenied = true; return }
                        speechDenied = false
                        // Dikte başlamadan önce mevcut metni hatırla — tanıma sonucunu üzerine yazacağız.
                        textBeforeDictation = text
                        lastTranscript = ""
                        do {
                            try speech.start()
                        } catch {
                            // Ses oturumu/motor kurulamadı — yutulursa düğme
                            // yine ölü kalır; kullanıcıya göster.
                            speechDenied = true
                        }
                    }
                }
            }
        }
    }

    private var moodRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            MonoLabel(text: "Nasıldın", color: Theme.c4)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 96), spacing: 8)], spacing: 8) {
                ForEach(moods, id: \.self) { m in
                    Button { mood = (mood == m) ? nil : m } label: {
                        Text(m)
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                            .foregroundStyle(mood == m ? .white : Theme.muted)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(mood == m ? AnyShapeStyle(Theme.c1) : AnyShapeStyle(Theme.panel),
                                        in: RoundedRectangle(cornerRadius: 12, style: .continuous))
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

            if !photos.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 9) {
                        ForEach(Array(photos.enumerated()), id: \.offset) { index, data in
                            photoThumb(data: data, index: index)
                        }
                    }
                    .padding(.top, 2)
                }
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
                        // VERİ KAYBI DÜZELTMESİ: Dikte çalışırken Apple önerisi eklendiyse,
                        // textBeforeDictation'ı da güncellemeliyiz. Aksi takdirde, bir sonraki
                        // dikte kısmi sonucu onChange tetiklenip metnin eski textBeforeDictation
                        // tabanından yeniden yapılmasını ve az önce eklenen önerinin silinmesini
                        // sağlayacaktır. Önerileri koruyan bu yaklaşım, tek elle kullanımdaki
                        // gerçek senaryoları karşılar.
                        if speech.recording {
                            // `text`'i doğrudan taban YAPMA: dikte sürerken
                            // text = taban + canlı transcript + öneri; canlı
                            // transcript'i tabana pişirirsek bir sonraki kısmi
                            // sonuç (aynı sözleri içerir) sona eklenince dikte
                            // kelimeleri ÇİFTLENİR. Tabanı canlı transcript
                            // hariç yeniden hesapla (sondan geriye arama —
                            // dikte kısmı sondadır, bkz. onChange(of: text)).
                            var base = text
                            if !lastTranscript.isEmpty,
                               let range = base.range(of: lastTranscript, options: .backwards) {
                                base.removeSubrange(range)
                            }
                            textBeforeDictation = base.trimmingCharacters(in: .whitespacesAndNewlines)
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

    @ViewBuilder
    private func photoThumb(data: Data, index: Int) -> some View {
        #if canImport(UIKit)
        if let image = UIImage(data: data) {
            ZStack(alignment: .topTrailing) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 86, height: 86)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Theme.line, lineWidth: 1))

                Button {
                    if photos.indices.contains(index) {
                        photos.remove(at: index)
                    }
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 18, weight: .bold))
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(.white, Color.black.opacity(0.55))
                        .padding(5)
                }
                .buttonStyle(.plain)
            }
        }
        #endif
    }

    private func insertPrompt(_ prompt: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            text = prompt + "\n"
        } else {
            text += "\n\n" + prompt + "\n"
        }
        editorFocused = true
    }

    private func save() {
        // Çift dokunuş koruması — sheet kapanmadan gelen ikinci dokunuş
        // aynı kaydın kopyasını eklemesin.
        guard !saved else { return }
        saved = true
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
