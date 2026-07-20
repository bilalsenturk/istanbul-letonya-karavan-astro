# Günlük ve Bildirimler — Uygulama Planı

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Kuzey'e herkesin kendi iCloud hesabında tuttuğu, çevrimdışı çalışan, sesli yazdırılabilen ve fotoğraf eklenebilen bir günlük ile yolda işe yarayan yerel bildirimler eklemek.

**Architecture:** Günlük kayıtları önce cihaza (`Documents/journal/`) yazılır, sonra CloudKit özel veritabanına kuyruktan gönderilir — sinyalsiz sınır bölgelerinde kayıt kaybolmaz. Saf mantık (kuyruk durum makinesi, bildirim tetik kuralları, bildirim bütçesi) UI'dan ayrı dosyalarda tutulur ve mevcut `swiftc` test koşucusuyla doğrulanır. Paylaşılan kayıtlar mevcut Vercel Blob hattından web'e yansır.

**Tech Stack:** SwiftUI, CloudKit (özel DB), Speech (`SFSpeechRecognizer` tr-TR), PhotoKit, JournalingSuggestions (iOS 17.2+), UserNotifications, xcodegen.

## Global Constraints

- iOS dağıtım hedefi **17.0** (`ios/project.yml`). `JournalingSuggestions` yalnızca **iOS 17.2+** — `#available` ile korunmalı, 17.0–17.1'de sessizce gizlenmeli.
- Tüm kullanıcıya görünen metinler **Türkçe**.
- Tüm bildirimler **yerel** (`UNUserNotificationCenter`). Push, APNs veya sunucu yok.
- Yeni izin kullanımı `ios/project.yml` içinde **usage description** ister. Eksik açıklama gerçek cihazda SIGABRT ile anında çökmeye yol açar (bu projede `NSMotionUsageDescription` eksikliği tam olarak buna sebep oldu).
- Renk/tipografi mevcut `Theme` üzerinden: `Theme.bg`, `Theme.panel`, `Theme.text`, `Theme.muted`, `Theme.dim`, `Theme.line`, `Theme.c1`–`Theme.c4`, `Theme.ok`, `Theme.bad`, `Theme.gradWarm`. Başlıklar `MonoLabel(text:color:)`, kartlar `.card()`.
- Saf mantık testleri `ios/Tests/` altındaki `swiftc` koşucu kalıbını izler (XCTest hedefi yok).
- CloudKit, mikrofon ve fotoğraf davranışı **gerçek cihazda** doğrulanır; simülatör yetmez.
- Commit mesajları Türkçe, sonunda `Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>`.

## Dosya Yapısı

**Oluşturulacak**

| Dosya | Sorumluluk |
|---|---|
| `ios/Karavan/Journal/JournalEntry.swift` | Kayıt modeli, `Codable`, CloudKit `CKRecord` dönüşümü |
| `ios/Karavan/Journal/JournalQueue.swift` | Gönderim kuyruğu — saf durum makinesi, testlenebilir |
| `ios/Karavan/Journal/JournalCloud.swift` | CloudKit özel DB işlemleri (yaz/oku/sil) |
| `ios/Karavan/Journal/JournalStore.swift` | Cihaz-önce depolama + kuyruk boşaltma orkestrasyonu |
| `ios/Karavan/Journal/SpeechRecorder.swift` | `VoiceExpenseView`'dan çıkarılan sesli dikte motoru |
| `ios/Karavan/Views/Journal/JournalView.swift` | Zaman çizgisi (kendi kayıtlarım + paylaşılanlar) |
| `ios/Karavan/Views/Journal/JournalComposeView.swift` | Kayıt oluşturma: metin + ses + fotoğraf + ruh hali |
| `ios/Karavan/Views/Journal/JournalPhotoPicker.swift` | Konumlu fotoğraflar önde gelen seçici |
| `ios/Karavan/Notifications/NotificationRules.swift` | Tetik kuralları — saf, testlenebilir |
| `ios/Karavan/Notifications/NotificationBudget.swift` | Bildirim disiplini — saf, testlenebilir |
| `ios/Karavan/Notifications/TripNotifier.swift` | Kuralları canlı veriye bağlayan katman |
| `ios/Tests/journal-queue-check.swift` | Kuyruk testleri |
| `ios/Tests/run-journal-check.sh` | Kuyruk test koşucusu |
| `ios/Tests/notification-rules-check.swift` | Bildirim kuralı testleri |
| `ios/Tests/run-notification-check.sh` | Bildirim test koşucusu |
| `src/pages/api/journal.ts` | Paylaşılan kayıtlar için Blob uç noktası |

**Değiştirilecek**

| Dosya | Değişiklik |
|---|---|
| `ios/project.yml` | CloudKit entitlement + container, `NSRemindersUsageDescription` gerekmez; mevcut mikrofon/fotoğraf açıklamaları yeterli |
| `ios/Karavan/Kuzey.entitlements` | `com.apple.developer.icloud-services` + container |
| `ios/Karavan/Views/Tools/VoiceExpenseView.swift` | `SpeechRecorder` çıkarıldı, import edilir |
| `ios/Karavan/KaravanApp.swift` | `JournalStore` + `TripNotifier` bağlanır |
| `ios/Karavan/ContentView.swift` | "Günlük" sekmesi |
| `ios/Karavan/Config.swift` | `journalPostURL` |
| `ios/Karavan/LocationManager.swift` | Konum tabanlı tetikler `TripNotifier`'a bağlanır |

---

## Task 1: Günlük kayıt modeli ve gönderim kuyruğu

Kuyruk saf bir durum makinesi olarak yazılır: hangi kaydın gönderilmeyi beklediğini, kaç kez denendiğini ve ne zaman vazgeçileceğini bilir. Ağ veya CloudKit bilmez — bu yüzden testlenebilir.

**Files:**
- Create: `ios/Karavan/Journal/JournalEntry.swift`
- Create: `ios/Karavan/Journal/JournalQueue.swift`
- Create: `ios/Tests/journal-queue-check.swift`
- Create: `ios/Tests/run-journal-check.sh`

**Interfaces:**
- Consumes: yok (ilk görev)
- Produces:
  - `struct JournalEntry: Codable, Identifiable, Equatable` — alanlar: `id: String`, `text: String`, `createdAt: Date`, `latitude: Double?`, `longitude: Double?`, `stopId: String?`, `mood: String?`, `photoFilenames: [String]`, `isShared: Bool`
  - `enum SyncState: String, Codable { case pending, syncing, synced, failed }`
  - `struct QueueItem: Codable, Equatable` — `entryId: String`, `state: SyncState`, `attempts: Int`, `lastAttemptAt: Date?`
  - `struct JournalQueue` — `mutating func enqueue(_ entryId: String)`, `mutating func markSyncing(_ entryId: String, now: Date)`, `mutating func markSynced(_ entryId: String)`, `mutating func markFailed(_ entryId: String, now: Date)`, `func nextToSend(now: Date) -> String?`, `var pendingCount: Int`
  - Sabit: `JournalQueue.maxAttempts = 5`, `JournalQueue.backoff(attempts:) -> TimeInterval`

- [ ] **Step 1: Kuyruk testlerini yaz (başarısız olacak)**

`ios/Tests/journal-queue-check.swift`:

```swift
import Foundation

var failures = 0
func check(_ name: String, _ condition: Bool, _ detail: String = "") {
    if condition { print("  ✓ \(name)") }
    else { failures += 1; print("  ✗ \(name) \(detail)") }
}

let t0 = Date(timeIntervalSince1970: 1_780_000_000)

print("\n=== 1) Kuyruğa alma ve sıra ===")
var q = JournalQueue()
q.enqueue("a")
q.enqueue("b")
check("iki kayıt bekliyor", q.pendingCount == 2, "\(q.pendingCount)")
check("ilk gönderilecek a", q.nextToSend(now: t0) == "a", q.nextToSend(now: t0) ?? "nil")

print("\n=== 2) Aynı kayıt iki kez kuyruğa girmez ===")
q.enqueue("a")
check("hâlâ iki kayıt", q.pendingCount == 2, "\(q.pendingCount)")

print("\n=== 3) Başarılı gönderim kuyruktan düşürür ===")
q.markSyncing("a", now: t0)
check("gönderilirken sıradaki a değil", q.nextToSend(now: t0) == "b", q.nextToSend(now: t0) ?? "nil")
q.markSynced("a")
check("bir kayıt kaldı", q.pendingCount == 1, "\(q.pendingCount)")

print("\n=== 4) Başarısızlık geri çekilme süresi uygular ===")
q.markSyncing("b", now: t0)
q.markFailed("b", now: t0)
check("hemen tekrar denenmez", q.nextToSend(now: t0) == nil, q.nextToSend(now: t0) ?? "nil")
let afterBackoff = t0.addingTimeInterval(JournalQueue.backoff(attempts: 1) + 1)
check("geri çekilme sonrası denenir", q.nextToSend(now: afterBackoff) == "b",
      q.nextToSend(now: afterBackoff) ?? "nil")

print("\n=== 5) Geri çekilme artan olmalı ===")
check("2. deneme 1.'den uzun",
      JournalQueue.backoff(attempts: 2) > JournalQueue.backoff(attempts: 1),
      "\(JournalQueue.backoff(attempts: 1)) → \(JournalQueue.backoff(attempts: 2))")

print("\n=== 6) Azami deneme sonrası vazgeçilir ===")
var q2 = JournalQueue()
q2.enqueue("c")
var now = t0
for i in 1 ... JournalQueue.maxAttempts {
    q2.markSyncing("c", now: now)
    q2.markFailed("c", now: now)
    now = now.addingTimeInterval(JournalQueue.backoff(attempts: i) + 1)
}
check("azami denemeden sonra sıraya girmez", q2.nextToSend(now: now) == nil,
      q2.nextToSend(now: now) ?? "nil")
check("kayıt failed durumunda", q2.items.first?.state == .failed,
      q2.items.first?.state.rawValue ?? "nil")

print("\n=== 7) Kuyruk diske yazılıp okunabilir ===")
let encoded = try! JSONEncoder().encode(q2)
let decoded = try! JSONDecoder().decode(JournalQueue.self, from: encoded)
check("gidiş-dönüş bozulmuyor", decoded == q2)

print("\n=== 8) Kayıt modeli gidiş-dönüş ===")
let entry = JournalEntry(
    id: "e1", text: "Sofya'da yağmur başladı", createdAt: t0,
    latitude: 42.6977, longitude: 23.3219, stopId: "sofya",
    mood: "yorgun", photoFilenames: ["e1-0.jpg"], isShared: false
)
let ed = try! JSONEncoder().encode(entry)
let dd = try! JSONDecoder().decode(JournalEntry.self, from: ed)
check("kayıt gidiş-dönüş bozulmuyor", dd == entry)
check("varsayılan gizli", entry.isShared == false)

print(failures == 0 ? "\n✅ hepsi geçti\n" : "\n❌ \(failures) başarısız\n")
exit(failures == 0 ? 0 : 1)
```

- [ ] **Step 2: Test koşucusunu yaz**

`ios/Tests/run-journal-check.sh`:

```bash
#!/usr/bin/env bash
# Günlük kuyruğu doğrulaması (UI'sız, saniyeler içinde).
#   ./ios/Tests/run-journal-check.sh
set -e
DIR="$(cd "$(dirname "$0")" && pwd)"
SRC="$DIR/../Karavan"
OUT="$(mktemp -d)"
swiftc -O -o "$OUT/journalcheck" \
  "$DIR/journal-queue-check.swift" \
  "$SRC/Journal/JournalEntry.swift" \
  "$SRC/Journal/JournalQueue.swift"
"$OUT/journalcheck"
```

Çalıştırılabilir yap:

```bash
chmod +x ios/Tests/run-journal-check.sh
```

- [ ] **Step 3: Testi çalıştır, başarısız olduğunu gör**

Run: `./ios/Tests/run-journal-check.sh`
Expected: FAIL — `error: cannot find 'JournalQueue' in scope` (dosyalar henüz yok)

- [ ] **Step 4: Kayıt modelini yaz**

`ios/Karavan/Journal/JournalEntry.swift`:

```swift
import Foundation

// Günlük kaydı. Cihazda JSON olarak saklanır, CloudKit özel veritabanına
// kuyruktan gönderilir. Fotoğraflar ayrı dosyalar; burada yalnızca adları durur.
struct JournalEntry: Codable, Identifiable, Equatable {
    let id: String
    var text: String
    var createdAt: Date
    var latitude: Double?
    var longitude: Double?
    var stopId: String?
    var mood: String?
    var photoFilenames: [String]
    /// Varsayılan GİZLİ. Paylaşmak bilinçli bir eylem olmalı —
    /// sonradan gizliye almak zor, baştan gizli olmak kolay.
    var isShared: Bool

    init(id: String = UUID().uuidString,
         text: String,
         createdAt: Date = Date(),
         latitude: Double? = nil,
         longitude: Double? = nil,
         stopId: String? = nil,
         mood: String? = nil,
         photoFilenames: [String] = [],
         isShared: Bool = false) {
        self.id = id
        self.text = text
        self.createdAt = createdAt
        self.latitude = latitude
        self.longitude = longitude
        self.stopId = stopId
        self.mood = mood
        self.photoFilenames = photoFilenames
        self.isShared = isShared
    }
}
```

- [ ] **Step 5: Kuyruğu yaz**

`ios/Karavan/Journal/JournalQueue.swift`:

```swift
import Foundation

enum SyncState: String, Codable {
    case pending, syncing, synced, failed
}

struct QueueItem: Codable, Equatable {
    let entryId: String
    var state: SyncState
    var attempts: Int
    var lastAttemptAt: Date?
}

// Gönderim kuyruğu — SAF durum makinesi. Ağ veya CloudKit bilmez;
// yalnızca hangi kaydın ne zaman denenebileceğini bilir. Bu ayrım
// kuyruğun cihazsız test edilebilmesini sağlar.
struct JournalQueue: Codable, Equatable {
    private(set) var items: [QueueItem] = []

    static let maxAttempts = 5

    /// Artan geri çekilme: 30 sn, 2 dk, 8 dk, 32 dk, 2 saat.
    /// Sinyalsiz sınır bölgesinde saniyede bir denemek pil yakar.
    static func backoff(attempts: Int) -> TimeInterval {
        30 * pow(4, Double(max(0, attempts - 1)))
    }

    mutating func enqueue(_ entryId: String) {
        guard !items.contains(where: { $0.entryId == entryId }) else { return }
        items.append(QueueItem(entryId: entryId, state: .pending, attempts: 0, lastAttemptAt: nil))
    }

    mutating func markSyncing(_ entryId: String, now: Date) {
        update(entryId) { $0.state = .syncing; $0.lastAttemptAt = now }
    }

    mutating func markSynced(_ entryId: String) {
        items.removeAll { $0.entryId == entryId }
    }

    mutating func markFailed(_ entryId: String, now: Date) {
        update(entryId) {
            $0.attempts += 1
            $0.lastAttemptAt = now
            $0.state = $0.attempts >= Self.maxAttempts ? .failed : .pending
        }
    }

    /// Şu an gönderilebilecek ilk kayıt. Gönderim sırasındakiler, vazgeçilenler
    /// ve geri çekilme süresi dolmayanlar atlanır.
    func nextToSend(now: Date) -> String? {
        items.first { item in
            guard item.state == .pending else { return false }
            guard item.attempts > 0, let last = item.lastAttemptAt else { return true }
            return now.timeIntervalSince(last) >= Self.backoff(attempts: item.attempts)
        }?.entryId
    }

    var pendingCount: Int {
        items.filter { $0.state != .failed }.count
    }

    private mutating func update(_ entryId: String, _ mutate: (inout QueueItem) -> Void) {
        guard let i = items.firstIndex(where: { $0.entryId == entryId }) else { return }
        mutate(&items[i])
    }
}
```

- [ ] **Step 6: Testi çalıştır, geçtiğini doğrula**

Run: `./ios/Tests/run-journal-check.sh`
Expected: PASS — `✅ hepsi geçti`, 12 kontrolün tamamı `✓`

- [ ] **Step 7: Commit**

```bash
git add ios/Karavan/Journal ios/Tests/journal-queue-check.swift ios/Tests/run-journal-check.sh
git commit -m "feat: günlük kayıt modeli ve gönderim kuyruğu

Kuyruk saf durum makinesi: artan geri çekilme (30 sn → 2 saat), azami 5
deneme. Ağ bilmediği için cihazsız test edilebiliyor.

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 2: CloudKit kurulumu ve bulut katmanı

**Files:**
- Modify: `ios/project.yml`
- Modify: `ios/Karavan/Kuzey.entitlements`
- Create: `ios/Karavan/Journal/JournalCloud.swift`

**Interfaces:**
- Consumes: `JournalEntry` (Task 1)
- Produces:
  - `actor JournalCloud` — `static let shared`
  - `func save(_ entry: JournalEntry, photoURLs: [URL]) async throws`
  - `func fetchAll() async throws -> [JournalEntry]`
  - `func delete(id: String) async throws`
  - `func accountAvailable() async -> Bool`
  - `enum JournalCloudError: Error { case accountUnavailable, quotaExceeded, network }`

- [ ] **Step 1: Entitlement'a CloudKit ekle**

`ios/project.yml` içinde `Kuzey` hedefinin `entitlements.properties` bölümünü şununla değiştir:

```yaml
    entitlements:
      path: Karavan/Kuzey.entitlements
      properties:
        com.apple.security.application-groups:
          - group.com.bilalsenturk.kuzey
        com.apple.developer.icloud-services:
          - CloudKit
        com.apple.developer.icloud-container-identifiers:
          - iCloud.com.bilalsenturk.kuzey
```

- [ ] **Step 2: Projeyi üret ve imzalamanın çalıştığını doğrula**

```bash
cd ios && xcodegen generate && \
xcodebuild -project Kuzey.xcodeproj -scheme Kuzey \
  -destination 'generic/platform=iOS' -configuration Debug \
  -allowProvisioningUpdates build 2>&1 | grep -E "error:|BUILD"
```

Expected: `** BUILD SUCCEEDED **`

Hata `Provisioning profile doesn't include the com.apple.developer.icloud-services entitlement` derse: CloudKit container'ı Apple hesabında yok demektir. `-allowProvisioningUpdates` genelde otomatik oluşturur; oluşturmazsa developer.apple.com → Identifiers → `com.bilalsenturk.kuzey` → iCloud kutusunu işaretle.

- [ ] **Step 3: Bulut katmanını yaz**

`ios/Karavan/Journal/JournalCloud.swift`:

```swift
import CloudKit
import Foundation

enum JournalCloudError: Error {
    case accountUnavailable
    case quotaExceeded
    case network
}

// CloudKit ÖZEL veritabanı — kayıtlar yalnızca sahibinin iCloud hesabında.
// Paylaşım burada YOK: paylaşılan kayıtlar ayrı bir yoldan (Vercel aynası) gider.
actor JournalCloud {
    static let shared = JournalCloud()

    private let container = CKContainer(identifier: "iCloud.com.bilalsenturk.kuzey")
    private var db: CKDatabase { container.privateCloudDatabase }

    private static let recordType = "JournalEntry"

    func accountAvailable() async -> Bool {
        (try? await container.accountStatus()) == .available
    }

    func save(_ entry: JournalEntry, photoURLs: [URL]) async throws {
        guard await accountAvailable() else { throw JournalCloudError.accountUnavailable }

        let record = CKRecord(recordType: Self.recordType,
                              recordID: CKRecord.ID(recordName: entry.id))
        record["text"] = entry.text as NSString
        record["createdAt"] = entry.createdAt as NSDate
        record["isShared"] = (entry.isShared ? 1 : 0) as NSNumber
        if let lat = entry.latitude { record["latitude"] = lat as NSNumber }
        if let lng = entry.longitude { record["longitude"] = lng as NSNumber }
        if let stopId = entry.stopId { record["stopId"] = stopId as NSString }
        if let mood = entry.mood { record["mood"] = mood as NSString }
        if !photoURLs.isEmpty {
            record["photos"] = photoURLs.map { CKAsset(fileURL: $0) }
        }

        do {
            _ = try await db.save(record)
        } catch let error as CKError {
            switch error.code {
            case .quotaExceeded: throw JournalCloudError.quotaExceeded
            case .networkUnavailable, .networkFailure: throw JournalCloudError.network
            case .notAuthenticated: throw JournalCloudError.accountUnavailable
            default: throw error
            }
        }
    }

    func fetchAll() async throws -> [JournalEntry] {
        guard await accountAvailable() else { throw JournalCloudError.accountUnavailable }

        let query = CKQuery(recordType: Self.recordType, predicate: NSPredicate(value: true))
        query.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: false)]

        let (results, _) = try await db.records(matching: query)
        return results.compactMap { _, result in
            guard let record = try? result.get() else { return nil }
            return Self.entry(from: record)
        }
    }

    func delete(id: String) async throws {
        _ = try await db.deleteRecord(withID: CKRecord.ID(recordName: id))
    }

    private static func entry(from record: CKRecord) -> JournalEntry? {
        guard let text = record["text"] as? String,
              let createdAt = record["createdAt"] as? Date else { return nil }
        let assets = record["photos"] as? [CKAsset] ?? []
        return JournalEntry(
            id: record.recordID.recordName,
            text: text,
            createdAt: createdAt,
            latitude: record["latitude"] as? Double,
            longitude: record["longitude"] as? Double,
            stopId: record["stopId"] as? String,
            mood: record["mood"] as? String,
            photoFilenames: assets.compactMap { $0.fileURL?.lastPathComponent },
            isShared: (record["isShared"] as? Int ?? 0) == 1
        )
    }
}
```

- [ ] **Step 4: Derle**

```bash
cd ios && xcodebuild -project Kuzey.xcodeproj -scheme Kuzey \
  -sdk iphonesimulator -destination 'id=687D33A5-A851-40B8-9979-743BD38156E5' \
  -configuration Debug build 2>&1 | grep -E "error:|BUILD"
```

Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 5: Commit**

```bash
git add ios/project.yml ios/Karavan/Kuzey.entitlements ios/Karavan/Journal/JournalCloud.swift ios/Kuzey.xcodeproj
git commit -m "feat: CloudKit özel veritabanı katmanı

Kayıtlar yalnızca sahibinin iCloud hesabında. Hata durumları ayrıştırıldı:
hesap yok, kota dolu, ağ yok — her biri kullanıcıya farklı davranış gerektiriyor.

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 3: Cihaz-önce depo ve kuyruk boşaltma

**Files:**
- Create: `ios/Karavan/Journal/JournalStore.swift`
- Modify: `ios/Karavan/KaravanApp.swift`

**Interfaces:**
- Consumes: `JournalEntry`, `JournalQueue` (Task 1), `JournalCloud` (Task 2)
- Produces:
  - `@MainActor final class JournalStore: ObservableObject`
  - `@Published private(set) var entries: [JournalEntry]` (yeniden eskiye sıralı)
  - `@Published private(set) var pendingCount: Int`
  - `@Published private(set) var cloudAvailable: Bool`
  - `@Published private(set) var cloudProblem: String?` — kullanıcıya gösterilecek hata metni (`nil` = sorun yok)
  - `func add(_ entry: JournalEntry, photos: [Data]) -> JournalEntry`
  - `func delete(_ entry: JournalEntry)`
  - `func setShared(_ entry: JournalEntry, shared: Bool)`
  - `func drainQueue() async`
  - `func photoURL(_ filename: String) -> URL`

- [ ] **Step 1: Depoyu yaz**

`ios/Karavan/Journal/JournalStore.swift`:

```swift
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

    private var queue = JournalQueue()

    private var dir: URL {
        let d = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("journal", isDirectory: true)
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }

    private var entriesFile: URL { dir.appendingPathComponent("entries.json") }
    private var queueFile: URL { dir.appendingPathComponent("queue.json") }

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
        pendingCount = queue.pendingCount
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(entries) {
            try? data.write(to: entriesFile, options: .atomic)
        }
        if let data = try? JSONEncoder().encode(queue) {
            try? data.write(to: queueFile, options: .atomic)
        }
        pendingCount = queue.pendingCount
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
            try? data.write(to: photoURL(name), options: .atomic)
            names.append(name)
        }
        saved.photoFilenames = names

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
        persist()
        Task { try? await JournalCloud.shared.delete(id: entry.id) }
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
        cloudProblem = nil

        while let id = queue.nextToSend(now: Date()) {
            guard let entry = entries.first(where: { $0.id == id }) else {
                queue.markSynced(id)
                continue
            }
            queue.markSyncing(id, now: Date())
            persist()

            let urls = entry.photoFilenames.map { photoURL($0) }
                .filter { FileManager.default.fileExists(atPath: $0.path) }

            do {
                try await JournalCloud.shared.save(entry, photoURLs: urls)
                queue.markSynced(id)
            } catch JournalCloudError.quotaExceeded {
                cloudProblem = "iCloud depolaman dolu — kayıtlar cihazda bekliyor."
                queue.markFailed(id, now: Date())
                persist()
                return
            } catch {
                queue.markFailed(id, now: Date())
                persist()
                return   // bir sonraki tetiklemede devam et
            }
            persist()
        }
    }
}
```

- [ ] **Step 2: Uygulamaya bağla**

`ios/Karavan/KaravanApp.swift` — durum nesnesi listesine ekle (`@StateObject private var roadFeed` satırının hemen altına):

```swift
    @StateObject private var journal = JournalStore()
```

`.environmentObject(roadFeed)` satırının altına:

```swift
                .environmentObject(journal)
```

`.task { ... }` bloğunda `await roadFeed.refresh()` satırının altına:

```swift
                    await journal.drainQueue()
```

`scenePhase` bloğunda `phase == .active` içine, `locationManager.applyPowerMode()` satırının altına:

```swift
                        Task { await journal.drainQueue() }
```

- [ ] **Step 3: Derle**

```bash
cd ios && xcodegen generate >/dev/null && \
xcodebuild -project Kuzey.xcodeproj -scheme Kuzey \
  -sdk iphonesimulator -destination 'id=687D33A5-A851-40B8-9979-743BD38156E5' \
  -configuration Debug build 2>&1 | grep -E "error:|BUILD"
```

Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 4: Commit**

```bash
git add ios/Karavan/Journal/JournalStore.swift ios/Karavan/KaravanApp.swift ios/Kuzey.xcodeproj
git commit -m "feat: cihaz-önce günlük deposu ve kuyruk boşaltma

Kayıt önce diske, sonra buluta. Bulut yazımı başarısız olursa kayıt
kaybolmuyor, kuyrukta geri çekilmeyle bekliyor.

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 4: Sesli dikte motorunu çıkar ve günlük yazma ekranı

`SpeechRecorder` şu an `VoiceExpenseView.swift` içinde gömülü. Günlüğün de aynı motora ihtiyacı var — kopyalamak yerine çıkarılır.

**Files:**
- Create: `ios/Karavan/Journal/SpeechRecorder.swift`
- Modify: `ios/Karavan/Views/Tools/VoiceExpenseView.swift`
- Create: `ios/Karavan/Views/Journal/JournalComposeView.swift`

**Interfaces:**
- Consumes: `JournalStore` (Task 3), `JournalEntry` (Task 1)
- Produces:
  - `@MainActor final class SpeechRecorder: NSObject, ObservableObject` — `@Published var transcript: String`, `@Published var recording: Bool`, `func start() throws`, `func stop()`
  - `struct JournalComposeView: View` — `init(prefillText: String = "")`

- [ ] **Step 1: `SpeechRecorder`'ı kendi dosyasına taşı**

`ios/Karavan/Views/Tools/VoiceExpenseView.swift` dosyasındaki `@MainActor final class SpeechRecorder: NSObject, ObservableObject { ... }` sınıfının tamamını kes ve `ios/Karavan/Journal/SpeechRecorder.swift` dosyasına yapıştır. Dosyanın başına şunları ekle:

```swift
import AVFoundation
import Foundation
import Speech
```

Sınıfın üstüne açıklama ekle:

```swift
// Türkçe sesli dikte. Hem sesli harcama hem günlük kullanır —
// aynı motoru iki yere kopyalamamak için ayrı dosyada.
```

`VoiceExpenseView.swift` içinde artık kullanılmayan `import Speech` ve `import AVFoundation` satırları kalmalı (dosyanın kalanı hâlâ kullanıyor olabilir); derleme hatası verirse kaldır.

- [ ] **Step 2: Taşımanın derlendiğini doğrula**

```bash
cd ios && xcodegen generate >/dev/null && \
xcodebuild -project Kuzey.xcodeproj -scheme Kuzey \
  -sdk iphonesimulator -destination 'id=687D33A5-A851-40B8-9979-743BD38156E5' \
  -configuration Debug build 2>&1 | grep -E "error:|BUILD"
```

Expected: `** BUILD SUCCEEDED **` — davranış değişmedi, yalnızca yer değişti.

- [ ] **Step 3: Yazma ekranını yaz**

`ios/Karavan/Views/Journal/JournalComposeView.swift`:

```swift
import CoreLocation
import SwiftUI

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
        }
        .preferredColorScheme(.dark)
        .onChange(of: speech.transcript) { _, new in
            if !new.isEmpty { text = new }
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
            if speech.recording { speech.stop() } else { try? speech.start() }
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
            Button { showPhotoPicker = true } label: {
                HStack(spacing: 8) {
                    Image(systemName: "photo.badge.plus").font(.system(size: 16))
                    Text("Fotoğraf ekle").font(.system(size: 15, weight: .semibold, design: .rounded))
                    Spacer()
                }
                .foregroundStyle(Theme.c3)
                .padding(13)
                .background(Theme.panel, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .buttonStyle(.plain)
        }
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
```

- [ ] **Step 4: Derle**

Bu adımda `JournalPhotoPicker` henüz yok — Task 5'te gelecek. Geçici olarak derlemenin geçmesi için `ios/Karavan/Views/Journal/JournalPhotoPicker.swift` dosyasını yer tutucu olarak oluştur:

```swift
import SwiftUI

// Task 5'te gerçek seçici ile değiştirilecek.
struct JournalPhotoPicker: View {
    let onPick: ([Data]) -> Void
    var body: some View { Color.clear.onAppear { onPick([]) } }
}
```

```bash
cd ios && xcodegen generate >/dev/null && \
xcodebuild -project Kuzey.xcodeproj -scheme Kuzey \
  -sdk iphonesimulator -destination 'id=687D33A5-A851-40B8-9979-743BD38156E5' \
  -configuration Debug build 2>&1 | grep -E "error:|BUILD"
```

Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 5: Commit**

```bash
git add ios/Karavan/Journal/SpeechRecorder.swift ios/Karavan/Views/Journal ios/Karavan/Views/Tools/VoiceExpenseView.swift ios/Kuzey.xcodeproj
git commit -m "feat: günlük yazma ekranı, sesli dikte ortaklaştırıldı

SpeechRecorder VoiceExpenseView'dan çıkarıldı; harcama ve günlük aynı
Türkçe dikte motorunu kullanıyor.

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 5: Fotoğraf seçici — konumlu fotoğraflar önde

Mevcut `PhotoJournalView` yolculuk penceresindeki konumlu fotoğrafları zaten tarıyor ama hiçbir şey saklamıyor. Aynı mantık seçiciye taşınır.

**Files:**
- Modify: `ios/Karavan/Views/Journal/JournalPhotoPicker.swift` (yer tutucuyu değiştir)

**Interfaces:**
- Consumes: `TripStore` (mevcut)
- Produces: `struct JournalPhotoPicker: View` — `init(onPick: @escaping ([Data]) -> Void)`

- [ ] **Step 1: Gerçek seçiciyi yaz**

`ios/Karavan/Views/Journal/JournalPhotoPicker.swift` içeriğini tamamen şununla değiştir:

```swift
import Photos
import SwiftUI

// Fotoğraf seçici. Yolculuk penceresindeki KONUMLU fotoğraflar önde gelir —
// günlüğe eklenecek fotoğraf büyük ihtimalle yolda çekilmiş olandır.
struct JournalPhotoPicker: View {
    let onPick: ([Data]) -> Void

    @EnvironmentObject var store: TripStore
    @Environment(\.dismiss) private var dismiss

    @State private var assets: [PHAsset] = []
    @State private var selected: Set<String> = []
    @State private var status: PHAuthorizationStatus = .notDetermined

    private let columns = [GridItem(.adaptive(minimum: 100), spacing: 4)]

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.bg.ignoresSafeArea()
                if status == .denied || status == .restricted {
                    deniedState
                } else {
                    ScrollView {
                        LazyVGrid(columns: columns, spacing: 4) {
                            ForEach(assets, id: \.localIdentifier) { asset in
                                thumb(asset)
                            }
                        }
                        .padding(4)
                    }
                }
            }
            .navigationTitle("Fotoğraf seç")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Vazgeç") { dismiss() }.tint(Theme.muted)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Ekle (\(selected.count))") { pickSelected() }
                        .font(.system(size: 15, weight: .bold))
                        .tint(Theme.c2)
                        .disabled(selected.isEmpty)
                }
            }
        }
        .preferredColorScheme(.dark)
        .task { await load() }
    }

    private var deniedState: some View {
        VStack(spacing: 10) {
            Image(systemName: "photo.on.rectangle.angled")
                .font(.system(size: 34)).foregroundStyle(Theme.muted)
            Text("Fotoğraflara erişim kapalı.\nAyarlar → Kuzey → Fotoğraflar'dan açabilirsin.")
                .font(.system(size: 14)).foregroundStyle(Theme.dim)
                .multilineTextAlignment(.center)
        }
        .padding(30)
    }

    private func thumb(_ asset: PHAsset) -> some View {
        let isOn = selected.contains(asset.localIdentifier)
        return PhotoThumb(asset: asset)
            .aspectRatio(1, contentMode: .fill)
            .clipped()
            .overlay(alignment: .topTrailing) {
                Image(systemName: isOn ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 19))
                    .foregroundStyle(isOn ? Theme.c1 : .white.opacity(0.8))
                    .shadow(radius: 2)
                    .padding(5)
            }
            .onTapGesture {
                if isOn { selected.remove(asset.localIdentifier) }
                else { selected.insert(asset.localIdentifier) }
            }
    }

    private func load() async {
        let s = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        status = s
        guard s == .authorized || s == .limited else { return }

        let from = (store.trip?.departureDate ?? Date()).addingTimeInterval(-30 * 86400)
        let options = PHFetchOptions()
        options.predicate = NSPredicate(format: "creationDate >= %@", from as NSDate)
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        options.fetchLimit = 400

        let result = PHAsset.fetchAssets(with: .image, options: options)
        var located: [PHAsset] = []
        var others: [PHAsset] = []
        result.enumerateObjects { asset, _, _ in
            if asset.location != nil { located.append(asset) } else { others.append(asset) }
        }
        assets = located + others   // konumlu olanlar önde
    }

    private func pickSelected() {
        let chosen = assets.filter { selected.contains($0.localIdentifier) }
        Task {
            var out: [Data] = []
            for asset in chosen {
                if let data = await Self.jpeg(from: asset) { out.append(data) }
            }
            onPick(out)
            dismiss()
        }
    }

    /// Fotoğrafı makul boyutta JPEG'e indir — iCloud kotasını ve yüklemeyi hafifletir.
    private static func jpeg(from asset: PHAsset) async -> Data? {
        await withCheckedContinuation { cont in
            let options = PHImageRequestOptions()
            options.isNetworkAccessAllowed = true
            options.deliveryMode = .highQualityFormat
            PHImageManager.default().requestImage(
                for: asset,
                targetSize: CGSize(width: 1600, height: 1600),
                contentMode: .aspectFit,
                options: options
            ) { image, _ in
                cont.resume(returning: image?.jpegData(compressionQuality: 0.8))
            }
        }
    }
}
```

- [ ] **Step 2: Kamera çekimini ekle**

Spec iki fotoğraf kaynağı istiyor: kütüphane ve **anlık kamera çekimi**. Aynı dosyanın sonuna ekle:

```swift
// Anlık çekim. Yolda görülen şeyi hemen günlüğe koyabilmek için —
// önce Fotoğraflar'a kaydedip sonra seçmek fazladan iki adım.
struct JournalCamera: UIViewControllerRepresentable {
    let onCapture: (Data) -> Void
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = UIImagePickerController.isSourceTypeAvailable(.camera) ? .camera : .photoLibrary
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ controller: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        private let parent: JournalCamera
        init(_ parent: JournalCamera) { self.parent = parent }

        func imagePickerController(_ picker: UIImagePickerController,
                                   didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let image = info[.originalImage] as? UIImage,
               let data = image.jpegData(compressionQuality: 0.8) {
                parent.onCapture(data)
            }
            parent.dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }
    }
}
```

`ios/Karavan/Views/Journal/JournalComposeView.swift` içinde `@State private var showPhotoPicker = false` satırının altına ekle:

```swift
    @State private var showCamera = false
```

`photoRow` içindeki `Button { showPhotoPicker = true }` bloğunu şu ikili ile değiştir:

```swift
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
```

`.sheet(isPresented: $showPhotoPicker)` satırının altına ekle:

```swift
            .sheet(isPresented: $showCamera) {
                JournalCamera { data in photos.append(data) }
                    .ignoresSafeArea()
            }
```

- [ ] **Step 3: Derle**

```bash
cd ios && xcodebuild -project Kuzey.xcodeproj -scheme Kuzey \
  -sdk iphonesimulator -destination 'id=687D33A5-A851-40B8-9979-743BD38156E5' \
  -configuration Debug build 2>&1 | grep -E "error:|BUILD"
```

Expected: `** BUILD SUCCEEDED **`

`PhotoThumb` bulunamadı hatası verirse: `PhotoThumb` `PhotoJournalView.swift` içinde tanımlı, aynı hedefte olduğu için erişilebilir olmalı. Erişilemiyorsa `private` olup olmadığını kontrol et ve `private`'ı kaldır.

- [ ] **Step 4: Commit**

```bash
git add ios/Karavan/Views/Journal/JournalPhotoPicker.swift
git commit -m "feat: günlük fotoğraf seçici — konumlu fotoğraflar önde

Yolculuk penceresindeki konumlu fotoğraflar listenin başında; 1600px JPEG'e
indirilerek iCloud kotası ve yükleme süresi hafifletiliyor.

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 6: Günlük zaman çizgisi ve sekme

**Files:**
- Create: `ios/Karavan/Views/Journal/JournalView.swift`
- Modify: `ios/Karavan/ContentView.swift`

**Interfaces:**
- Consumes: `JournalStore` (Task 3), `JournalComposeView` (Task 4)
- Produces: `struct JournalView: View`

- [ ] **Step 1: Zaman çizgisini yaz**

`ios/Karavan/Views/Journal/JournalView.swift`:

```swift
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

    private func cloudWarning(_ message: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.icloud").foregroundStyle(Theme.bad)
            Text(message)
                .font(.system(size: 12)).foregroundStyle(Theme.muted)
            Spacer()
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
```

- [ ] **Step 2: Sekmeyi ekle**

`ios/Karavan/ContentView.swift` içindeki `TabView` bloğuna, mevcut sekmelerin arasına (Araçlar'dan önce) ekle:

```swift
            JournalView()
                .tabItem { Label("Günlük", systemImage: "book.closed.fill") }
```

- [ ] **Step 3: Derle ve simülatörde aç**

```bash
cd ios && xcodebuild -project Kuzey.xcodeproj -scheme Kuzey \
  -sdk iphonesimulator -destination 'id=687D33A5-A851-40B8-9979-743BD38156E5' \
  -configuration Debug build 2>&1 | grep -E "error:|BUILD"

APP=$(find ~/Library/Developer/Xcode/DerivedData/Kuzey-*/Build/Products/Debug-iphonesimulator -name "Kuzey.app" | head -1)
xcrun simctl install 687D33A5-A851-40B8-9979-743BD38156E5 "$APP"
xcrun simctl launch 687D33A5-A851-40B8-9979-743BD38156E5 com.bilalsenturk.kuzey
```

Expected: `** BUILD SUCCEEDED **`, app açılır, "Günlük" sekmesi görünür, boş durum metni okunur.

- [ ] **Step 4: Commit**

```bash
git add ios/Karavan/Views/Journal/JournalView.swift ios/Karavan/ContentView.swift ios/Kuzey.xcodeproj
git commit -m "feat: günlük zaman çizgisi ve sekmesi

Her kayıtta kilit/paylaşım rozeti; iCloud kapalıysa ve kuyrukta bekleyen
kayıt varsa kullanıcı bunu görüyor.

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 7: Paylaşılan kayıtların web'e yansıması

**Files:**
- Create: `src/pages/api/journal.ts`
- Modify: `ios/Karavan/Config.swift`
- Modify: `ios/Karavan/Journal/JournalStore.swift`

**Interfaces:**
- Consumes: `JournalStore.setShared` (Task 3)
- Produces:
  - `Config.journalPostURL: URL?`
  - `JournalStore.publishShared()` — paylaşılan kayıtları Blob'a gönderir

- [ ] **Step 1: Uç noktayı yaz**

`src/pages/api/journal.ts`:

```typescript
import type { APIRoute } from 'astro';
import { put, head } from '@vercel/blob';

export const prerender = false;

// PAYLAŞILAN günlük kayıtları. Gizli kayıtlar buraya asla gelmez —
// app yalnızca isShared=true olanları gönderir.
//
// POST: app (x-live-secret) yazar. GET: site okur.

const BLOB_PATH = 'kuzey/journal.json';

const jsonHeaders = {
  'Content-Type': 'application/json',
  'Cache-Control': 'no-store',
  'Access-Control-Allow-Origin': '*',
};

let memRecord: string | null = null;

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), { status, headers: jsonHeaders });
}

export const POST: APIRoute = async ({ request }) => {
  const secret = import.meta.env.LIVE_POST_SECRET;
  if (!secret || request.headers.get('x-live-secret') !== secret) {
    return json({ error: 'unauthorized' }, 401);
  }

  let body: { entries?: unknown };
  try {
    body = await request.json();
  } catch {
    return json({ error: 'bad json' }, 400);
  }

  if (!Array.isArray(body.entries)) {
    return json({ error: 'bad entries' }, 400);
  }

  const entries = body.entries
    .filter((e): e is Record<string, unknown> => typeof e === 'object' && e !== null)
    .map((e) => ({
      id: String(e.id ?? ''),
      text: String(e.text ?? ''),
      createdAt: typeof e.createdAt === 'string' ? e.createdAt : null,
      author: typeof e.author === 'string' ? e.author : null,
      mood: typeof e.mood === 'string' ? e.mood : null,
      stopId: typeof e.stopId === 'string' ? e.stopId : null,
    }))
    .filter((e) => e.id && e.text && e.createdAt);

  const payload = JSON.stringify({ entries, updatedAt: new Date().toISOString() });

  if (import.meta.env.BLOB_READ_WRITE_TOKEN) {
    await put(BLOB_PATH, payload, {
      access: 'public',
      addRandomSuffix: false,
      allowOverwrite: true,
      contentType: 'application/json',
    });
  } else {
    memRecord = payload;
  }

  return json({ ok: true, count: entries.length });
};

export const GET: APIRoute = async () => {
  if (!import.meta.env.BLOB_READ_WRITE_TOKEN) {
    return memRecord
      ? new Response(memRecord, { headers: jsonHeaders })
      : json({ error: 'no data yet' }, 404);
  }
  try {
    const meta = await head(BLOB_PATH);
    const res = await fetch(meta.downloadUrl, { cache: 'no-store' });
    return new Response(await res.text(), { headers: jsonHeaders });
  } catch {
    return json({ error: 'no data yet' }, 404);
  }
};
```

- [ ] **Step 2: Uç noktayı doğrula**

```bash
SECRET=$(grep -m1 "LIVE_POST_SECRET" .env | cut -d= -f2- | tr -d '"'"'"' ')
printf "yetkisiz → "; curl -s -o /dev/null -w "%{http_code}\n" -X POST http://localhost:4321/api/journal -H "Content-Type: application/json" -d '{"entries":[]}'
printf "yetkili  → "; curl -s -o /dev/null -w "%{http_code}\n" -X POST http://localhost:4321/api/journal -H "Content-Type: application/json" -H "x-live-secret: $SECRET" -d '{"entries":[{"id":"a","text":"deneme","createdAt":"2026-08-04T10:00:00Z"}]}'
printf "bozuk    → "; curl -s -o /dev/null -w "%{http_code}\n" -X POST http://localhost:4321/api/journal -H "Content-Type: application/json" -H "x-live-secret: $SECRET" -d '{"entries":"hayır"}'
curl -s http://localhost:4321/api/journal
```

Expected: `401`, `200`, `400`, ardından `{"entries":[{"id":"a",...}],"updatedAt":...}`

- [ ] **Step 3: Config'e URL ekle**

`ios/Karavan/Config.swift` içinde `editsURL` tanımının altına:

```swift
    /// Paylaşılan günlük kayıtlarının web'e gönderileceği uç nokta.
    static var journalPostURL: URL? { siteURL?.appendingPathComponent("api/journal") }
```

- [ ] **Step 4: Yayınlamayı depoya bağla**

`ios/Karavan/Journal/JournalStore.swift` içine, `drainQueue()` metodunun altına ekle:

```swift
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
```

`setShared(_:shared:)` metodunun sonuna, `Task { await drainQueue() }` satırının altına ekle:

```swift
        publishShared()
```

`delete(_:)` metodunun sonuna, `Task { try? await JournalCloud... }` satırının altına ekle:

```swift
        publishShared()   // paylaşılmış kayıt silindiyse web'den de düşsün
```

- [ ] **Step 5: Derle**

```bash
cd ios && xcodebuild -project Kuzey.xcodeproj -scheme Kuzey \
  -sdk iphonesimulator -destination 'id=687D33A5-A851-40B8-9979-743BD38156E5' \
  -configuration Debug build 2>&1 | grep -E "error:|BUILD"
```

Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 6: Commit**

```bash
git add src/pages/api/journal.ts ios/Karavan/Config.swift ios/Karavan/Journal/JournalStore.swift
git commit -m "feat: paylaşılan günlük kayıtları web'e yansıyor

Yalnızca isShared=true kayıtlar gönderilir; gizli kayıt cihazdan çıkmaz.
Paylaşılan kayıt silindiğinde web'den de düşer.

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 8: Apple öneri seçicisi (iOS 17.2+)

**Files:**
- Modify: `ios/Karavan/Views/Journal/JournalComposeView.swift`

**Interfaces:**
- Consumes: `JournalComposeView` (Task 4)
- Produces: yok (mevcut ekrana eklenti)

- [ ] **Step 1: Öneri seçicisini ekle**

`ios/Karavan/Views/Journal/JournalComposeView.swift` dosyasının en üstüne ekle:

```swift
#if canImport(JournalingSuggestions)
import JournalingSuggestions
#endif
```

`photoRow` tanımının altına ekle:

```swift
    // Apple'ın öneri seçicisi (iOS 17.2+). Ayrı süreçte koşar; yalnızca
    // kullanıcının seçtiği içerik app'e geçer, ayrı ayrı izin istenmez.
    // NOT: Apple'ın Günlük UYGULAMASINA yazmak mümkün değil — bu API tek yönlü.
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
                        if text.isEmpty { text = title }
                        else { text += "\n\n\(title)" }
                    }
                }
                .buttonStyle(.plain)
            }
        }
        #endif
    }
```

`body` içindeki `VStack` bloğunda `photoRow` satırının altına ekle:

```swift
                        suggestionsRow
```

- [ ] **Step 2: Derle**

```bash
cd ios && xcodebuild -project Kuzey.xcodeproj -scheme Kuzey \
  -sdk iphonesimulator -destination 'id=687D33A5-A851-40B8-9979-743BD38156E5' \
  -configuration Debug build 2>&1 | grep -E "error:|BUILD"
```

Expected: `** BUILD SUCCEEDED **`

Derleme `JournalingSuggestions` bulunamadı derse: çerçeve yalnızca gerçek cihaz SDK'sında olabilir. `#if canImport` koruması bunu zaten halleder; hata sürerse `project.yml` içindeki `Kuzey` hedefine `dependencies: - sdk: JournalingSuggestions.framework` ekle ve `xcodegen generate` çalıştır.

- [ ] **Step 3: Commit**

```bash
git add ios/Karavan/Views/Journal/JournalComposeView.swift
git commit -m "feat: Apple öneri seçicisi günlüğe bağlandı

iOS 17.2+ koşullu. Apple'ın Günlük uygulamasına yazmak API olarak mümkün
değil; bu çerçeve yalnızca önerileri içeri taşıyor.

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 9: Bildirim kuralları ve disiplini

Tetik kararları saf fonksiyonlar olarak yazılır — konum, hava veya kur bilgisi girdi, "bildirim gönderilsin mi" çıktı. Bu ayrım kuralların cihazsız test edilmesini sağlar.

**Files:**
- Create: `ios/Karavan/Notifications/NotificationRules.swift`
- Create: `ios/Karavan/Notifications/NotificationBudget.swift`
- Create: `ios/Tests/notification-rules-check.swift`
- Create: `ios/Tests/run-notification-check.sh`

**Interfaces:**
- Consumes: yok
- Produces:
  - `enum NotifKind: String, CaseIterable { case borderApproach, driveBreak, arrivalSoon, currencyJump, fuelPrice, journalReminder, dailySummary, lowBattery }`
  - `extension NotifKind { var isCritical: Bool }`
  - `enum NotificationRules` — saf statik fonksiyonlar:
    - `static func borderApproach(distanceKm: Double) -> Bool`
    - `static func driveBreak(continuousDriveSeconds: TimeInterval) -> Bool`
    - `static func arrivalSoon(remainingKm: Double) -> Bool`
    - `static func currencyJump(previous: Double, current: Double) -> Bool`
    - `static func fuelCheaper(here: Double, next: Double) -> Int?`
    - `static func lowBattery(level: Float, navigating: Bool) -> Bool`
  - `struct NotificationBudget` — `mutating func allow(_ kind: NotifKind, now: Date) -> Bool`, sabitler `cooldown`, `criticalCooldown`

- [ ] **Step 1: Kural testlerini yaz**

`ios/Tests/notification-rules-check.swift`:

```swift
import Foundation

var failures = 0
func check(_ name: String, _ condition: Bool, _ detail: String = "") {
    if condition { print("  ✓ \(name)") }
    else { failures += 1; print("  ✗ \(name) \(detail)") }
}

let t0 = Date(timeIntervalSince1970: 1_780_000_000)

print("\n=== 1) Sınır yaklaşımı 30 km ===")
check("35 km'de tetiklenmez", NotificationRules.borderApproach(distanceKm: 35) == false)
check("30 km'de tetiklenir", NotificationRules.borderApproach(distanceKm: 30) == true)
check("12 km'de tetiklenir", NotificationRules.borderApproach(distanceKm: 12) == true)

print("\n=== 2) Sürüş molası 2 saat ===")
check("90 dakikada tetiklenmez", NotificationRules.driveBreak(continuousDriveSeconds: 90 * 60) == false)
check("2 saatte tetiklenir", NotificationRules.driveBreak(continuousDriveSeconds: 120 * 60) == true)

print("\n=== 3) Varışa 50 km ===")
check("60 km'de tetiklenmez", NotificationRules.arrivalSoon(remainingKm: 60) == false)
check("50 km'de tetiklenir", NotificationRules.arrivalSoon(remainingKm: 50) == true)

print("\n=== 4) Kur sıçraması %3 ===")
check("%2 sıçrama sayılmaz", NotificationRules.currencyJump(previous: 50.0, current: 51.0) == false)
check("%4 sıçrama sayılır", NotificationRules.currencyJump(previous: 50.0, current: 52.0) == true)
check("%4 düşüş de sayılır", NotificationRules.currencyJump(previous: 52.0, current: 50.0) == true)
check("sıfır bölme çökmez", NotificationRules.currencyJump(previous: 0, current: 50) == false)

print("\n=== 5) Yakıt farkı ===")
check("burası %12 ucuzsa yüzde döner",
      NotificationRules.fuelCheaper(here: 1.76, next: 2.0) == 12,
      String(describing: NotificationRules.fuelCheaper(here: 1.76, next: 2.0)))
check("fark küçükse nil", NotificationRules.fuelCheaper(here: 1.98, next: 2.0) == nil)
check("burası pahalıysa nil", NotificationRules.fuelCheaper(here: 2.2, next: 2.0) == nil)

print("\n=== 6) Düşük pil yalnızca navigasyondayken ===")
check("navigasyon kapalıyken uyarmaz", NotificationRules.lowBattery(level: 0.15, navigating: false) == false)
check("navigasyon açıkken uyarır", NotificationRules.lowBattery(level: 0.15, navigating: true) == true)
check("pil yüksekse uyarmaz", NotificationRules.lowBattery(level: 0.55, navigating: true) == false)

print("\n=== 7) Bütçe: aynı türden art arda bildirim yok ===")
var budget = NotificationBudget()
check("ilk bildirim geçer", budget.allow(.journalReminder, now: t0) == true)
check("hemen ikincisi geçmez", budget.allow(.journalReminder, now: t0.addingTimeInterval(60)) == false)
let afterCooldown = t0.addingTimeInterval(NotificationBudget.cooldown + 1)
check("bekleme sonrası geçer", budget.allow(.journalReminder, now: afterCooldown) == true)

print("\n=== 8) Farklı türler birbirini engellemez ===")
var b2 = NotificationBudget()
_ = b2.allow(.journalReminder, now: t0)
check("başka tür aynı anda geçer", b2.allow(.borderApproach, now: t0) == true)

print("\n=== 9) Kritik bildirimler daha kısa beklemeye tabi ===")
check("kritik tür işaretli", NotifKind.borderApproach.isCritical == true)
check("hatırlatma kritik değil", NotifKind.journalReminder.isCritical == false)
var b3 = NotificationBudget()
_ = b3.allow(.borderApproach, now: t0)
let afterCritical = t0.addingTimeInterval(NotificationBudget.criticalCooldown + 1)
check("kritik bekleme daha kısa", NotificationBudget.criticalCooldown < NotificationBudget.cooldown)
check("kritik bekleme sonrası geçer", b3.allow(.borderApproach, now: afterCritical) == true)

print(failures == 0 ? "\n✅ hepsi geçti\n" : "\n❌ \(failures) başarısız\n")
exit(failures == 0 ? 0 : 1)
```

- [ ] **Step 2: Koşucuyu yaz**

`ios/Tests/run-notification-check.sh`:

```bash
#!/usr/bin/env bash
# Bildirim kuralları ve disiplini doğrulaması (UI'sız).
#   ./ios/Tests/run-notification-check.sh
set -e
DIR="$(cd "$(dirname "$0")" && pwd)"
SRC="$DIR/../Karavan"
OUT="$(mktemp -d)"
swiftc -O -o "$OUT/notifcheck" \
  "$DIR/notification-rules-check.swift" \
  "$SRC/Notifications/NotificationRules.swift" \
  "$SRC/Notifications/NotificationBudget.swift"
"$OUT/notifcheck"
```

```bash
chmod +x ios/Tests/run-notification-check.sh
```

- [ ] **Step 3: Testi çalıştır, başarısız olduğunu gör**

Run: `./ios/Tests/run-notification-check.sh`
Expected: FAIL — `error: cannot find 'NotificationRules' in scope`

- [ ] **Step 4: Kuralları yaz**

`ios/Karavan/Notifications/NotificationRules.swift`:

```swift
import Foundation

// Bildirim türleri. Kritik olanlar daha kısa bekleme süresine tabidir —
// sınıra yaklaşırken belge hatırlatması gecikirse işe yaramaz.
enum NotifKind: String, CaseIterable {
    case borderApproach, driveBreak, arrivalSoon
    case currencyJump, fuelPrice
    case journalReminder, dailySummary, lowBattery

    var isCritical: Bool {
        switch self {
        case .borderApproach, .lowBattery: return true
        default: return false
        }
    }
}

// Tetik kararları — SAF fonksiyonlar. Konum/hava/kur girdi, evet-hayır çıktı.
// UI ve sistem API'lerinden ayrı olduğu için cihazsız test edilebiliyor.
enum NotificationRules {
    static func borderApproach(distanceKm: Double) -> Bool {
        distanceKm <= 30
    }

    static func driveBreak(continuousDriveSeconds: TimeInterval) -> Bool {
        continuousDriveSeconds >= 2 * 3600
    }

    static func arrivalSoon(remainingKm: Double) -> Bool {
        remainingKm <= 50
    }

    /// %3 ve üzeri değişim — iki yönde de.
    static func currencyJump(previous: Double, current: Double) -> Bool {
        guard previous > 0 else { return false }
        return abs(current - previous) / previous >= 0.03
    }

    /// Buradaki yakıt sıradaki ülkeden en az %5 ucuzsa yüzde farkını döndürür.
    static func fuelCheaper(here: Double, next: Double) -> Int? {
        guard next > 0, here < next else { return nil }
        let pct = Int(((next - here) / next * 100).rounded())
        return pct >= 5 ? pct : nil
    }

    /// Yalnızca navigasyon açıkken uyarılır — telefon cepteyken %20 pil sorun değil.
    static func lowBattery(level: Float, navigating: Bool) -> Bool {
        navigating && level <= 0.20
    }
}
```

- [ ] **Step 5: Bütçeyi yaz**

`ios/Karavan/Notifications/NotificationBudget.swift`:

```swift
import Foundation

// Bildirim disiplini. Yolculuk sekiz gün sürüyor; bildirim yorgunluğu
// gerçek bir risk — yorulan kullanıcı hepsini kapatır ve kritik olanı da
// kaçırır. Anons motorundaki (AnnouncementEngine) kısıtlama mantığının eşi.
struct NotificationBudget {
    /// Normal bildirimler: aynı türden 45 dakikada bir.
    static let cooldown: TimeInterval = 45 * 60
    /// Kritik bildirimler: aynı türden 10 dakikada bir.
    static let criticalCooldown: TimeInterval = 10 * 60

    private var lastSent: [String: Date] = [:]

    mutating func allow(_ kind: NotifKind, now: Date) -> Bool {
        let limit = kind.isCritical ? Self.criticalCooldown : Self.cooldown
        if let last = lastSent[kind.rawValue], now.timeIntervalSince(last) < limit {
            return false
        }
        lastSent[kind.rawValue] = now
        return true
    }
}
```

- [ ] **Step 6: Testi çalıştır, geçtiğini doğrula**

Run: `./ios/Tests/run-notification-check.sh`
Expected: PASS — `✅ hepsi geçti`, 22 kontrolün tamamı `✓`

- [ ] **Step 7: Commit**

```bash
git add ios/Karavan/Notifications ios/Tests/notification-rules-check.swift ios/Tests/run-notification-check.sh
git commit -m "feat: bildirim kuralları ve disiplini

Tetik kararları saf fonksiyon; cihazsız test ediliyor. Bütçe katmanı aynı
türden art arda bildirimi engelliyor — sekiz günlük yolculukta bildirim
yorgunluğu kritik olanı da kaçırtır.

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 10: Kuralları canlı veriye bağla

**Files:**
- Create: `ios/Karavan/Notifications/TripNotifier.swift`
- Modify: `ios/Karavan/LocationManager.swift`
- Modify: `ios/Karavan/KaravanApp.swift`

**Interfaces:**
- Consumes: `NotificationRules`, `NotificationBudget`, `NotifKind` (Task 9), `NotificationManager` (mevcut)
- Produces:
  - `@MainActor final class TripNotifier: ObservableObject` — `static let shared`
  - `func onLocation(remainingKm: Int?, nextStopName: String?, speedKmh: Int?, now: Date)`
  - `func onCurrency(previous: Double, current: Double, code: String)`
  - `func onFuel(here: Double, next: Double, hereCountry: String, nextCountry: String)`
  - `func checkBattery(navigating: Bool)`

- [ ] **Step 1: Bağlayıcı katmanı yaz**

`ios/Karavan/Notifications/TripNotifier.swift`:

```swift
import Foundation
import UIKit

// Saf kuralları canlı veriye bağlar. Kural mantığı burada YOK —
// yalnızca "veri geldi → kurala sor → bütçeye sor → bildir" akışı.
@MainActor
final class TripNotifier: ObservableObject {
    static let shared = TripNotifier()

    private var budget = NotificationBudget()
    private var driveStartedAt: Date?
    private var lastMovingAt: Date?

    private init() {
        UIDevice.current.isBatteryMonitoringEnabled = true
    }

    // MARK: - Konum tabanlı

    func onLocation(remainingKm: Int?, nextStopName: String?, speedKmh: Int?, now: Date = Date()) {
        trackDriving(speedKmh: speedKmh, now: now)

        if let km = remainingKm, let name = nextStopName {
            if NotificationRules.arrivalSoon(remainingKm: Double(km)),
               budget.allow(.arrivalSoon, now: now) {
                NotificationManager.shared.notify(
                    title: "\(name)'a 50 km",
                    body: "Kamp yerini şimdi aramaya başla — akşam yer bulmak zor."
                )
            }
        }

        if let seconds = continuousDriveSeconds(now: now),
           NotificationRules.driveBreak(continuousDriveSeconds: seconds),
           budget.allow(.driveBreak, now: now) {
            NotificationManager.shared.notify(
                title: "İki saattir yoldasın",
                body: "Mola ver: bacaklarını aç, su iç, gözlerini dinlendir."
            )
            driveStartedAt = now   // sayacı sıfırla
        }
    }

    /// Sınıra yaklaşım — çağıran taraf mesafeyi hesaplar.
    func onBorderDistance(_ km: Double, countryName: String, now: Date = Date()) {
        guard NotificationRules.borderApproach(distanceKm: km),
              budget.allow(.borderApproach, now: now) else { return }
        NotificationManager.shared.notify(
            title: "\(countryName) sınırı \(Int(km)) km",
            body: "Pasaport, ruhsat, yeşil kart ve vinyet hazır mı?"
        )
    }

    // MARK: - Para

    func onCurrency(previous: Double, current: Double, code: String, now: Date = Date()) {
        guard NotificationRules.currencyJump(previous: previous, current: current),
              budget.allow(.currencyJump, now: now) else { return }
        let direction = current > previous ? "yükseldi" : "düştü"
        NotificationManager.shared.notify(
            title: "\(code) \(direction)",
            body: String(format: "%.2f → %.2f. Bozdurma planını gözden geçir.", previous, current)
        )
    }

    func onFuel(here: Double, next: Double, hereCountry: String, nextCountry: String, now: Date = Date()) {
        guard let pct = NotificationRules.fuelCheaper(here: here, next: next),
              budget.allow(.fuelPrice, now: now) else { return }
        NotificationManager.shared.notify(
            title: "Burada dizel %\(pct) ucuz",
            body: "\(hereCountry) · \(nextCountry)'dan ucuz. Depoyu burada doldur."
        )
    }

    // MARK: - Pil

    func checkBattery(navigating: Bool, now: Date = Date()) {
        let level = UIDevice.current.batteryLevel
        guard level >= 0,   // -1 = bilinmiyor
              NotificationRules.lowBattery(level: level, navigating: navigating),
              budget.allow(.lowBattery, now: now) else { return }
        NotificationManager.shared.notify(
            title: "Pil %\(Int(level * 100))",
            body: "Navigasyon açık. Şarja tak — haritasız kalmak istemezsin."
        )
    }

    // MARK: - Sürüş süresi takibi

    private func trackDriving(speedKmh: Int?, now: Date) {
        let moving = (speedKmh ?? 0) >= 20
        if moving {
            if driveStartedAt == nil { driveStartedAt = now }
            lastMovingAt = now
        } else if let last = lastMovingAt, now.timeIntervalSince(last) > 10 * 60 {
            // 10 dakikadan uzun duraklama = mola sayılır, sayaç sıfırlanır
            driveStartedAt = nil
            lastMovingAt = nil
        }
    }

    private func continuousDriveSeconds(now: Date) -> TimeInterval? {
        guard let start = driveStartedAt else { return nil }
        return now.timeIntervalSince(start)
    }
}
```

- [ ] **Step 2: Konum akışına bağla**

`ios/Karavan/LocationManager.swift` içinde, `nav?.update(...)` çağrısının bulunduğu bloğu bul (yaklaşık satır 111) ve hemen altına ekle:

```swift
            await MainActor.run {
                TripNotifier.shared.onLocation(
                    remainingKm: self.nav?.remainingKm,
                    nextStopName: self.nav?.nextStop?.name,
                    speedKmh: self.speedKmh
                )
                TripNotifier.shared.checkBattery(navigating: self.nav?.nextStop != nil)
            }
```

- [ ] **Step 3: Sınır yaklaşımını bağla**

`onBorderDistance` çağrılmazsa sınır bildirimi hiç tetiklenmez. Sınırın tam koordinatı elimizde yok; sıradaki durağın ülkesi bulunduğun ülkeden farklıysa o etapta bir sınır var demektir ve mesafe o durağa olan mesafeyle yaklaşık alınır.

`ios/Karavan/Notifications/TripNotifier.swift` içinde `onLocation` metodunun sonuna (kapanış parantezinden önce) ekle:

```swift
        // Sınır yaklaşımı — yaklaşık: sıradaki durak farklı ülkedeyse
        // o etapta sınır var, mesafe durağa olan mesafeyle tahmin edilir.
        if let km = remainingKm, let country = nextCountry, country != currentCountry {
            onBorderDistance(Double(km), countryName: country, now: now)

            // Sınırı geçmeden önce: buradaki dizel sıradaki ülkeden ucuz mu?
            if let hereCode = currentCode, let nextCode = nextCountryCode,
               let here = fuelPrices[hereCode], let next = fuelPrices[nextCode] {
                onFuel(here: here, next: next,
                       hereCountry: currentCountry ?? hereCode,
                       nextCountry: country, now: now)
            }
        }
```

`onLocation` imzasını genişlet:

```swift
    func onLocation(remainingKm: Int?, nextStopName: String?, speedKmh: Int?,
                    currentCountry: String? = nil, nextCountry: String? = nil,
                    currentCode: String? = nil, nextCountryCode: String? = nil,
                    now: Date = Date()) {
```

Yakıt fiyatı deposunu da ekle — `private var lastMovingAt: Date?` satırının altına:

```swift
    /// Ülke kodu → €/L dizel. RoadFeedService besler.
    private var fuelPrices: [String: Double] = [:]
```

Ve `TripNotifier` içine setter ekle (`checkBattery` metodunun altına):

```swift
    func updateFuelPrices(_ prices: [FuelPrice]) {
        fuelPrices = Dictionary(uniqueKeysWithValues: prices.map { ($0.country, $0.dieselEur) })
    }
```

- [ ] **Step 4: Kur ve yakıt tetiklerini bağla**

`ios/Karavan/RoadFeedService.swift` içinde `@Published private(set) var updatedAt: Date?` satırının altına ekle:

```swift
    /// Bir önceki çekimdeki kurlar — sıçrama tespiti için.
    private var previousRates: [String: Double] = [:]
```

`refresh(force:)` metodunun sonunda, `feed` atandıktan sonra ekle:

```swift
        // Kur sıçraması bildirimi + yakıt fiyatlarını bildirim katmanına ver.
        if let feed {
            for (code, rate) in feed.rates {
                if let old = previousRates[code] {
                    TripNotifier.shared.onCurrency(previous: old, current: rate, code: code)
                }
            }
            previousRates = feed.rates

            // Yakıt karşılaştırması konumu bilmeyi gerektiriyor; fiyatları
            // bildirim katmanına verip kararı orada veriyoruz.
            TripNotifier.shared.updateFuelPrices(feed.fuel)
        }
```

`ios/Karavan/LocationManager.swift` içinde Step 2'de eklediğin `TripNotifier.shared.onLocation(...)` çağrısını ülke bilgisiyle genişlet:

```swift
                TripNotifier.shared.onLocation(
                    remainingKm: self.nav?.remainingKm,
                    nextStopName: self.nav?.nextStop?.name,
                    speedKmh: self.speedKmh,
                    currentCountry: self.currentStop()?.country,
                    nextCountry: self.nav?.nextStop?.country,
                    currentCode: self.currentStop()?.code,
                    nextCountryCode: self.nav?.nextStop?.code
                )
```

Aynı dosyaya yardımcı metodu ekle (`distanceKm(to:)` metodunun altına):

```swift
    /// Bulunduğun etabın BAŞLANGIÇ durağı — sınır geçişi ve yakıt karşılaştırması için.
    func currentStop() -> Stop? {
        guard let stops = trip?.trip?.stops, let leg = nav?.currentLegIndex,
              stops.indices.contains(leg) else { return nil }
        return stops[leg]
    }
```

**Not:** `Stop.code` ülke adını koda çeviriyor (`Models.swift:55`), `FuelPrice.country` da ülke kodu (`TR`, `BG`, `RO`) — ikisi aynı alfabede, doğrudan eşleşiyor.

- [ ] **Step 5: Derle**

```bash
cd ios && xcodegen generate >/dev/null && \
xcodebuild -project Kuzey.xcodeproj -scheme Kuzey \
  -sdk iphonesimulator -destination 'id=687D33A5-A851-40B8-9979-743BD38156E5' \
  -configuration Debug build 2>&1 | grep -E "error:|BUILD"
```

Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 6: Commit**

```bash
git add ios/Karavan/Notifications/TripNotifier.swift ios/Karavan/LocationManager.swift ios/Karavan/RoadFeedService.swift ios/Kuzey.xcodeproj
git commit -m "feat: bildirim kuralları canlı konuma bağlandı

Varışa 50 km, iki saatlik sürüş molası, düşük pil. Sürüş sayacı 10 dakikayı
aşan duraklamada sıfırlanıyor — mola verildiyse süre baştan sayılmalı.

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 11: Akşam günlük hatırlatması ve gün özeti

**Files:**
- Modify: `ios/Karavan/Notifications.swift`
- Modify: `ios/Karavan/KaravanApp.swift`

**Interfaces:**
- Consumes: `NotificationManager` (mevcut), `JournalStore` (Task 3)
- Produces: `NotificationManager.scheduleDailyJournalReminder(hour:)`, `NotificationManager.scheduleDailySummary(hour:)`

- [ ] **Step 1: Günlük tekrarlayan bildirimleri ekle**

`ios/Karavan/Notifications.swift` içinde `scheduleDepartureReminders` metodunun altına ekle:

```swift
    /// Her akşam "bugünü günlüğe yaz" hatırlatması. Tekrarlayan; bir kez kurulur.
    func scheduleDailyJournalReminder(hour: Int = 21) {
        let id = "journal-daily"
        center.removePendingNotificationRequests(withIdentifiers: [id])

        let content = UNMutableNotificationContent()
        content.title = "Bugünü yaz"
        content.body = "Bugün ne oldu? Bir iki cümle bile yeter — istersen sesli."
        content.sound = .default

        var components = DateComponents()
        components.hour = hour
        components.minute = 0

        center.add(UNNotificationRequest(
            identifier: id,
            content: content,
            trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
        ))
    }

    /// Sabah gün özeti. İçerik gönderim anında değil kurulum anında sabitlenir;
    /// canlı veri gerektiren kısımlar app açılınca güncellenir.
    func scheduleDailySummary(hour: Int = 8) {
        let id = "summary-daily"
        center.removePendingNotificationRequests(withIdentifiers: [id])

        let content = UNMutableNotificationContent()
        content.title = "Bugünün planı"
        content.body = "Kuzey'i aç: sıradaki durak, hava ve kalan mesafe seni bekliyor."
        content.sound = .default

        var components = DateComponents()
        components.hour = hour
        components.minute = 0

        center.add(UNNotificationRequest(
            identifier: id,
            content: content,
            trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
        ))
    }
```

- [ ] **Step 2: Açılışta kur**

`ios/Karavan/KaravanApp.swift` içindeki `.task { ... }` bloğunda `BackgroundWeather.schedule()` satırının hemen üstüne ekle:

```swift
                    NotificationManager.shared.scheduleDailyJournalReminder()
                    NotificationManager.shared.scheduleDailySummary()
```

- [ ] **Step 3: Derle ve bildirimlerin kurulduğunu doğrula**

```bash
cd ios && xcodebuild -project Kuzey.xcodeproj -scheme Kuzey \
  -sdk iphonesimulator -destination 'id=687D33A5-A851-40B8-9979-743BD38156E5' \
  -configuration Debug build 2>&1 | grep -E "error:|BUILD"

APP=$(find ~/Library/Developer/Xcode/DerivedData/Kuzey-*/Build/Products/Debug-iphonesimulator -name "Kuzey.app" | head -1)
xcrun simctl install 687D33A5-A851-40B8-9979-743BD38156E5 "$APP"
xcrun simctl launch 687D33A5-A851-40B8-9979-743BD38156E5 com.bilalsenturk.kuzey
```

Expected: `** BUILD SUCCEEDED **`, app açılır ve çökmez.

- [ ] **Step 4: Tüm testleri çalıştır**

```bash
./ios/Tests/run-planner-check.sh && \
./ios/Tests/run-journal-check.sh && \
./ios/Tests/run-notification-check.sh
```

Expected: üçü de `✅ hepsi geçti`

- [ ] **Step 5: Commit**

```bash
git add ios/Karavan/Notifications.swift ios/Karavan/KaravanApp.swift
git commit -m "feat: akşam günlük hatırlatması ve sabah gün özeti

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 12: Gerçek cihaz doğrulaması

Simülatör bu özelliklerin hiçbirini gerçekten test edemez: CloudKit iCloud oturumu ister, mikrofon davranışı farklıdır, fotoğraf kütüphanesi boştur, pil seviyesi sahtedir. Bu projede iki hata yalnızca gerçek cihazda ortaya çıktı.

**Files:** yok (doğrulama görevi)

- [ ] **Step 1: Cihaza kur**

```bash
cd ios && rm -rf /tmp/Kuzey-verify.xcarchive && \
xcodebuild -project Kuzey.xcodeproj -scheme Kuzey \
  -destination 'generic/platform=iOS' -configuration Release \
  -allowProvisioningUpdates archive -archivePath /tmp/Kuzey-verify.xcarchive \
  2>&1 | grep -E "error:|ARCHIVE"

xcrun devicectl device install app --device 00008112-001909343EC3C01E \
  /tmp/Kuzey-verify.xcarchive/Products/Applications/Kuzey.app 2>&1 | grep -E "App installed|ERROR"

xcrun devicectl device process launch --device 00008112-001909343EC3C01E com.bilalsenturk.kuzey
```

Expected: `** ARCHIVE SUCCEEDED **`, `App installed:`, `Launched application`

- [ ] **Step 2: Açılışta çökme olmadığını doğrula**

```bash
sleep 12
xcrun devicectl device info processes --device 00008112-001909343EC3C01E 2>/dev/null | grep "Kuzey.app/Kuzey"
```

Expected: bir PID satırı döner. Boşsa app çökmüştür — `--console` ile yeniden başlatıp sinyali oku. `signal 6` (SIGABRT) genelde eksik usage description demektir.

- [ ] **Step 3: Elle doğrulama listesi**

Cihazda sırayla dene ve her birini işaretle:

- [ ] Günlük sekmesi açılıyor, boş durum metni okunuyor
- [ ] Kalem düğmesi → yazma ekranı açılıyor
- [ ] "Sesli yaz" → mikrofon izni isteniyor → Türkçe konuşma metne dönüyor
- [ ] Fotoğraf ekle → seçici açılıyor → yolda çekilmiş konumlu fotoğraflar listenin başında
- [ ] Kaydet → kayıt zaman çizgisinde görünüyor, kilit rozeti var
- [ ] Uçak modu aç → yeni kayıt oluştur → "1 kayıt yüklenmeyi bekliyor" görünüyor
- [ ] Uçak modu kapat → app'i arka plana al ve geri getir → bekleyen sayısı sıfırlanıyor
- [ ] Bir kaydı paylaş → web sitesinde `/api/journal` çıktısında görünüyor
- [ ] Paylaşımı kaldır → web'den düşüyor
- [ ] iOS 17.2+ ise: "Apple önerilerinden ekle" düğmesi görünüyor ve seçici açılıyor

- [ ] **Step 4: Paylaşımın web'e ulaştığını doğrula**

```bash
curl -s https://istanbul-letonya-karavan-astro.vercel.app/api/journal | head -c 400
```

Expected: paylaşılan kaydın `id`, `text` ve `createdAt` alanları görünür. Gizli kayıtların metni **görünmemeli**.

- [ ] **Step 5: TestFlight'a gönder**

```bash
./tools/testflight.sh
```

Expected: `✓ yüklendi (build N)`

- [ ] **Step 6: Commit**

```bash
git add -A
git commit -m "chore: günlük ve bildirimler cihazda doğrulandı

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```
