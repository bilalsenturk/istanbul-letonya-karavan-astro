import CloudKit
import Foundation
import os

enum JournalCloudError: Error {
    case accountUnavailable
    case quotaExceeded
    case network
    /// Kayıt sunucuda yok (silinmiş ya da hiç var olmamış). save()'de bu
    /// durum hata SAYILMAZ — yeni kayıt olarak devam edilir; bu case
    /// delete/fetch gibi "kaydın var olmasını bekleyen" çağrılar için var.
    case notFound
    /// `mapError`'ın tanımadığı bir CKError. Ham CKError'ı çağırana sızdırmak
    /// yerine tek bir durumda toplanır; orijinal hata teşhis için saklanır.
    case unexpected(Error)
    /// Kayıt sunucuda mezar taşı (başka cihazda silinmiş) — save() bunun
    /// üzerine aktif kayıt yazmayı reddeder; aksi halde silinmiş kayıt
    /// çevrimdışı kalmış bir cihazın kuyruğundan geri dirilirdi. Yalnızca
    /// kullanıcı kaydı BİLEREK yeniden oluşturduğunda (allowResurrect) aşılır.
    case tombstoned
}

private let logger = Logger(subsystem: "com.bilalsenturk.kuzey", category: "JournalCloud")

/// drainQueue'un hesap kapısı için üç değerli durum: `.available` hesap
/// var; `.noAccount` oturum gerçekten yok/kısıtlı; `.unknown` durum
/// öğrenilemedi (geçici ağ hatası) — bu "hesap yok" DEMEK DEĞİL, çevrimdışı
/// sayılmalı ki bekleyen kayıtlar "iCloud oturumu kapalı" diye yanlış
/// etiketlenmesin.
enum JournalAccountState {
    case available, noAccount, unknown
}

// CloudKit ÖZEL veritabanı — kayıtlar yalnızca sahibinin iCloud hesabında.
// Paylaşım burada YOK: paylaşılan kayıtlar ayrı bir yoldan (Vercel aynası) gider.
actor JournalCloud {
    static let shared = JournalCloud()

    private let container = CKContainer(identifier: "iCloud.com.bilalsenturk.kuzey")
    private var db: CKDatabase { container.privateCloudDatabase }

    private static let recordType = "JournalEntry"
    private static let photoNamesKey = "photoNames"
    /// Mezar taşı bayrağı: başka cihazda silinen kayıt fiziksel olarak
    /// silinmek yerine bu bayrakla işaretlenir ki merge sırasında öbür
    /// cihazlar da yerel kopyayı düşürebilsin (fiziksel silme cihazlar
    /// arası silmeyi hiç yayamazdı).
    private static let deletedKey = "deleted"

    /// Hesap durumunu çeker; `accountStatus()` başarısız olursa (ör. ağ
    /// sorunu) durumu değil hatayı döndürür. Böylece "hesap gerçekten yok"
    /// ile "durumu öğrenemedik" birbirine karışmaz.
    private func resolveAccountStatus() async -> (status: CKAccountStatus?, error: Error?) {
        do {
            let status = try await container.accountStatus()
            return (status, nil)
        } catch {
            return (nil, error)
        }
    }

    /// Basit ikili kontrol — yalnızca UI'da hızlı bir ipucu için (ör. günlük
    /// sekmesinde "iCloud kapalı" rozeti). Ağ hatasını "hesap yok" ile
    /// karıştırmadan asıl hata sınıflandırması gereken yerlerde (save/
    /// fetchAll/delete) bunun yerine `ensureAccountAvailable()` kullanılır.
    func accountAvailable() async -> Bool {
        let (status, _) = await resolveAccountStatus()
        return status == .available
    }

    /// `accountAvailable()`'ın üç değerli hâli: ağ hatasında false dönen
    /// ikili kontrol, geçici çevrimdışılığı "hesap yok" ile karıştırıyordu.
    /// drainQueue bu ayrımla yalnızca GERÇEK hesap yokluğunda "oturum
    /// kapalı" mesajı gösterir.
    func accountState() async -> JournalAccountState {
        let (status, _) = await resolveAccountStatus()
        guard let status else { return .unknown }
        return status == .available ? .available : .noAccount
    }

    /// save/fetchAll/delete'in ortak ön koşulu. Hesap gerçekten yoksa
    /// `.accountUnavailable`, durum öğrenilemediyse (ağ vb.) altta yatan
    /// hatayı doğru şekilde eşleyerek fırlatır — kullanıcıya "hesabın yok"
    /// yerine "bağlantı sorunu" gibi doğru bir mesaj gitsin diye.
    private func ensureAccountAvailable() async throws {
        let (status, error) = await resolveAccountStatus()
        if let status {
            guard status == .available else { throw JournalCloudError.accountUnavailable }
            return
        }
        if let ckError = error as? CKError {
            throw Self.mapError(ckError)
        }
        throw JournalCloudError.network
    }

    /// `allowResurrect`: kayıt sunucuda mezar taşıysa (başka cihazda
    /// silinmiş) save normalde `.tombstoned` fırlatır — silinmiş bir kaydın
    /// çevrimdışı kalmış bir cihazın kuyruğundan geri dirilmesini engeller.
    /// Kullanıcı aynı id ile kaydı BİLEREK yeniden oluşturuyorsa (yeni kayıt
    /// ekleme yolu değil, kuyruk dışı bilinçli bir çağrı) true geçilir.
    func save(_ entry: JournalEntry, photoURLs: [URL], allowResurrect: Bool = false) async throws {
        try await ensureAccountAvailable()

        let recordID = CKRecord.ID(recordName: entry.id)
        let record: CKRecord
        do {
            // Var olan kaydı sunucudan çekip onun change-tag'i üzerine
            // yazıyoruz. Sıfırdan CKRecord kurup aynı id ile ikinci kez
            // save etmek CloudKit'te .serverRecordChanged fırlatır — ve bu
            // kesinlikle olacak: bir sonraki görevde kayıt paylaşılıp/
            // paylaşımı kaldırılınca aynı kayıt tekrar save edilecek.
            record = try await db.record(for: recordID)
        } catch let error as CKError where error.code == .unknownItem {
            // Sunucuda henüz yok — ilk kayıt, normal durum, hata değil.
            record = CKRecord(recordType: Self.recordType, recordID: recordID)
        } catch let error as CKError {
            throw Self.mapError(error)
        }

        // Mezar taşı dirilmesin: bu kayıt başka bir cihazda silindi. Kuyruk
        // gönderimi (allowResurrect=false) bayrağı ezerek kaydı tüm
        // cihazlara geri getirirdi — reddet; çağıran kuyruktan düşürür.
        if !allowResurrect, (record[Self.deletedKey] as? Int ?? 0) == 1 {
            throw JournalCloudError.tombstoned
        }

        record["text"] = entry.text as NSString
        record["createdAt"] = entry.createdAt as NSDate
        record["isShared"] = (entry.isShared ? 1 : 0) as NSNumber
        // Optional alanlar nil verildiğinde CKRecord'daki değeri temizler —
        // artık var olan kaydı güncelleyebildiğimiz için bu önemli: örneğin
        // konum sonradan kaldırılırsa sunucuda eski değer asılı kalmamalı.
        record["latitude"] = entry.latitude as NSNumber?
        record["longitude"] = entry.longitude as NSNumber?
        record["stopId"] = entry.stopId as NSString?
        record["mood"] = entry.mood as NSString?
        // Aktif bir kayıt mezar taşı DEĞİLDİR — delete(id:) aynı kayıt
        // tipinde silindi bayraklı bir kayıt yazar (bkz. deletedKey); aynı
        // id ile yeniden kaydetme durumunda bayrağın temizlenmesi gerekir.
        record[Self.deletedKey] = 0 as NSNumber
        // Gerçek dosya adları ayrı bir alanda saklanır — CKAsset'in indirme
        // sırasında ürettiği geçici önbellek dosya adına GÜVENİLMEZ (bkz.
        // entry(from:)). Fotoğraf yüklenmese bile isimler cihazda zaten
        // biliniyor, o yüzden photoURLs'den bağımsız yazılır.
        record[Self.photoNamesKey] = entry.photoFilenames as NSArray
        if !photoURLs.isEmpty {
            record["photos"] = photoURLs.map { CKAsset(fileURL: $0) }
        }

        do {
            _ = try await db.save(record)
        } catch let error as CKError {
            throw Self.mapError(error)
        }
    }

    /// CloudKit sunucudan tüm sayfaları TOPLAYARAK döner. `db.records(matching:)`
    /// tüm sonuçları otomatik sayfalamaz — özellikle CKAsset (fotoğraf)
    /// yüklü kayıtlarda sunucu sayfayı erken böler ve dönen `queryCursor` ile
    /// `db.records(continuingMatchFrom:)` ile devam edilmesi gerekir. Bu cursor
    /// önceden yok sayılıyordu; adı "fetchAll" olsa da yalnızca ilk sayfayı
    /// çekiyordu — birden çok sayfa varsa (ör. çok sayıda fotoğraflı kayıt)
    /// başka bir cihaz günlüğün yalnızca bir kısmını görürdü.
    ///
    /// `maxPages` sonsuz döngüye karşı bir üst sınırdır (hatalı/beklenmedik
    /// bir durumda sunucu hep aynı cursor'ı döndürseydi bu döngü asla
    /// bitmezdi); sınıra ulaşılırsa kalan sayfalar loglanıp atlanır, elde
    /// olanla devam edilir.
    ///
    /// Dönüşte `deletedIds`: başka cihazda silinip mezar taşı bırakılmış
    /// kayıt id'leri (bkz. `delete(id:)`). Bunlar entry'ye dönüştürülmez;
    /// çağıran yerel kopyaları düşürmek için kullanır.
    func fetchAll() async throws -> (entries: [JournalEntry], deletedIds: Set<String>) {
        try await ensureAccountAvailable()

        let query = CKQuery(recordType: Self.recordType, predicate: NSPredicate(value: true))
        query.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: false)]

        // Bozuk/eşlenemeyen tek bir kayıt yüzünden kullanıcı günlüğünün
        // bir kısmını SESSİZCE kaybetmesin diye düşürülen her kayıt
        // loglanır ve toplam sayı uyarı olarak basılır.
        var droppedCount = 0
        var entries: [JournalEntry] = []
        var deletedIds: Set<String> = []
        var cursor: CKQueryOperation.Cursor?
        var pageIndex = 0
        let maxPages = 200

        func consume(_ matchResults: [(CKRecord.ID, Result<CKRecord, Error>)]) {
            for (recordID, result) in matchResults {
                switch result {
                case .success(let record):
                    if (record[Self.deletedKey] as? Int ?? 0) == 1 {
                        // Mezar taşı — entry değil; çağıran bu id'nin yerel
                        // kopyasını düşürecek.
                        deletedIds.insert(recordID.recordName)
                    } else if let entry = Self.entry(from: record) {
                        entries.append(entry)
                    } else {
                        droppedCount += 1
                        logger.error("Günlük kaydı ayrıştırılamadı, atlandı: \(recordID.recordName, privacy: .public)")
                    }
                case .failure(let error):
                    droppedCount += 1
                    logger.error("Günlük kaydı çekilemedi, atlandı: \(recordID.recordName, privacy: .public) — \(String(describing: error), privacy: .public)")
                }
            }
        }

        do {
            repeat {
                let matchResults: [(CKRecord.ID, Result<CKRecord, Error>)]
                let nextCursor: CKQueryOperation.Cursor?
                if let cursor {
                    (matchResults, nextCursor) = try await db.records(continuingMatchFrom: cursor)
                } else {
                    (matchResults, nextCursor) = try await db.records(matching: query)
                }
                consume(matchResults)
                cursor = nextCursor
                pageIndex += 1

                if cursor != nil, pageIndex >= maxPages {
                    logger.warning("fetchAll: sayfa sınırına (\(maxPages, privacy: .public)) ulaşıldı, kalan sayfalar atlanıyor")
                    cursor = nil
                }
            } while cursor != nil
        } catch let error as CKError {
            throw Self.mapError(error)
        }

        if droppedCount > 0 {
            logger.warning("fetchAll: \(droppedCount, privacy: .public) kayıt düşürüldü")
        }
        return (entries, deletedIds)
    }

    func delete(id: String) async throws {
        // save/fetchAll ile aynı hesap ve hata sözleşmesi: silme de sessizce
        // yarım kalmamalı — çağıran taraf her zaman aynı hataları yakalayabilmeli.
        try await ensureAccountAvailable()

        // Fiziksel silme YERİNE mezar taşı yazılır: kayıt CloudKit'ten
        // bütünüyle kaldırılırsa başka cihazlar silindiğini asla öğrenemez
        // (fetchAll yalnızca var olan kayıtları görür) ve yerel kopyaları
        // sonsuza dek kalırdı. Aynı kayıt tipinde, silindi bayraklı minimal
        // bir kayıt yazılır; merge sırasında öbür cihazlar bu id'yi yerelden
        // düşürür. Kayıt zaten yoksa da aynı taş yazılır — notFound burada
        // hata sayılmaz (silme amacına zaten ulaşılmıştır).
        let recordID = CKRecord.ID(recordName: id)
        let tombstone: CKRecord
        do {
            tombstone = try await db.record(for: recordID)
        } catch let error as CKError where error.code == .unknownItem {
            tombstone = CKRecord(recordType: Self.recordType, recordID: recordID)
        } catch let error as CKError {
            throw Self.mapError(error)
        }
        tombstone[Self.deletedKey] = 1 as NSNumber
        // fetchAll sorgusu createdAt'e göre sıralıyor; alanı olmayan kayıt
        // sıralamada sorun çıkarmasın diye mezar taşına da bir tarih konur.
        if tombstone["createdAt"] == nil {
            tombstone["createdAt"] = Date() as NSDate
        }
        // Mezar taşı yalnızca "bu id silindi" bilgisini taşımalı — var olan
        // kaydın üzerine yazıldığı için kullanıcı içeriği (metin, konum, ruh
        // hâli) aksi halde sunucuda SONSUZA DEK kalırdı; silme niyetiyle
        // bağdaşmaz. id + createdAt + deleted dışındaki her şey temizlenir.
        for key in ["text", "latitude", "longitude", "stopId", "mood", "isShared"] {
            tombstone[key] = nil
        }
        // Fotoğraf asset'leri artık gereksiz — sunucuda yer kaplamasın.
        tombstone["photos"] = nil
        tombstone[Self.photoNamesKey] = nil

        do {
            _ = try await db.save(tombstone)
        } catch let error as CKError {
            throw Self.mapError(error)
        }
    }

    /// Başka cihazdan gelen bir kaydın fotoğraflarını (CKAsset) yerel
    /// dizine indirir. `fetchAll` kayıtla yalnızca alanları getirir — dosya
    /// ADLARI gelir ama asset içerikleri bu cihazda hiçbir dosyaya karşılık
    /// gelmez; indirilmezse küçük resim sonsuza dek yükleniyor gösterirdi.
    /// Tek bir fotoğraf inmezse kayıt yine de kalır, yalnızca o dosya eksik
    /// kalır (küçük resim görünümü yer tutucuya düşer).
    func downloadPhotos(entryId: String, to directory: URL) async throws {
        try await ensureAccountAvailable()

        let record: CKRecord
        do {
            record = try await db.record(for: CKRecord.ID(recordName: entryId))
        } catch let error as CKError {
            throw Self.mapError(error)
        }

        let names = record[Self.photoNamesKey] as? [String] ?? []
        let assets = record["photos"] as? [CKAsset] ?? []
        // zip(names, assets) kısa olana kadar eşleştirir — sayılar tutmazsa
        // eşleşmeyen fotoğraflar SESSİZCE düşerdi ve hiçbir yeniden deneme
        // tetiklenmezdi. Uyuşmazlığı ve eşleşmeyen adları mutlaka logla;
        // yeniden deneme tarafı JournalStore.mergeFromCloud'dadır (dosyası
        // eksik kayıtlar her merge'de tekrar indirilmeye kuyrukla girer).
        if names.count != assets.count {
            logger.error("Fotoğraf ad/asset sayısı uyuşmuyor: \(entryId, privacy: .public) — \(names.count, privacy: .public) ad, \(assets.count, privacy: .public) asset")
            for name in names.dropFirst(assets.count) {
                logger.error("Eşleşen asset yok, fotoğraf atlandı: \(entryId, privacy: .public)/\(name, privacy: .public)")
            }
        }
        for (name, asset) in zip(names, assets) {
            guard let fileURL = asset.fileURL,
                  let data = try? Data(contentsOf: fileURL) else {
                logger.error("Fotoğraf indirilemedi, atlandı: \(entryId, privacy: .public)/\(name, privacy: .public)")
                continue
            }
            let target = directory.appendingPathComponent(name)
            do {
                try data.write(to: target, options: .atomic)
            } catch {
                logger.error("Fotoğraf diske yazılamadı: \(entryId, privacy: .public)/\(name, privacy: .public) — \(String(describing: error), privacy: .public)")
            }
        }
    }

    private static func mapError(_ error: CKError) -> Error {
        switch error.code {
        case .quotaExceeded:
            return JournalCloudError.quotaExceeded
        case .networkUnavailable, .networkFailure, .serviceUnavailable,
             .requestRateLimited, .zoneBusy, .limitExceeded,
             .resultsTruncated, .serverResponseLost, .accountTemporarilyUnavailable:
            // Geçici/yeniden denenebilir durumlar — kuyruk zaten backoff ile
            // tekrar dener, çağırana "ağ" olarak tek bir çatı altında gider.
            return JournalCloudError.network
        case .notAuthenticated:
            return JournalCloudError.accountUnavailable
        case .unknownItem:
            return JournalCloudError.notFound
        default:
            // Tanınmayan bir CKError — ham sızdırmak yerine tek bir
            // durumda topla, orijinal hatayı teşhis için sakla.
            return JournalCloudError.unexpected(error)
        }
    }

    private static func entry(from record: CKRecord) -> JournalEntry? {
        guard let text = record["text"] as? String,
              let createdAt = record["createdAt"] as? Date else { return nil }
        // Dosya adları CKAsset'ten DEĞİL, ayrı photoNames alanından okunur:
        // CKAsset.fileURL indirilen kaydın geçici önbellek yolunu gösterir,
        // cihazdaki gerçek dosya adıyla hiçbir ilgisi yoktur — başka bir
        // cihazdan çekildiğinde bu ad hiçbir dosyaya karşılık gelmez.
        let photoNames = record[photoNamesKey] as? [String] ?? []
        return JournalEntry(
            id: record.recordID.recordName,
            text: text,
            createdAt: createdAt,
            latitude: record["latitude"] as? Double,
            longitude: record["longitude"] as? Double,
            stopId: record["stopId"] as? String,
            mood: record["mood"] as? String,
            photoFilenames: photoNames,
            isShared: (record["isShared"] as? Int ?? 0) == 1
        )
    }
}
