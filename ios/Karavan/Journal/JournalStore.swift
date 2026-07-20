import Foundation
import SwiftUI

// Cihaz-ÖNCE depo: her kayıt önce diske yazılır, sonra buluta gönderilir.
// Yolculuğun büyük kısmı sinyalin zayıf olduğu sınır bölgelerinden geçiyor;
// buluta yazamamak kaydı kaybetmek anlamına gelmemeli.
@MainActor
final class JournalStore: ObservableObject {
    @Published private(set) var entries: [JournalEntry] = []
    @Published private(set) var pendingCount = 0
    @Published private(set) var cloudAvailable = true
    /// Kullanıcıya gösterilecek bulut sorunu. Sessizce yutulmamalı:
    /// kota dolduğunda kayıtlar cihazda birikir ve kimse fark etmez.
    @Published private(set) var cloudProblem: String?
    /// Azami deneme sayısına ulaşıp tamamen vazgeçilen (senkronlanamayan)
    /// kayıt sayısı. Bu kayıtlar `pendingCount`'a girmez — kullanıcı ayrıca
    /// bilgilendirilmezse hiçbir yerde görünmez ve hiç yüklenmediklerini
    /// asla öğrenemez.
    @Published private(set) var failedCount = 0
    /// `add()` sırasında bir veya daha fazla fotoğraf diske yazılamadıysa
    /// kullanıcıya gösterilecek uyarı. Sessizce yutulursa kayıt var olmayan
    /// bir dosyaya işaret eder, kullanıcı fark etmeden fotoğrafı kaybeder.
    @Published private(set) var photoWarning: String?

    private var queue = JournalQueue()
    /// Bulutta silinmeyi bekleyen kayıt id'leri. `delete()` ağ yokken
    /// CloudKit'e hiç ulaşamayabilir; bu liste diske yazıldığı için
    /// uygulama kapanıp açılsa da deneme sürer — aksi halde kayıt
    /// CloudKit'te sonsuza dek öksüz kalır ve başka cihazda görünmeye devam eder.
    private var pendingDeleteIds: Set<String> = []

    private var dir: URL {
        let d = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("journal", isDirectory: true)
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }

    private var entriesFile: URL { dir.appendingPathComponent("entries.json") }
    private var queueFile: URL { dir.appendingPathComponent("queue.json") }
    private var pendingDeletesFile: URL { dir.appendingPathComponent("pending-deletes.json") }

    init() {
        load()
    }

    // MARK: - Okuma / yazma

    private func load() {
        if let data = try? Data(contentsOf: entriesFile),
           let decoded = try? JSONDecoder().decode([JournalEntry].self, from: data) {
            entries = decoded.sorted { $0.createdAt > $1.createdAt }
        }
        if let data = try? Data(contentsOf: queueFile),
           let decoded = try? JSONDecoder().decode(JournalQueue.self, from: data) {
            queue = decoded
        }
        if let data = try? Data(contentsOf: pendingDeletesFile),
           let decoded = try? JSONDecoder().decode(Set<String>.self, from: data) {
            pendingDeleteIds = decoded
        }
        refreshQueueStats()
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(entries) {
            try? data.write(to: entriesFile, options: .atomic)
        }
        if let data = try? JSONEncoder().encode(queue) {
            try? data.write(to: queueFile, options: .atomic)
        }
        if let data = try? JSONEncoder().encode(pendingDeleteIds) {
            try? data.write(to: pendingDeletesFile, options: .atomic)
        }
        refreshQueueStats()
    }

    /// `pendingCount`/`failedCount`'u kuyruğun güncel durumuyla eşitler.
    /// load() ve persist() sonrasında tek noktadan çağrılır ki ikisi
    /// birbirinden sürüklenmesin.
    private func refreshQueueStats() {
        pendingCount = queue.pendingCount
        failedCount = queue.items.filter { $0.state == .failed }.count
    }

    func photoURL(_ filename: String) -> URL {
        dir.appendingPathComponent(filename)
    }

    // MARK: - Düzenleme

    @discardableResult
    func add(_ entry: JournalEntry, photos: [Data]) -> JournalEntry {
        var saved = entry
        var names: [String] = []
        for (i, data) in photos.enumerated() {
            let name = "\(entry.id)-\(i).jpg"
            do {
                try data.write(to: photoURL(name), options: .atomic)
                names.append(name)
            } catch {
                // Yazılamayan dosyanın adı listeye GİRMEMELİ — aksi halde
                // kayıt var olmayan bir dosyaya işaret eder ve galeri
                // sekmesinde kırık görsel olarak kalır.
            }
        }
        saved.photoFilenames = names

        // Hiç fotoğraf yazılamadıysa kullanıcı sessizce veri kaybetmesin —
        // "eklendi" sanıp bir daha kontrol etmeyebilir.
        photoWarning = (!photos.isEmpty && names.isEmpty)
            ? "Fotoğraflar kaydedilemedi — cihaz depolaması dolu olabilir."
            : nil

        entries.insert(saved, at: 0)
        queue.enqueue(saved.id)
        persist()
        Task { await drainQueue() }
        return saved
    }

    func delete(_ entry: JournalEntry) {
        entries.removeAll { $0.id == entry.id }
        for name in entry.photoFilenames {
            try? FileManager.default.removeItem(at: photoURL(name))
        }
        queue.markSynced(entry.id)   // kuyruktan da düşür
        // Bulut silmesini burada ateşle-unut yapmıyoruz: ağ yoksa deneme
        // kaybolur ve kayıt CloudKit'te sonsuza dek kalır. Kalıcı listeye
        // ekleyip drainQueue() üzerinden (şimdi ve sonraki her tetiklemede)
        // yeniden deniyoruz.
        pendingDeleteIds.insert(entry.id)
        persist()
        Task { await drainQueue() }
    }

    func setShared(_ entry: JournalEntry, shared: Bool) {
        guard let i = entries.firstIndex(where: { $0.id == entry.id }) else { return }
        entries[i].isShared = shared
        queue.enqueue(entry.id)
        persist()
        Task { await drainQueue() }
    }

    // MARK: - Kuyruk boşaltma

    func drainQueue() async {
        cloudAvailable = await JournalCloud.shared.accountAvailable()
        guard cloudAvailable else {
            cloudProblem = "iCloud oturumu kapalı — kayıtların yalnızca bu cihazda."
            return
        }

        await drainPendingDeletes()

        while let id = queue.nextToSend(now: Date()) {
            guard let snapshot = entries.first(where: { $0.id == id }) else {
                queue.markSynced(id)
                continue
            }
            queue.markSyncing(id, now: Date())
            persist()

            let urls = snapshot.photoFilenames.map { photoURL($0) }
                .filter { FileManager.default.fileExists(atPath: $0.path) }

            do {
                try await JournalCloud.shared.save(snapshot, photoURLs: urls)
                // await sırasında kayıt değişmiş olabilir (ör. kullanıcı
                // setShared() çağırdı) — o an enqueue() kuyrukta zaten
                // .syncing durumda olan kayıt için sessizce no-op yapmıştı.
                // Gönderdiğimiz anlık görüntü hâlâ güncelse normal şekilde
                // düşür; değilse güncel hâlin gitmesi için yeniden kuyrukla
                // (bu bir gönderim BAŞARISIZLIĞI değil, içerik bayatlamasıydı
                // — bu yüzden deneme sayısı ARTIRILMAZ, markSynced + enqueue
                // ile sıfırdan pending'e döner).
                switch entries.first(where: { $0.id == id }) {
                case .some(let current) where current == snapshot:
                    queue.markSynced(id)
                case .some:
                    queue.markSynced(id)
                    queue.enqueue(id)
                case .none:
                    break   // delete() zaten kuyruktan düşürmüştü, dokunma
                }
            } catch JournalCloudError.quotaExceeded {
                cloudProblem = "iCloud depolaman dolu — kayıtlar cihazda bekliyor."
                queue.markFailed(id, now: Date())
                persist()
                break
            } catch JournalCloudError.accountUnavailable {
                // Döngü başında uygunmuş gibi görünüp arada kapanmış olabilir
                // (hesaptan çıkış, kısıtlama vb.) — durumu da kullanıcı mesajını
                // da güncel tut, aksi halde arayüz "bulut var" der ama hiç
                // gönderemez.
                cloudAvailable = false
                cloudProblem = "iCloud oturumu kapalı — kayıtların yalnızca bu cihazda."
                queue.markFailed(id, now: Date())
                persist()
                break
            } catch {
                // network / notFound / unexpected — hepsi geçici veya tek
                // kayıtlık sorunlar sayılır; kuyrukta bekletip bir sonraki
                // tetiklemede (uygulama öne gelince, ağ dönünce) tekrar denenir.
                queue.markFailed(id, now: Date())
                persist()
                break
            }
            persist()
        }

        // Sorun mesajını yalnızca GERÇEKTEN çözüldüğünde temizle: kuyrukta
        // geri çekilme bekleyen ya da azami denemeye ulaşıp tamamen
        // vazgeçilmiş (failed) bir kayıt varken temizlemek kullanıcıya
        // "sorun yok" yanılgısı verir — oysa kayıt hâlâ cihazda takılı,
        // hiçbir yere gitmedi.
        if !queue.items.contains(where: { $0.attempts > 0 }) {
            cloudProblem = nil
        } else if cloudProblem == nil {
            // Bu turda hiçbir gönderim denenmedi (hepsi geri çekilme
            // bekliyor) ya da önceki oturumdan kalan mesaj kalıcı değildi
            // (uygulama yeniden başlatıldı) — kuyrukta yine de sorunlu kayıt
            // var, kullanıcıyı habersiz bırakma.
            cloudProblem = "iCloud'a gönderilemeyen kayıtlar var — otomatik olarak tekrar denenecek."
        }
        persist()
    }

    /// Bulutta silinmeyi bekleyen kayıtları tekrar dener. `notFound` başarı
    /// sayılır — kayıt zaten sunucuda yok, silme amacına ulaşılmış demektir.
    private func drainPendingDeletes() async {
        guard !pendingDeleteIds.isEmpty else { return }
        for id in Array(pendingDeleteIds) {
            do {
                try await JournalCloud.shared.delete(id: id)
                pendingDeleteIds.remove(id)
            } catch JournalCloudError.notFound {
                pendingDeleteIds.remove(id)
            } catch {
                // Ağ/hesap sorunu — listede kalır, bir sonraki drainQueue
                // tetiklemesinde tekrar denenir.
            }
        }
        persist()
    }
}
