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

    /// Bekleyen silmeler için geri çekilme durumu. `JournalQueue` kayıt başına
    /// deneme sayar; silmeler için bu kadar hassasiyete gerek yok — tüm
    /// bekleyen silmeleri TEK bir zaman damgasıyla birlikte erteliyoruz.
    /// Aksi halde her drainQueue() tetiklemesinde (açılış, öne gelme, yeni
    /// kayıt, paylaşım değişimi — yani çok sık) tüm silmeler anında yeniden
    /// denenir ve sinyalsiz bölgede CloudKit'i gereksiz yorup rate-limit'e
    /// sürükler.
    private var pendingDeleteAttempts = 0
    private var pendingDeleteLastAttemptAt: Date?

    private var dir: URL {
        let d = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("journal", isDirectory: true)
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }

    private var entriesFile: URL { dir.appendingPathComponent("entries.json") }
    private var queueFile: URL { dir.appendingPathComponent("queue.json") }
    private var pendingDeletesFile: URL { dir.appendingPathComponent("pending-deletes.json") }

    /// `pendingDeletesFile`'ın disk üzerindeki şekli — id listesiyle birlikte
    /// geri çekilme durumu da kalıcı olsun ki uygulama kapanıp açılsa bile
    /// art arda başarısız silmeler yeniden hemen denenmesin.
    private struct PendingDeletesState: Codable {
        var ids: Set<String>
        var attempts: Int
        var lastAttemptAt: Date?
    }

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
           let decoded = try? JSONDecoder().decode(PendingDeletesState.self, from: data) {
            pendingDeleteIds = decoded.ids
            pendingDeleteAttempts = decoded.attempts
            pendingDeleteLastAttemptAt = decoded.lastAttemptAt
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
        let deleteState = PendingDeletesState(
            ids: pendingDeleteIds, attempts: pendingDeleteAttempts, lastAttemptAt: pendingDeleteLastAttemptAt
        )
        if let data = try? JSONEncoder().encode(deleteState) {
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

    /// Fotoğraf uyarısı şeridini kullanıcı elle kapattığında çağrılır.
    /// Önceden yalnızca bir sonraki `add()` çağrısı bu uyarıyı temizliyordu —
    /// kullanıcı uyarıyı okuduktan sonra kapatacak bir yolu yoktu.
    func clearPhotoWarning() {
        photoWarning = nil
    }

    // MARK: - Düzenleme

    @discardableResult
    func add(_ entry: JournalEntry, photos: [Data]) -> JournalEntry {
        var saved = entry
        var names: [String] = []
        var failedPhotoCount = 0
        for (i, data) in photos.enumerated() {
            let name = "\(entry.id)-\(i).jpg"
            do {
                try data.write(to: photoURL(name), options: .atomic)
                names.append(name)
            } catch {
                // Yazılamayan dosyanın adı listeye GİRMEMELİ — aksi halde
                // kayıt var olmayan bir dosyaya işaret eder ve galeri
                // sekmesinde kırık görsel olarak kalır.
                failedPhotoCount += 1
            }
        }
        saved.photoFilenames = names

        // Kısmi başarısızlık da sessiz kalmamalı: 3 fotoğraftan biri
        // yazılamazsa kullanıcı "hepsi eklendi" sanır ve o fotoğrafın sessizce
        // kaybolduğunu asla öğrenemez — kaç tanesinin gittiğini söyle.
        if failedPhotoCount == 0 {
            photoWarning = nil
        } else if names.isEmpty {
            photoWarning = "Fotoğraflar kaydedilemedi — cihaz depolaması dolu olabilir."
        } else {
            photoWarning = "\(failedPhotoCount) fotoğraf kaydedilemedi — cihaz depolaması dolu olabilir."
        }

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
        publishShared()   // paylaşılmış kayıt silindiyse web'den de düşsün
    }

    func setShared(_ entry: JournalEntry, shared: Bool) {
        guard let i = entries.firstIndex(where: { $0.id == entry.id }) else { return }
        entries[i].isShared = shared
        queue.enqueue(entry.id)
        persist()
        Task { await drainQueue() }
        publishShared()
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
        let failedNow = queue.items.filter { $0.state == .failed }.count
        let hasFailed = failedNow > 0
        let hasBackoffPending = queue.items.contains { $0.state != .failed && $0.attempts > 0 }

        if !hasFailed && !hasBackoffPending {
            cloudProblem = nil
        } else if cloudProblem == nil {
            // Bu turda hiçbir gönderim denenmedi (hepsi geri çekilme
            // bekliyor) ya da önceki oturumdan kalan mesaj kalıcı değildi
            // (uygulama yeniden başlatıldı) — kuyrukta yine de sorunlu kayıt
            // var, kullanıcıyı habersiz bırakma.
            //
            // .failed olan kayıtlar için "otomatik olarak tekrar denenecek"
            // demek YALAN olur: nextToSend() .failed durumundaki kaydı bir
            // daha asla seçmez ve enqueue() zaten kuyrukta olan kayıt için
            // no-op'tur — o kayıt otomatik hiçbir zaman gitmez. Kullanıcıya
            // gerçeği söyle ve elle bir çıkış yolu olduğunu belirt
            // (retryFailed()).
            cloudProblem = hasFailed
                ? "iCloud'a gönderilemeyen \(failedNow) kayıt var — otomatik deneme hakları bitti, tekrar denemek için dokunman gerekiyor."
                : "iCloud'a gönderilemeyen kayıtlar var — otomatik olarak tekrar denenecek."
        }
        persist()
    }

    // MARK: - Paylaşılanları web'e yansıt

    /// YALNIZCA isShared=true kayıtlar gider. Gizli kayıt cihazdan çıkmaz.
    func publishShared() {
        guard let url = Config.journalPostURL else { return }
        let shared = entries.filter(\.isShared)

        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime]
        let payload: [String: Any] = [
            "entries": shared.map { e -> [String: Any] in
                var d: [String: Any] = [
                    "id": e.id,
                    "text": e.text,
                    "createdAt": iso.string(from: e.createdAt),
                ]
                if let mood = e.mood { d["mood"] = mood }
                if let stopId = e.stopId { d["stopId"] = stopId }
                return d
            },
        ]

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(Config.livePostSecret, forHTTPHeaderField: "x-live-secret")
        request.timeoutInterval = 12
        request.httpBody = try? JSONSerialization.data(withJSONObject: payload)

        Task { _ = try? await URLSession.shared.data(for: request) }
    }

    /// Azami deneme sayısına ulaşıp `.failed` durumuna düşmüş, bu yüzden
    /// `nextToSend()` tarafından bir daha asla seçilmeyecek kayıtları
    /// yeniden dener. `cloudProblem` bu kayıtlar için "otomatik tekrar
    /// denenecek" diyemediğinden (bu doğru olmazdı), kullanıcıya sunulacak
    /// elle çıkış yolu budur.
    func retryFailed() {
        let failedIds = queue.items.filter { $0.state == .failed }.map { $0.entryId }
        guard !failedIds.isEmpty else { return }
        for id in failedIds {
            // JournalQueue'ya "deneme sayısını sıfırla" diye bir metot
            // eklemeden aynı sonucu elde etmenin yolu: kayıtları kuyruktan
            // tamamen düşürüp (markSynced) sıfır denemeyle yeniden kuyruğa
            // almak (enqueue) — JournalQueue'nun mevcut açık yüzeyiyle.
            queue.markSynced(id)
            queue.enqueue(id)
        }
        persist()
        Task { await drainQueue() }
    }

    /// Bulutta silinmeyi bekleyen kayıtları tekrar dener. `notFound` başarı
    /// sayılır — kayıt zaten sunucuda yok, silme amacına ulaşılmış demektir.
    ///
    /// `drainQueue()` açılışta, öne gelince, kayıt eklenince, paylaşım
    /// değişince — yani çok sık — tetikleniyor. Geri çekilme olmadan burada
    /// TÜM bekleyen silmeleri her seferinde anında yeniden denemek,
    /// sinyalsiz bölgede app'i sık açıp kapatan bir kullanıcıda CloudKit'i
    /// gereksiz yükler ve rate-limit'e sürükleyebilir. Kaydetme tarafındaki
    /// gibi (JournalQueue.backoff) üstel bir geri çekilme uyguluyoruz; ama
    /// silmeler kayıt başına değil TEK bir zaman damgasıyla birlikte
    /// erteleniyor — JournalQueue'ya dokunmadan yeterli basitlikte bir çözüm.
    private func drainPendingDeletes() async {
        guard !pendingDeleteIds.isEmpty else { return }
        if pendingDeleteAttempts > 0, let last = pendingDeleteLastAttemptAt,
           // Geri çekilme süresi sınırlandırılmalı: üst sınır olmadan deneme sayısı
           // arttıkça süre günlere hatta yıllara çıkar (10. denemede ~91 gün,
           // 12. denemede ~4 yıl). Gönderim tarafındaki gibi maxAttempts ile sınırla
           // ki süre ~2 saatte durabilsin.
           Date().timeIntervalSince(last) < JournalQueue.backoff(attempts: min(pendingDeleteAttempts, JournalQueue.maxAttempts)) {
            return
        }

        var anyFailed = false
        for id in Array(pendingDeleteIds) {
            do {
                try await JournalCloud.shared.delete(id: id)
                pendingDeleteIds.remove(id)
            } catch JournalCloudError.notFound {
                pendingDeleteIds.remove(id)
            } catch {
                // Ağ/hesap sorunu — listede kalır, geri çekilme süresi
                // dolunca bir sonraki drainQueue tetiklemesinde tekrar
                // denenir.
                anyFailed = true
            }
        }
        // Tüm kalan silmeler bu turda başarılıysa (anyFailed false) geri
        // çekilmeyi sıfırla; en az biri hâlâ başarısızsa süreyi uzat.
        pendingDeleteLastAttemptAt = Date()
        pendingDeleteAttempts = anyFailed ? pendingDeleteAttempts + 1 : 0
        persist()
    }
}
