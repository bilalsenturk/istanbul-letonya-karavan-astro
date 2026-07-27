import Foundation

/// Hafızadaki tek bir kayıt: anahtarı ve kartı bir arada.
/// Ders kurgusu hafızayı hep bu tip üzerinden, sıralı dizilerle geziyor.
struct LatvianMemoryEntry: Hashable, Sendable {
    let key: LatvianMemoryKey
    let card: LatvianMemoryCard
}

/// `LatvianProgress.load(from:)` sonucunda ne kadarının kurtarıldığı.
/// Çağıran, `.recovered` ve `.reset` durumlarında kullanıcıyı bilgilendirebilir.
enum LatvianProgressLoadOutcome: String, Hashable, Sendable {
    /// Hiç kayıt yoktu; sıfırdan başlandı.
    case fresh
    /// Ana dosyadan okundu.
    case loaded
    /// Ana dosya okunamadı, yedekten kurtarıldı.
    case recovered
    /// Ne ana dosya ne yedek okunabildi; ilerleme sıfırlandı.
    case reset
}

/// Öğrencinin kalıcı durumu: hafıza kartları, XP, seri, can, son hatalar ve
/// tamamlanan sahneler.
///
/// İki kural bu tipin her yerinde geçerli:
///
/// 1. **Gizli saat yok.** Zamana bağlı her fonksiyon anı parametre olarak alır;
///    burada hiçbir yerde `Date()` çağrılmaz. Aynı girdi her zaman aynı sonucu verir.
/// 2. **Sözlük sırası dışarı sızmaz.** Swift'in özet tohumu süreç başına yeniden
///    üretildiğinden, `memory` üzerinde ham sırayla gezip sonucu dışarı vermek
///    "aynı tohum aynı ders" garantisini kırardı. Dışarıya dönen her liste
///    `storageKey` gibi toplam bir sıralamayla belirlenimci hale getiriliyor.
struct LatvianProgress: Codable, Equatable, Sendable {
    static let maxHearts = 5
    /// Bir canın geri gelmesi için geçmesi gereken süre.
    static let heartRefillInterval: TimeInterval = 4 * 3600
    /// Hata listesinde tutulan en fazla kelime sayısı. Liste sınırsız büyümez.
    static let mistakeMemory = 24
    /// Doğru cevap başına kazanılan XP.
    static let xpPerCorrectAnswer = 10

    /// `LatvianMemoryKey.storageKey` → kart.
    private var memory: [String: LatvianMemoryCard]
    private(set) var xp: Int
    private(set) var streakDays: Int
    /// Son ders yapılan gün, `yyyy-MM-dd`. Hangi takvimle yazıldıysa onunla okunmalı.
    private(set) var lastLessonDay: String?
    private(set) var hearts: Int
    /// Dolum sayacının başladığı an: canlar tam değilken bir sonraki canın
    /// sayılmaya başladığı nokta. Canlar doluyken `nil`.
    private(set) var lastHeartLostAt: Date?
    /// Son derslerde yanlış yapılan kelimeler, en yenisi sonda.
    private(set) var recentMistakes: [String]
    /// Sahne kimliği → ilk tamamlandığı an.
    private(set) var sceneCompletedAt: [String: Date]

    private init(
        memory: [String: LatvianMemoryCard],
        xp: Int,
        streakDays: Int,
        lastLessonDay: String?,
        hearts: Int,
        lastHeartLostAt: Date?,
        recentMistakes: [String],
        sceneCompletedAt: [String: Date]
    ) {
        self.memory = memory
        self.xp = xp
        self.streakDays = streakDays
        self.lastLessonDay = lastLessonDay
        self.hearts = hearts
        self.lastHeartLostAt = lastHeartLostAt
        self.recentMistakes = recentMistakes
        self.sceneCompletedAt = sceneCompletedAt
    }

    static func new() -> LatvianProgress {
        LatvianProgress(
            memory: [:],
            xp: 0,
            streakDays: 0,
            lastLessonDay: nil,
            hearts: maxHearts,
            lastHeartLostAt: nil,
            recentMistakes: [],
            sceneCompletedAt: [:]
        )
    }

    // MARK: - Hafıza

    func card(for key: LatvianMemoryKey) -> LatvianMemoryCard? {
        memory[key.storageKey]
    }

    mutating func setCard(_ card: LatvianMemoryCard, for key: LatvianMemoryKey) {
        memory[key.storageKey] = card
    }

    /// Hafızadaki tüm kayıtlar, `storageKey`'e göre sıralı.
    /// Sıralama toplam (anahtarlar tekil), dolayısıyla sonuç süreçten sürece aynı.
    func allCards() -> [LatvianMemoryEntry] {
        memory
            .compactMap { entry in
                LatvianMemoryKey(storageKey: entry.key)
                    .map { LatvianMemoryEntry(key: $0, card: entry.value) }
            }
            .sorted { $0.key.storageKey < $1.key.storageKey }
    }

    /// Tekrar zamanı gelmiş kayıtlar, en zayıf hatırlananı başta.
    ///
    /// Hatırlanma olasılığı eşit olan kartlar sık görülür (örneğin hiç görülmemiş
    /// olanların hepsi sıfırdır); eşitlik `storageKey` ile bozuluyor, yoksa sıralama
    /// sözlük sırasına bağlı kalır ve süreçler arası değişirdi.
    func dueEntries(now: Date) -> [LatvianMemoryEntry] {
        Self.dueEntries(from: allCards(), now: now)
    }

    /// Aynı sıralama, kayıtlar hazırken. `allCards()` her anahtarı dizeden geri çözüp
    /// listeyi sıralıyor; ders kurgusu hem tekrar kuyruğunu hem takılan kelime havuzunu
    /// beslediğinden bunu ders başına iki kez yapmasın diye ayrı bir giriş var.
    static func dueEntries(from entries: [LatvianMemoryEntry], now: Date) -> [LatvianMemoryEntry] {
        // Hatırlanma olasılığı sıralama başına bir kez hesaplanıyor: karşılaştırıcının
        // içinde hesaplamak her kartı log n kez `pow`'dan geçirirdi.
        entries
            .filter { $0.card.isDue(at: now) }
            .map { (entry: $0, score: $0.card.retrievability(at: now)) }
            .sorted { left, right in
                if left.score != right.score { return left.score < right.score }
                return left.entry.key.storageKey < right.entry.key.storageKey
            }
            .map(\.entry)
    }

    /// Tekrar zamanı gelmiş kelimeler, en acili başta; her kelime bir kez.
    func dueWordIds(now: Date) -> [String] {
        var seen: Set<String> = []
        var result: [String] = []
        for entry in dueEntries(now: now) where seen.insert(entry.key.wordId).inserted {
            result.append(entry.key.wordId)
        }
        return result
    }

    /// Bir cevabı hafızaya işler. **Yalnızca verilen modalitenin kartına dokunur** —
    /// tanıma ve üretim ayrı ayrı öğrenilir, sahne kilidi ikisini birden ister.
    ///
    /// - Returns: Cevap yazıldıysa `true`. Kelime kimliği boşsa (anahtara kodlanamaz)
    ///   `false` döner ve hiçbir şey değişmez.
    @discardableResult
    mutating func registerAnswer(
        wordId: String,
        modality: LatvianModality,
        rating: LatvianRating,
        scheduler: LatvianScheduler,
        now: Date
    ) -> Bool {
        guard let key = LatvianMemoryKey(wordId: wordId, modality: modality) else { return false }
        let existing = memory[key.storageKey] ?? .new()
        memory[key.storageKey] = scheduler.review(card: existing, rating: rating, now: now)

        switch rating {
        case .again:
            // Aynı kelime listede iki kez yer kaplamasın diye önce çıkarılıp sona ekleniyor.
            recentMistakes.removeAll { $0 == wordId }
            recentMistakes.append(wordId)
            if recentMistakes.count > Self.mistakeMemory {
                recentMistakes.removeFirst(recentMistakes.count - Self.mistakeMemory)
            }
        case .hard:
            // Zorlanarak da olsa doğru: listeye girmiyor ama zaten oradaysa çıkmıyor.
            break
        case .good, .easy:
            recentMistakes.removeAll { $0 == wordId }
        }

        if rating != .again { xp += Self.xpPerCorrectAnswer }
        return true
    }

    // MARK: - Can

    /// Bir can eksiltir. Kayıp anında bekleyen dolumlar önce işleniyor, yoksa
    /// dört saati dolmuş bir can kaybın altında kalırdı.
    ///
    /// Dolum sayacı yalnızca canlar tamken düşerken başlıyor; art arda gelen kayıplar
    /// sayacı ileri itmiyor. Aksi halde canı biten öğrenci her yanlışta sayacı sıfırlar
    /// ve hiç can kazanamazdı.
    mutating func loseHeart(now: Date) {
        refillHearts(now: now)
        guard hearts > 0 else { return }
        let wasFull = hearts == Self.maxHearts
        hearts -= 1
        if wasFull || lastHeartLostAt == nil { lastHeartLostAt = now }
    }

    /// Geçen süreye göre canları geri verir. Üst sınırı aşamaz; uzun aradan sonra
    /// da yalnızca eksik can kadarı geri gelir.
    mutating func refillHearts(now: Date) {
        guard hearts < Self.maxHearts else {
            lastHeartLostAt = nil
            return
        }
        guard let anchor = lastHeartLostAt else { return }
        let elapsed = now.timeIntervalSince(anchor)
        guard elapsed >= Self.heartRefillInterval else { return }

        // Eksik can sayısıyla sınırlamak hem üst sınırı korur hem de bozuk bir kayıttan
        // gelen uçuk tarihte `Int(...)` dönüşümünün taşmasını engeller.
        let missing = Self.maxHearts - hearts
        let earned = Int(min(elapsed / Self.heartRefillInterval, Double(missing)))
        guard earned > 0 else { return }

        hearts = min(Self.maxHearts, hearts + earned)
        lastHeartLostAt = hearts >= Self.maxHearts
            ? nil
            : anchor.addingTimeInterval(Double(earned) * Self.heartRefillInterval)
    }

    // MARK: - Seri

    /// Günlük seriyi günceller.
    ///
    /// Takvim açıkça parametre: gün sınırı saat dilimine bağlı olduğundan "an" ile
    /// "takvim" birlikte sonucu tam belirliyor. Aynı gün ikinci kez çağrılması seriyi
    /// artırmaz; tam bir gün sonrası artırır; daha büyük boşluk seriyi bire düşürür.
    mutating func registerLessonCompleted(now: Date, calendar: Calendar = .current) {
        let today = Self.dayKey(now, calendar: calendar)
        guard lastLessonDay != today else { return }

        // Gün farkı iki gece yarısı arasında ölçülüyor; gün içindeki saat farkı
        // (ya da yaz saati geçişindeki 23/25 saatlik gün) sonucu bozmasın diye.
        if let lastLessonDay,
           let previousMidnight = Self.date(from: lastLessonDay, calendar: calendar),
           let gap = calendar.dateComponents(
               [.day], from: previousMidnight, to: calendar.startOfDay(for: now)
           ).day,
           gap == 1 {
            streakDays += 1
        } else {
            streakDays = 1
        }
        lastLessonDay = today
    }

    static func dayKey(_ date: Date, calendar: Calendar = .current) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    private static func date(from key: String, calendar: Calendar) -> Date? {
        let parts = key.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        return calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))
    }

    // MARK: - XP ve sahne

    mutating func awardXP(_ amount: Int) {
        guard amount > 0 else { return }
        xp += amount
    }

    /// Sahnenin ilk tamamlanma anını kaydeder. Sonraki çağrılar ilk anı koruyor:
    /// kilit bir kez açıldıktan sonra unutma yüzünden geri kapanmasın diye.
    mutating func registerSceneCompletion(sceneId: String, now: Date) {
        guard !sceneId.isEmpty, sceneCompletedAt[sceneId] == nil else { return }
        sceneCompletedAt[sceneId] = now
    }

    func hasCompleted(sceneId: String) -> Bool {
        sceneCompletedAt[sceneId] != nil
    }

    // MARK: - Kodlama

    private enum CodingKeys: String, CodingKey {
        case memory, xp, streakDays, lastLessonDay, hearts, lastHeartLostAt
        case recentMistakes, sceneCompletedAt
    }

    /// Eksik alanları varsayılana, anlamsız değerleri geçerli aralığa çekiyor.
    /// Eski sürümden gelen ya da elle bozulmuş bir kayıt yüzünden uygulama çökmemeli;
    /// tamamen okunamayan JSON zaten `load(from:)` tarafından yakalanıyor.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let storedMemory = try container.decodeIfPresent(
            [String: LatvianMemoryCard].self, forKey: .memory
        ) ?? [:]
        // Çözülemeyen anahtar ders kurgusunda sessizce kaybolurdu; burada atılıyor.
        memory = storedMemory.filter { LatvianMemoryKey(storageKey: $0.key) != nil }
        xp = max(0, try container.decodeIfPresent(Int.self, forKey: .xp) ?? 0)
        streakDays = max(0, try container.decodeIfPresent(Int.self, forKey: .streakDays) ?? 0)
        lastLessonDay = try container.decodeIfPresent(String.self, forKey: .lastLessonDay)
        let storedHearts = try container.decodeIfPresent(Int.self, forKey: .hearts) ?? Self.maxHearts
        hearts = min(Self.maxHearts, max(0, storedHearts))
        lastHeartLostAt = try container.decodeIfPresent(Date.self, forKey: .lastHeartLostAt)
        let storedMistakes = try container.decodeIfPresent([String].self, forKey: .recentMistakes) ?? []
        recentMistakes = Self.tidy(mistakes: storedMistakes)
        sceneCompletedAt = try container.decodeIfPresent(
            [String: Date].self, forKey: .sceneCompletedAt
        ) ?? [:]
    }

    /// Boşları atar, tekrarları en yeni geçişte toplar, üst sınıra kırpar.
    private static func tidy(mistakes: [String]) -> [String] {
        var result: [String] = []
        for wordId in mistakes where !wordId.isEmpty {
            result.removeAll { $0 == wordId }
            result.append(wordId)
        }
        if result.count > mistakeMemory {
            result.removeFirst(result.count - mistakeMemory)
        }
        return result
    }

    // MARK: - Kalıcılık

    func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(self)
    }

    static func decode(from data: Data) throws -> LatvianProgress {
        try JSONDecoder().decode(LatvianProgress.self, from: data)
    }

    /// `UserDefaults` değil: ilerleme büyüyen bir kayıt ve yedeklenebilir olmalı.
    static func defaultFileURL() throws -> URL {
        let directory = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        return directory.appendingPathComponent("latvian-progress.json")
    }

    static func backupURL(for url: URL) -> URL {
        url.appendingPathExtension("bak")
    }

    /// Ana dosya okunamazsa yedeğe düşer; ikisi de okunamazsa sıfırdan başlar.
    /// Hiçbir durumda hata fırlatmıyor — ilerleme dosyası uygulamayı açılışta düşürmemeli.
    static func load(from url: URL) -> (progress: LatvianProgress, outcome: LatvianProgressLoadOutcome) {
        let backup = backupURL(for: url)
        let hadAnyFile = FileManager.default.fileExists(atPath: url.path)
            || FileManager.default.fileExists(atPath: backup.path)

        if let data = try? Data(contentsOf: url), let value = try? decode(from: data) {
            return (value, .loaded)
        }
        if let data = try? Data(contentsOf: backup), let value = try? decode(from: data) {
            return (value, .recovered)
        }
        return (.new(), hadAnyFile ? .reset : .fresh)
    }

    static func load() -> (progress: LatvianProgress, outcome: LatvianProgressLoadOutcome) {
        guard let url = try? defaultFileURL() else { return (.new(), .fresh) }
        return load(from: url)
    }

    /// Önce geçerli olan eski içeriği yedekliyor, sonra atomik yazıyor.
    /// Eski içerik zaten bozuksa yedeklenmiyor: bozuk bir dosyayı yedeğin üstüne
    /// yazmak, kurtarılabilecek tek kopyayı da yok ederdi.
    func save(to url: URL) throws {
        let data = try encoded()
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        if let existing = try? Data(contentsOf: url), (try? Self.decode(from: existing)) != nil {
            try? existing.write(to: Self.backupURL(for: url), options: .atomic)
        }
        try data.write(to: url, options: .atomic)
    }

    func save() throws {
        try save(to: Self.defaultFileURL())
    }
}
