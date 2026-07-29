import SwiftUI

// Günlük zaman çizgisi. Kendi kayıtların; her biri varsayılan gizli,
// tek tek paylaşılabilir.
struct JournalView: View {
    @EnvironmentObject var journal: JournalStore
    @State private var showCompose = false
    // Silme onayı bekleyen kayıt. `ForEach` içindeki `entryCard` kendi
    // state'ini tutamaz (View değil, sıradan bir fonksiyon) — bu yüzden
    // hangi kaydın silineceği burada, üst view'da tutulur.
    @State private var entryPendingDelete: JournalEntry?

    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "tr_TR")
        f.dateFormat = "d MMMM · HH:mm"
        return f
    }()

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.bg.ignoresSafeArea()

                if journal.entries.isEmpty {
                    emptyState
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .padding(.horizontal, 28)
                } else {
                    ScrollView {
                        // LazyVStack: yalnızca ekranda görünen kartlar (ve
                        // fotoğrafları) çizilir. Düz VStack kullanılsaydı,
                        // JournalStore'daki pendingCount/cloudProblem/failedCount
                        // gibi fotoğrafla ilgisiz alanlar değiştiğinde bile
                        // (açılış, öne gelme, her yeni kayıt, paylaşım değişimi
                        // — yani sık) TÜM kayıtlar ve TÜM fotoğrafları yeniden
                        // çizilirdi.
                        LazyVStack(alignment: .leading, spacing: 12) {
                            // Fotoğraf uyarısı en üstte: kayıt zaten kaydedildi ama
                            // bir görseli kaybetti — kullanıcı fark etmeden geçmemeli.
                            if let warning = journal.photoWarning {
                                photoWarningBanner(warning)
                            }
                            if let problem = journal.cloudProblem {
                                cloudWarning(problem)
                            } else if journal.pendingCount > 0 {
                                pendingBadge
                            }
                            ForEach(journal.entries) { entry in
                                entryCard(entry)
                            }
                        }
                        .padding(16)
                    }
                }

            }
            .navigationTitle("Günlük")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button { showCompose = true } label: {
                        Image(systemName: "square.and.pencil")
                    }
                    .accessibilityLabel("Günlük kaydı yaz")
                }
            }
        }
        .sheet(isPresented: $showCompose) { JournalComposeView() }
        // TripSettingsView'daki "tüm düzenlemeleri sıfırla" kalıbıyla aynı:
        // tek dokunuşla kalıcı silme yerine onay iste. Buradaki silme çok
        // daha hassas — metni, fotoğrafları VE CloudKit kaydını geri
        // dönüşsüz siliyor — yine de eskiden onaysızdı.
        .confirmationDialog(
            "Bu günlük kaydı silinsin mi?",
            isPresented: Binding(
                get: { entryPendingDelete != nil },
                set: { if !$0 { entryPendingDelete = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Sil", role: .destructive) {
                if let entry = entryPendingDelete { journal.delete(entry) }
                entryPendingDelete = nil
            }
            Button("Vazgeç", role: .cancel) { entryPendingDelete = nil }
        } message: {
            if let entry = entryPendingDelete {
                Text("\"\(Self.preview(entry.text))\" kaydı, fotoğrafları dahil kalıcı olarak silinecek. Bu işlem geri alınamaz.")
            }
        }
        .preferredColorScheme(.dark)
    }

    /// Onay mesajında hangi kaydın silineceğini belli etmek için kısa bir
    /// önizleme üretir. Metin boşsa (yalnızca fotoğraflı kayıt) yerine
    /// tarihini göster ki mesaj boş tırnak olarak kalmasın.
    private static func preview(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "Bu kayıt" }
        let limit = 60
        if trimmed.count > limit {
            return String(trimmed.prefix(limit)) + "…"
        }
        return trimmed
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "book.closed")
                .font(.system(size: 38))
                .foregroundStyle(Theme.muted)
            Text("Henüz kayıt yok")
                .font(.system(size: 17, weight: .semibold, design: .rounded))
                .foregroundStyle(Theme.dim)
                .multilineTextAlignment(.center)
            Text("Yoldaki anları, notları ve fotoğrafları burada biriktir.")
                .font(.system(size: 14, weight: .medium, design: .rounded))
                .foregroundStyle(Theme.muted)
                .multilineTextAlignment(.center)
            Button { showCompose = true } label: {
                Text("İlk kaydını ekle")
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 44)
                    .background(Theme.gradWarm, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
            }
            .buttonStyle(.plain)
            .padding(.top, 4)
        }
    }

    // `photoWarning` doluysa göster: fotoğrafı kaydedilememiş bir kayıt
    // sessizce geçmemeli, kullanıcı fotoğrafın gitmediğini bilmeli.
    private func photoWarningBanner(_ message: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "photo.badge.exclamationmark").foregroundStyle(Theme.bad)
            Text(message)
                .font(.system(size: 12)).foregroundStyle(Theme.muted)
            Spacer()
            // Uyarı yalnızca bir sonraki kayıt eklemesinde kendiliğinden
            // temizleniyordu — kullanıcı elle kapatamıyordu. Artık kapatılabilir.
            Button {
                journal.clearPhotoWarning()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.muted)
            }
            .buttonStyle(.plain)
        }
        .padding(11)
        .background(Theme.panel, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func cloudWarning(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.icloud").foregroundStyle(Theme.bad)
                Text(message)
                    .font(.system(size: 12)).foregroundStyle(Theme.muted)
                Spacer()
            }
            // Azami deneme hakkı biten kayıtlar otomatik tekrar denenmez
            // (JournalStore.retryFailed dokümantasyonu) — bu yüzden burada
            // elle bir çıkış yolu sunulmazsa kullanıcıya vaat edilen "tekrar
            // dene" imkânı hiçbir arayüzde erişilemez kalır.
            if journal.failedCount > 0 {
                Button {
                    journal.retryFailed()
                } label: {
                    Label("Tekrar dene", systemImage: "arrow.clockwise")
                        .font(.system(size: 12, weight: .bold))
                }
                .buttonStyle(.plain)
                .foregroundStyle(Theme.c1)
            }
        }
        .padding(11)
        .background(Theme.panel, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var pendingBadge: some View {
        HStack(spacing: 8) {
            Image(systemName: "arrow.triangle.2.circlepath").foregroundStyle(Theme.muted)
            Text("\(journal.pendingCount) kayıt yüklenmeyi bekliyor")
                .font(.system(size: 12)).foregroundStyle(Theme.muted)
            Spacer()
        }
        .padding(11)
        .background(Theme.panel, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func entryCard(_ entry: JournalEntry) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                Text(Self.dayFormatter.string(from: entry.createdAt))
                    .font(.system(size: 11.5, weight: .bold, design: .monospaced))
                    .foregroundStyle(Theme.c4)
                if let mood = entry.mood {
                    Text(mood)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Theme.muted)
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(Theme.bg, in: Capsule())
                }
                Spacer()
                Image(systemName: entry.isShared ? "person.2.fill" : "lock.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(entry.isShared ? Theme.c1 : Theme.muted)
            }

            Text(entry.text)
                .font(.system(size: 15))
                .foregroundStyle(Theme.text)
                .fixedSize(horizontal: false, vertical: true)

            if !entry.photoFilenames.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(entry.photoFilenames, id: \.self) { name in
                            JournalPhotoThumb(url: journal.photoURL(name))
                                .frame(width: 88, height: 88)
                                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        }
                    }
                }
            }

            HStack(spacing: 14) {
                Button {
                    journal.setShared(entry, shared: !entry.isShared)
                } label: {
                    Label(entry.isShared ? "Paylaşımı kaldır" : "Paylaş",
                          systemImage: entry.isShared ? "person.2.slash" : "person.2")
                        .font(.system(size: 12, weight: .semibold))
                }
                .buttonStyle(.plain)
                .foregroundStyle(entry.isShared ? Theme.muted : Theme.c1)

                Spacer()

                Button(role: .destructive) { entryPendingDelete = entry } label: {
                    Image(systemName: "trash").font(.system(size: 12))
                }
                .buttonStyle(.plain)
                .foregroundStyle(Theme.bad)
            }
        }
        .card()
    }
}

// NSCache kendi içinde thread-safe; dosya kapsamında (View'ın MainActor
// çıkarımının dışında) tutuluyor ki arka plan Task'ından erişim derleyici
// uyarısı üretmesin.
private let journalPhotoCache = NSCache<NSString, UIImage>()

// Fotoğraf küçük resmi: diskten yalnızca BİR KEZ okunur ve çözülür, sonra
// bellek içi önbellekte tutulur. `PhotoJournalView.PhotoThumb` ile aynı
// kalıp — burada PhotoKit yerine dosya yolundan yükleniyor. Önbellek
// olmadan her `body` yeniden değerlendirmesinde (ör. pendingCount değişince)
// aynı fotoğraf yeniden senkron diskten okunup çözülürdü.
private struct JournalPhotoThumb: View {
    let url: URL
    @State private var image: UIImage?
    /// Dosya bu cihazda yok/okunamıyor (ör. başka cihazdan gelen kaydın
    /// fotoğrafı henüz inmedi ya da indirilemedi) — ProgressView sonsuza dek
    /// dönmesin diye yer tutucu gösterilir. KİLİTLİ DEĞİL: merge'in arka plan
    /// indirmesi dosyayı getirince `photoArrivedNotification` ile yeniden
    /// denenir (eskiden failed=true bir kez yazılır, inen fotoğraf uygulama
    /// yeniden açılana dek görünmezdi).
    @State private var failed = false

    var body: some View {
        ZStack {
            if let image {
                Image(uiImage: image).resizable().scaledToFill()
            } else if failed {
                Theme.panel
                Image(systemName: "photo")
                    .font(.system(size: 20))
                    .foregroundStyle(Theme.dim)
            } else {
                Theme.panel
                ProgressView().tint(Theme.muted).scaleEffect(0.7)
            }
        }
        .onAppear { load() }
        .onReceive(NotificationCenter.default.publisher(for: JournalStore.photoArrivedNotification)) { _ in
            // Arka plan indirmesi yeni dosya yazdı — yer tutucuda takılı
            // kalmışsak kilidi aç ve yeniden dene.
            guard image == nil, failed else { return }
            failed = false
            load()
        }
    }

    private func load() {
        guard image == nil, !failed else { return }
        let key = url.path as NSString
        if let cached = journalPhotoCache.object(forKey: key) {
            image = cached
            return
        }
        // Okuma + çözme ana iş parçacığını kilitlemesin diye arka planda;
        // sonucu küçük boyuta (kart 88pt @2x/@3x) indirip önbelleğe koy.
        Task.detached(priority: .userInitiated) {
            guard let original = UIImage(contentsOfFile: url.path) else {
                // Dosya (henüz) yok — merge'in arka plan indirmesi bitince
                // photoArrivedNotification ile yeniden denenecek; o zamana
                // dek sonsuz ProgressView yerine yer tutucu göster.
                await MainActor.run { self.failed = true }
                return
            }
            let thumb = await original.byPreparingThumbnail(ofSize: CGSize(width: 176, height: 176)) ?? original
            journalPhotoCache.setObject(thumb, forKey: key)
            await MainActor.run {
                self.image = thumb
            }
        }
    }
}
