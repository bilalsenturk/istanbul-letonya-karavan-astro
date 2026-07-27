import AVFoundation
import Foundation

/// Letonca derslerinin ses kliplerini indirir, diskte tutar ve çalar.
///
/// `Learning/` altındaki diğer dosyalar saf motordur (yalnızca `Foundation`) ve
/// `ios/Tests/run-latvian-check.sh` tarafından `swiftc` ile derlenir. Bu dosya
/// arayüz sınırıdır: `AVFoundation` kullanır, `@MainActor`'dır ve o kaynak
/// listesine EKLENMEZ — eklenirse motor kontrolü derlenemez.
///
/// Temel tasarım kararı: çalma anında hiçbir ses üretilmez. Klipler derleme
/// zamanında üretilip statik dosya olarak sunuluyor; uygulama bir kez indirip
/// hep diskten çalıyor. Eski sürümün "Dinle düğmesi sessiz kalıyor" hatası tam
/// olarak bunun tersinden geliyordu: çalma anında canlı bir TTS isteği atılıyor,
/// istek başarısız olunca çalar tek kelime etmeden ölüyordu.
@MainActor
final class LatvianAudioStore: NSObject, ObservableObject, AVAudioPlayerDelegate {
    /// Diskte tam ve doğrulanmış olarak duran klip kimlikleri.
    /// `LatvianExerciseFactory` bunu `availableAudio` olarak alır: eksik klip
    /// bozuk soru değil, o kelime için daha az soru türü demektir. Bu yüzden
    /// buraya yalnızca baştan sona yazılmış dosyalar girer.
    @Published private(set) var downloadedAudioIds: Set<String> = []

    /// 0...1 — paketteki kliplerin kaçının hazır olduğu. Diskteki gerçekten
    /// türetildiği için indirme kesilip sürdürüldüğünde geri gitmez ve 1'i aşmaz.
    @Published private(set) var downloadProgress: Double = 0

    @Published private(set) var isDownloading = false

    /// Kullanıcıya gösterilecek son hata (Türkçe). Başarılı bir eşitleme veya
    /// çalma bunu temizler.
    @Published private(set) var lastError: String?

    /// Kliplerin diskte kapladığı toplam yer. Ayarlar ekranı bunu gösterebilir.
    @Published private(set) var storedByteCount: Int64 = 0

    /// Şu an çalan klip — arayüz hoparlör simgesini canlandırabilsin diye.
    @Published private(set) var playingAudioId: String?

    // `nonisolated`: indirme işini yapan yardımcılar ana aktörün dışında çalışıyor.
    private nonisolated static let directoryName = "letonca-ses"
    private nonisolated static let fileExtension = "mp3"
    /// Telefon bağlantısında 412 isteği sıraya dizmek dakikalar sürer; altı
    /// paralel istek hem hızlı hem de sunucuyu zorlamayacak kadar ölçülü.
    private nonisolated static let maxConcurrentDownloads = 6
    /// Paketteki en küçük klip 3,8 KB. Bunun altındaki her şey (hata sayfası,
    /// yarım gövde) klip değildir.
    private nonisolated static let minimumClipBytes = 512

    private let directory: URL
    private let session: URLSession

    private var activeSync: Task<Void, Never>?
    /// Kimlik → dosyanın bayt sayısı. `downloadedAudioIds` ve `storedByteCount`
    /// yalnızca buradan güncellenir; böylece bir dosya arkamızdan değişse bile
    /// sayaç kaymaz (her zaman "eklerken kaydettiğimiz" kadar düşülür).
    private var clipBytes: [String: Int64] = [:]
    /// Son eşitlenen paketin klip kimlikleri; ilerleme oranı ve artık paket
    /// dışında kalan eski kliplerin temizliği buna göre hesaplanır.
    private var manifestIds: Set<String> = []
    /// Bozuk çıkan bir klibi kendiliğinden yeniden indirebilmek için saklanır.
    private var lastPack: LatvianPack?

    private var player: AVAudioPlayer?
    private var sessionReady = false

    override init() {
        directory = Self.makeDirectory()
        session = Self.makeSession()
        super.init()
        rescanDisk()
    }

    // MARK: - Sorgular

    /// Klip diskte hazırsa dosya adresi, değilse `nil`.
    /// Küme diskin doğrusu olarak tutulduğu için dosya sistemine gitmez.
    func localURL(for audioId: String) -> URL? {
        guard downloadedAudioIds.contains(audioId) else { return nil }
        return fileURL(for: audioId)
    }

    /// "5,2 MB" gibi yerel biçimli boyut.
    var storedSizeText: String {
        ByteCountFormatter.string(fromByteCount: storedByteCount, countStyle: .file)
    }

    /// Arayüzdeki hata şeridini kapatmak için.
    func dismissError() { lastError = nil }

    // MARK: - İndirme

    /// Pakette olup diskte olmayan klipleri indirir.
    ///
    /// - Yeniden çağrılabilir: eşitleme sürerken çağrılırsa ikinci bir tur
    ///   başlatmaz, sürenin bitmesini bekler. Her şey yerindeyse tek bir ağ
    ///   isteği bile atmadan döner.
    /// - Kesilebilir: her dosya diske atomik yazılır, yarım dosya "var"
    ///   sayılmaz. Yarıda kalan bir indirme sonraki çağrıda kaldığı yerden sürer.
    /// - Çağıran görev iptal olsa da (ekran kapansa da) indirme sürer; ders
    ///   ekranından çıkmak 400 dosyalık indirmeyi baştan başlatmamalı.
    func syncMissing(pack: LatvianPack) async {
        if let active = activeSync {
            await active.value
            return
        }
        let task = Task { [weak self] in
            guard let self else { return }
            await self.performSync(pack: pack)
        }
        activeSync = task
        await task.value
        activeSync = nil
    }

    private func performSync(pack: LatvianPack) async {
        lastPack = pack
        let ordered = Self.orderedAudioIds(in: pack)
        manifestIds = Set(ordered)
        pruneUnreferenced()
        refreshProgress()

        let missing = ordered.filter { !downloadedAudioIds.contains($0) }
        guard !missing.isEmpty else {
            lastError = nil
            return
        }

        isDownloading = true
        lastError = nil

        var failed = await download(ids: missing, pack: pack)
        // Tek bir yeniden deneme: mobil bağlantıda tek tük istek düşer, ikinci
        // turda genelde geçer. Hepsi düştüyse bağlantı yoktur; 412 isteği ikinci
        // kez denemenin anlamı yok.
        if !failed.isEmpty, failed.count < missing.count {
            failed = await download(ids: failed, pack: pack)
        }

        isDownloading = false
        lastError = failureMessage()
    }

    /// Mesaj denenen sayıdan değil, diskteki gerçekten üretilir: kullanıcıyı
    /// ilgilendiren "kaç ses hâlâ yok", "bu turda kaç istek düştü" değil.
    private func failureMessage() -> String? {
        let stillMissing = manifestIds.subtracting(downloadedAudioIds).count
        guard stillMissing > 0 else { return nil }
        guard !downloadedAudioIds.isEmpty else {
            return "Ses dosyaları inemedi. İnternet bağlantını kontrol edip tekrar dene."
        }
        return "\(stillMissing) ses inemedi; bağlantın olduğunda yeniden denenecek. "
            + "O kelimeler şimdilik dinleme sorusu olmadan çalışılır."
    }

    /// Verilen kimlikleri sınırlı paralellikle indirir, inemeyenleri döndürür.
    private func download(ids: [String], pack: LatvianPack) async -> [String] {
        let directory = self.directory
        let session = self.session
        var pending = ids.makeIterator()
        var failed: [String] = []

        await withTaskGroup(of: DownloadResult.self) { group in
            func addNext() -> Bool {
                guard let audioId = pending.next() else { return false }
                let url = pack.audioURL(for: audioId)
                group.addTask {
                    await Self.fetch(audioId: audioId, from: url, into: directory, session: session)
                }
                return true
            }

            for _ in 0..<Self.maxConcurrentDownloads {
                if !addNext() { break }
            }

            for await result in group {
                switch result {
                case .success(let audioId, let byteCount):
                    // Kimlik yalnızca dosya bütünüyle yazıldıktan SONRA eklenir.
                    register(audioId: audioId, byteCount: byteCount)
                case .failure(let audioId):
                    failed.append(audioId)
                }
                refreshProgress()
                _ = addNext()
            }
        }
        return failed
    }

    private enum DownloadResult: Sendable {
        case success(audioId: String, byteCount: Int64)
        case failure(audioId: String)
    }

    private nonisolated static func fetch(
        audioId: String,
        from url: URL,
        into directory: URL,
        session: URLSession
    ) async -> DownloadResult {
        do {
            let (data, response) = try await session.data(from: url)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                return .failure(audioId: audioId)
            }
            // Gövde beklenenden kısaysa bağlantı ortada kopmuştur.
            let expected = http.expectedContentLength
            guard expected <= 0 || Int64(data.count) == expected else {
                return .failure(audioId: audioId)
            }
            guard looksLikeMP3(data) else { return .failure(audioId: audioId) }

            let target = directory.appendingPathComponent("\(audioId).\(fileExtension)", isDirectory: false)
            // `.atomic`: aynı klasörde geçici dosyaya yazıp `rename()` ile taşır.
            // Uygulama yazma sırasında öldürülse bile hedefte yarım dosya kalmaz —
            // ya eski hâli vardır ya hiç yoktur.
            try data.write(to: target, options: .atomic)
            return .success(audioId: audioId, byteCount: Int64(data.count))
        } catch {
            return .failure(audioId: audioId)
        }
    }

    /// Sunucu 200 ile HTML hata sayfası döndürebilir; o zaman "indi" sayılan
    /// dosya çalma anında sessizlik olur. Bayt başlığına bakıp önlüyoruz.
    private nonisolated static func looksLikeMP3(_ data: Data) -> Bool {
        guard data.count >= minimumClipBytes else { return false }
        let head = [UInt8](data.prefix(3))
        guard head.count >= 3 else { return false }
        if head[0] == 0x49, head[1] == 0x44, head[2] == 0x33 { return true }   // "ID3"
        return head[0] == 0xFF && (head[1] & 0xE0) == 0xE0                     // MPEG çerçeve senkronu
    }

    // MARK: - Çalma

    /// Klibi çalar. Ses yoksa ya da çözümlenemiyorsa Türkçe bir hata bırakır:
    /// bu sınıfın var oluş sebebi, sessizce hiçbir şey yapmamayı önlemek.
    func play(audioId: String) {
        guard let url = localURL(for: audioId) else {
            lastError = "Bu sesin dosyası henüz inmedi. İnternete bağlandığında kendiliğinden inecek."
            return
        }
        prepareSessionIfNeeded()
        player?.stop()
        do {
            let player = try AVAudioPlayer(contentsOf: url)
            player.delegate = self
            guard player.play() else { throw PlaybackError.refused }
            self.player = player
            playingAudioId = audioId
            lastError = nil
        } catch {
            player = nil
            playingAudioId = nil
            // Dosya bozuk: sil ve yeniden indir. Bozuk bir klip sessizlik olarak
            // çalarsa kullanıcı hatayı hiç göremez.
            discard(audioId: audioId)
            lastError = "Ses çalınamadı; dosya bozuk görünüyor. " + Self.repairAdvice(started: repairMissingClips())
        }
    }

    /// Onarım turu gerçekten başladıysa öyle söyle. Paket henüz bilinmiyorken
    /// "yeniden indiriliyor" demek kullanıcıya yalan olurdu.
    private static func repairAdvice(started: Bool) -> String {
        started ? "Yeniden indiriliyor, birazdan tekrar dene." : "Ders yeniden açıldığında indirilecek."
    }

    private enum PlaybackError: Error { case refused }

    /// Ses oturumu bir kez kurulur — her çalışta yeniden kurmak gereksiz.
    /// Yine de kategori kontrol edilir: sesli günlük (`SpeechRecorder`) kategoriyi
    /// `.record`'a çevirmiş olabilir ve o hâlde klip sessiz kalırdı.
    ///
    /// Oturum bilerek kapatılmıyor: aynı oturumu yol müziği (`MusicPlayer`) da
    /// kullanıyor, `setActive(false)` çalan müziği susturur.
    private func prepareSessionIfNeeded() {
        let audioSession = AVAudioSession.sharedInstance()
        guard !sessionReady || audioSession.category != .playback else { return }
        try? audioSession.setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
        try? audioSession.setActive(true)
        sessionReady = true
    }

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        let finished = ObjectIdentifier(player)
        Task { @MainActor in
            self.clearPlayer(if: finished)
        }
    }

    nonisolated func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        let broken = ObjectIdentifier(player)
        Task { @MainActor in
            guard let audioId = self.playingAudioId, self.isCurrent(broken) else { return }
            self.clearPlayer(if: broken)
            self.discard(audioId: audioId)
            self.lastError = "Ses yarıda kesildi; dosya bozuk. " + Self.repairAdvice(started: self.repairMissingClips())
        }
    }

    private func isCurrent(_ identifier: ObjectIdentifier) -> Bool {
        player.map(ObjectIdentifier.init) == identifier
    }

    /// Yeni bir klip başlamışsa eski çaların geri çağrısı durumu bozmasın.
    private func clearPlayer(if identifier: ObjectIdentifier) {
        guard isCurrent(identifier) else { return }
        player = nil
        playingAudioId = nil
    }

    // MARK: - Disk

    private func fileURL(for audioId: String) -> URL {
        directory.appendingPathComponent("\(audioId).\(Self.fileExtension)", isDirectory: false)
    }

    /// Bozuk/eskimiş klibi diskten ve kümeden düşürür.
    private func discard(audioId: String) {
        try? FileManager.default.removeItem(at: fileURL(for: audioId))
        unregister(audioId: audioId)
        refreshProgress()
    }

    private func register(audioId: String, byteCount: Int64) {
        storedByteCount += byteCount - (clipBytes[audioId] ?? 0)
        clipBytes[audioId] = byteCount
        downloadedAudioIds.insert(audioId)
    }

    private func unregister(audioId: String) {
        guard let byteCount = clipBytes.removeValue(forKey: audioId) else { return }
        storedByteCount = max(0, storedByteCount - byteCount)
        downloadedAudioIds.remove(audioId)
    }

    /// Bilinen paketle sessizce bir onarım turu başlatır.
    /// - Returns: tur başlatıldıysa `true`. Paket henüz bilinmiyorsa (ilk
    ///   `syncMissing` çağrısından önce) onarım yapılamaz.
    @discardableResult
    private func repairMissingClips() -> Bool {
        guard let pack = lastPack else { return false }
        Task { [weak self] in
            guard let self else { return }
            // Eşitleme sürüyorsa önce onun bitmesini bekle: az önce düşürdüğümüz
            // klip o turun eksik listesine giremezdi, yeni bir tur gerekiyor.
            if let active = self.activeSync { await active.value }
            await self.syncMissing(pack: pack)
        }
        return true
    }

    /// Paket değişip bir klip artık kullanılmıyorsa diskte kalmasın.
    private func pruneUnreferenced() {
        for audioId in downloadedAudioIds.subtracting(manifestIds) {
            discard(audioId: audioId)
        }
    }

    private func refreshProgress() {
        guard !manifestIds.isEmpty else { return }
        let ready = manifestIds.intersection(downloadedAudioIds).count
        downloadProgress = min(1, Double(ready) / Double(manifestIds.count))
    }

    private func rescanDisk() {
        clipBytes = Self.scanDirectory(directory)
        downloadedAudioIds = Set(clipBytes.keys)
        storedByteCount = clipBytes.values.reduce(0, +)
        refreshProgress()
    }

    /// Diskteki gerçeği okur. Beklenmedik biçimde küçük ya da düzensiz dosyalar
    /// (eski sürümlerden kalmış olabilir) silinir; "var" diye raporlanmaz.
    private static func scanDirectory(_ directory: URL) -> [String: Int64] {
        let keys: Set<URLResourceKey> = [.fileSizeKey, .isRegularFileKey]
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: Array(keys),
            options: [.skipsHiddenFiles, .skipsSubdirectoryDescendants]
        ) else {
            return [:]
        }

        var clips: [String: Int64] = [:]
        for url in entries where url.pathExtension == fileExtension {
            let values = try? url.resourceValues(forKeys: keys)
            guard values?.isRegularFile == true,
                  let size = values?.fileSize, size >= minimumClipBytes else {
                try? FileManager.default.removeItem(at: url)
                continue
            }
            clips[url.deletingPathExtension().lastPathComponent] = Int64(size)
        }
        return clips
    }

    private static func makeDirectory() -> URL {
        let manager = FileManager.default
        let base = (try? manager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )) ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)

        var directory = base.appendingPathComponent(directoryName, isDirectory: true)
        try? manager.createDirectory(at: directory, withIntermediateDirectories: true)
        // Klipler her an yeniden indirilebilir; iCloud yedeğini 6 MB şişirmesinler.
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? directory.setResourceValues(values)
        return directory
    }

    private static func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.default
        // Klipler zaten diske yazılıyor; URLCache ikinci bir kopya tutmasın.
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = 120
        configuration.httpMaximumConnectionsPerHost = maxConcurrentDownloads
        return URLSession(configuration: configuration)
    }

    /// Kimlikler `pack.audioManifest` ile aynı kümedir, ama sahne sırasındadır:
    /// ilk dersin sesleri ilk iner, kullanıcı indirmenin tamamını beklemeden
    /// başlayabilir.
    private static func orderedAudioIds(in pack: LatvianPack) -> [String] {
        var seen: Set<String> = []
        var ordered: [String] = []
        for scene in pack.scenes {
            for audioId in scene.words.map(\.audioId) + scene.sentences.map(\.audioId)
            where isSafe(audioId: audioId) {
                if seen.insert(audioId).inserted { ordered.append(audioId) }
            }
        }
        return ordered
    }

    /// Kimlik dosya adına çevrildiği için klasörden dışarı çıkmadığı doğrulanır.
    private static func isSafe(audioId: String) -> Bool {
        !audioId.isEmpty && audioId.count <= 64 && audioId.allSatisfy {
            $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-" || $0 == "_")
        }
    }
}
