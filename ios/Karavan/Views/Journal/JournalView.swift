import SwiftUI

// Günlük zaman çizgisi. Kendi kayıtların; her biri varsayılan gizli,
// tek tek paylaşılabilir.
struct JournalView: View {
    @EnvironmentObject var journal: JournalStore
    @State private var showCompose = false

    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "tr_TR")
        f.dateFormat = "d MMMM · HH:mm"
        return f
    }()

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottomTrailing) {
                Theme.bg.ignoresSafeArea()

                if journal.entries.isEmpty {
                    emptyState
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 12) {
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

                Button { showCompose = true } label: {
                    ZStack {
                        Circle().fill(Theme.gradWarm).frame(width: 60, height: 60)
                        Image(systemName: "square.and.pencil")
                            .font(.system(size: 22, weight: .bold))
                            .foregroundStyle(.white)
                    }
                    .shadow(color: .black.opacity(0.4), radius: 8, y: 3)
                }
                .buttonStyle(.plain)
                .padding(20)
            }
            .navigationTitle("Günlük")
            .navigationBarTitleDisplayMode(.large)
        }
        .sheet(isPresented: $showCompose) { JournalComposeView() }
        .preferredColorScheme(.dark)
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "book.closed")
                .font(.system(size: 38)).foregroundStyle(Theme.muted)
            Text("Henüz kayıt yok.\nSağ alttaki kalemle başla — istersen sesli yaz.")
                .font(.system(size: 14)).foregroundStyle(Theme.dim)
                .multilineTextAlignment(.center)
        }
        .padding(30)
    }

    // `photoWarning` doluysa göster: fotoğrafı kaydedilememiş bir kayıt
    // sessizce geçmemeli, kullanıcı fotoğrafın gitmediğini bilmeli.
    private func photoWarningBanner(_ message: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "photo.badge.exclamationmark").foregroundStyle(Theme.bad)
            Text(message)
                .font(.system(size: 12)).foregroundStyle(Theme.muted)
            Spacer()
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
                            if let img = UIImage(contentsOfFile: journal.photoURL(name).path) {
                                Image(uiImage: img)
                                    .resizable().scaledToFill()
                                    .frame(width: 88, height: 88)
                                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                            }
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

                Button(role: .destructive) { journal.delete(entry) } label: {
                    Image(systemName: "trash").font(.system(size: 12))
                }
                .buttonStyle(.plain)
                .foregroundStyle(Theme.bad)
            }
        }
        .card()
    }
}
