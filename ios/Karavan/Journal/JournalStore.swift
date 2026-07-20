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

    /// Web'e (site) paylaşım yayınının kalıcı durumu. `publishShared()` daha
    /// önce ateşle-unut çalışıyordu: `Task { _ = try? await ... }` — ağ hatası
    /// sessizce yutuluyor, tekrar deneme YOKTU. Sınırda sinyal zayıfken
    /// kullanıcı bir kaydın paylaşımını kaldırırsa (ya da kaydı silerse) ve
    /// POST zaman aşımına uğrarsa, hiçbir sonraki açılış/öne gelme/senkron bunu
    /// tekrar denemiyordu — kullanıcı paylaşımı kaldırdığını sanırken metin
    /// herkese açık web sitesinde kalmaya devam ediyordu (gizlilik sorunu).
    /// Bu bayrak diske yazıldığı için uygulama kapanıp açılsa bile "bekleyen
    /// bir yayın var" bilgisi kaybolmaz ve drainQueue() üzerinden yeniden denenir.
    private var sharePublishPending = false
    /// Silme kuyruğundaki gibi (`pendingDeleteAttempts`) TEK bir geri çekilme
    /// zamanlayıcısı: yayın kayıt başına değil, "paylaşılanlar listesi"
    /// bütünü için tek seferde gönderiliyor.
    private var sharePublishAttempts = 0
    private var sharePublishLastAttemptAt: Date?

    /// `mergeFromCloud()` için bellek-içi (KALICI OLMAYAN) son BAŞARILI çekim
    /// zamanı. `drainQueue()` çok sık tetikleniyor: her kayıt eklemede, silmede,
    /// paylaşım değişiminde, uygulama açılışında, her öne gelmede. Bunun
    /// sonunda koşulsuz tam bir CKQuery (`fetchAll()`) atmak — kullanıcı bir
    /// oturumda birkaç kayıt eklerse aynı dakikada birkaç kez tüm tabloyu
    /// sorgulamak demek. `drainPendingDeletes()`/`attemptPublishShared()`
    /// bu tür sık tetiklenme riskini bilinçle geri çekilmeyle önlüyor;
    /// `mergeFromCloud` bu özenden yoksundu. nil'den başlaması (ilk merge
    /// hiç yaşanmamış) uygulama açılışında ilk merge'ün her zaman çalışmasını
    /// sağlar; kalıcı yapmaya gerek yok — her açılışta bir kez taze çekmek
    /// zaten makul.
    private var lastCloudMergeAt: Date?
    /// Minimum merge aralığı: zayıf sinyalli sınır bölgesinde sık tetiklenen
    /// drainQueue()'nun her seferinde tam tabloyu sorgulaması hem gereksiz
    /// pil/veri tüketir hem de CloudKit rate-limit riskini artırır.
    private static let cloudMergeMinInterval: TimeInterval = 5 * 60

    private var dir: URL {
        let d = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("journal", isDirectory: true)
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }

    private var entriesFile: URL { dir.appendingPathComponent("entries.json") }
    private var queueFile: URL { dir.appendingPathComponent("queue.json") }
    private var pendingDeletesFile: URL { dir.appendingPathComponent("pending-deletes.json") }
    private var sharePublishFile: URL { dir.appendingPathComponent("share-publish.json") }

    /// `pendingDeletesFile`'ın disk üzerindeki şekli — id listesiyle birlikte
    /// geri çekilme durumu da kalıcı olsun ki uygulama kapanıp açılsa bile
    /// art arda başarısız silmeler yeniden hemen denenmesin.
    private struct PendingDeletesState: Codable {
        var ids: Set<String>
        var attempts: Int
        var lastAttemptAt: Date?
    }

    /// `sharePublishFile`'ın disk üzerindeki şekli — bkz. `sharePublishPending`.
    private struct SharePublishState: Codable {
        var pending: Bool
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
        if let data = try? Data(contentsOf: sharePublishFile),
           let decoded = try? JSONDecoder().decode(SharePublishState.self, from: data) {
            sharePublishPending = decoded.pending
            sharePublishAttempts = decoded.attempts
            sharePublishLastAttemptAt = decoded.lastAttemptAt
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
        let publishState = SharePublishState(
            pending: sharePublishPending, attempts: sharePublishAttempts, lastAttemptAt: sharePublishLastAttemptAt
        )
        if let data = try? JSONEncoder().encode(publishState) {
            try? data.write(to: sharePublishFile, options: .atomic)
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
        // Web yayını CloudKit'ten tamamen bağımsız bir HTTP çağrısıdır —
        // iCloud oturumu kapalı/kısıtlı olsa bile bekleyen bir paylaşım
        // yayını varsa denenmeli. Bu satırı aşağıdaki iCloud guard'ından
        // ÖNCEYE koyuyoruz; aksi halde iCloud'a girmemiş bir cihazda web'de
        // unutulmuş bir paylaşım hiçbir zaman düzelmezdi.
        await attemptPublishShared()

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

        // Yazma tarafı (kuyruk boşaltma) burada bitti — okuma tarafını da
        // çalıştır. Tasarım "CloudKit kaynak, yerel önce" diyordu ama fetchAll()
        // hiç çağrılmıyordu: aynı iCloud hesabındaki iPhone/iPad günlüğü
        // paylaşmıyordu, uygulama silinip kurulunca cihazdaki kayıtlar
        // görünmüyordu (CloudKit'te dururken). drainQueue() açılışta ve öne
        // gelince zaten tetiklendiği için ayrı bir "açılış" kancasına gerek yok.
        await mergeFromCloud()
    }

    /// CloudKit'teki kayıtları yerel `entries` ile birleştirir (okuma tarafı).
    /// Çakışmada YEREL kazanır: kullanıcının bu cihazda henüz senkronlanmamış
    /// bir düzenlemesi, başka cihazdan/CloudKit'ten gelen eski bir kopya
    /// tarafından ASLA ezilmez — yalnızca yerelde hiç olmayan uzak kayıtlar
    /// eklenir. Bu yüzden kuyrukta gönderilmeyi bekleyen yerel kayıtlar da
    /// (zaten `entries` içinde id'leriyle var oldukları için) dokunulmadan kalır.
    ///
    /// `pendingDeleteIds`'teki kayıtlar bilerek dışlanır: aksi halde kullanıcının
    /// az önce sildiği ama CloudKit'e silme isteği henüz ulaşmamış bir kayıt,
    /// bu fetch ile geri dirilirdi.
    ///
    /// Hesap yoksa/ağ yoksa sessizce geç — mevcut yerel veri olduğu gibi kalır.
    ///
    /// Debounce: `drainQueue()` çok sık tetiklendiği (her ekleme/silme/paylaşım
    /// değişimi/açılış/öne gelme) ve tetikleyen sinyal zayıf olduğu (CloudKit'in
    /// gerçekten yeni veri olup olmadığını bilmiyoruz) için, son BAŞARILI
    /// merge'ün üstünden `cloudMergeMinInterval` geçmediyse yeni bir fetch
    /// atmadan sessizce geç. Aksi halde sık tetiklenmede CloudKit gereksiz
    /// yorulur ve rate-limit'e sürüklenebilir (bkz. `drainPendingDeletes`/
    /// `attemptPublishShared`'daki aynı gerekçe). Uygulama açılışında
    /// `lastCloudMergeAt` henüz nil olduğu için ilk merge her zaman çalışır.
    private func mergeFromCloud() async {
        guard cloudAvailable else { return }
        if let last = lastCloudMergeAt, Date().timeIntervalSince(last) < Self.cloudMergeMinInterval {
            return
        }

        let remote: [JournalEntry]
        do {
            remote = try await JournalCloud.shared.fetchAll()
        } catch {
            return
        }
        // Zaman damgası yalnızca BAŞARILI bir çekimden sonra güncellenir —
        // aksi halde geçici bir ağ hatası, kullanıcıyı sonraki tetiklemelerde
        // (öne gelme vb.) gereksiz yere `cloudMergeMinInterval` kadar
        // bekletirdi.
        lastCloudMergeAt = Date()

        let localIds = Set(entries.map(\.id))
        let newFromRemote = remote.filter { !localIds.contains($0.id) && !pendingDeleteIds.contains($0.id) }
        guard !newFromRemote.isEmpty else { return }

        entries.append(contentsOf: newFromRemote)
        entries.sort { $0.createdAt > $1.createdAt }
        persist()
    }

    // MARK: - Paylaşılanları web'e yansıt

    /// YALNIZCA isShared=true kayıtlar gider. Gizli kayıt cihazdan çıkmaz.
    ///
    /// Önceden burada doğrudan ateşle-unut bir `Task { _ = try? await ... }`
    /// vardı: ağ hatası sessizce yutuluyor, tekrar deneme yoktu. Şimdi önce
    /// "bekleyen bir yayın var" bayrağını KALICI olarak (diske) işaretliyoruz,
    /// sonra deniyoruz — POST şimdi başarısız olsa bile bayrak diskte kalır ve
    /// `drainQueue()` her tetiklendiğinde (açılış, öne gelme, senkron) tekrar
    /// denenir. Aksi halde kullanıcı paylaşımı kaldırdığını/kaydı sildiğini
    /// sanırken metin herkese açık web sitesinde kalmaya devam edebilirdi.
    func publishShared() {
        guard Config.journalPostURL != nil else { return }
        sharePublishPending = true
        persist()
        Task { await attemptPublishShared() }
    }

    /// Bekleyen web yayınını, geri çekilmeye tabi olarak dener. Gövde HER
    /// SEFERİNDE bu anki `entries`'ten yeniden üretilir — bayat bir yükü
    /// tekrar göndermek (ör. arada tekrar gizlenmiş bir kaydı hâlâ pakette
    /// taşımak) gizlilik ihlalini geri getirebilir.
    ///
    /// `drainQueue()` açılışta, öne gelince, kayıt eklenince, paylaşım
    /// değişince — yani çok sık — tetikleniyor. `drainPendingDeletes()`
    /// deki gibi geri çekilme süresini `JournalQueue.backoff` ile hesaplayıp
    /// `maxAttempts` ile ÜST SINIRLIYORUZ — aksi halde deneme sayısı arttıkça
    /// süre günlere, hatta yıllara çıkar (deponun geçmişinde üst sınırsız
    /// geri çekilme 12. denemede ~4 yıla çıkmıştı).
    private func attemptPublishShared() async {
        guard sharePublishPending, let url = Config.journalPostURL else { return }

        if sharePublishAttempts > 0, let last = sharePublishLastAttemptAt,
           Date().timeIntervalSince(last) < JournalQueue.backoff(attempts: min(sharePublishAttempts, JournalQueue.maxAttempts)) {
            return
        }

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

        sharePublishLastAttemptAt = Date()

        var succeeded = false
        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            if let http = response as? HTTPURLResponse {
                succeeded = (200...299).contains(http.statusCode)
            } else {
                succeeded = true   // HTTPURLResponse olmayan ortamlarda (ör. test) varsayılan başarı
            }
        } catch {
            succeeded = false   // ağ hatası / zaman aşımı — bayrak KALDIRILMAZ, bir sonraki tetiklemede tekrar denenir
        }

        if succeeded {
            sharePublishPending = false
            sharePublishAttempts = 0
        } else {
            sharePublishAttempts += 1
        }
        persist()
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
