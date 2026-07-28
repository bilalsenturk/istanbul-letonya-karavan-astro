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

print("\n=== 7b) Öldürülme sonrası .syncing'de takılı kalan kayıt kurtarılır ===")
// Gönderim ortasında uygulama öldürülürse kayıt .syncing kalır; diskte bu
// hâliyle durur. Açılışta resetStuckSyncing() çağrılmazsa nextToSend()
// (yalnızca .pending seçer) bu kaydı bir daha asla döndürmez.
var q3 = JournalQueue()
q3.enqueue("d")
q3.markSyncing("d", now: t0)
check("takılı kayıt gönderime seçilmez", q3.nextToSend(now: t0) == nil,
      q3.nextToSend(now: t0) ?? "nil")
let stuckData = try! JSONEncoder().encode(q3)
var relaunched = try! JSONDecoder().decode(JournalQueue.self, from: stuckData)
relaunched.resetStuckSyncing()   // JournalStore.load() açılışta bunu çağırır
check("kurtarılan kayıt yeniden gönderilebilir", relaunched.nextToSend(now: t0) == "d",
      relaunched.nextToSend(now: t0) ?? "nil")
check("bekleyen sayısına geri girer", relaunched.pendingCount == 1,
      "\(relaunched.pendingCount)")
check("deneme sayısı korunur", relaunched.items.first?.attempts == 0,
      "\(relaunched.items.first?.attempts ?? -1)")
// Geri çekilme bekleyen bir kayıt takılırsa backoff'u korunmalı:
// hemen değil, süresi dolunca seçilmeli.
var q4 = JournalQueue()
q4.enqueue("e")
q4.markSyncing("e", now: t0)
q4.markFailed("e", now: t0)      // attempts=1, .pending, backoff başladı
q4.markSyncing("e", now: t0.addingTimeInterval(JournalQueue.backoff(attempts: 1) + 1))
q4.resetStuckSyncing()
let duringBackoff = t0.addingTimeInterval(JournalQueue.backoff(attempts: 1) + 2)
check("backoff korumalı kayıt hemen seçilmez", q4.nextToSend(now: duringBackoff) == nil,
      q4.nextToSend(now: duringBackoff) ?? "nil")
let backoffOver = duringBackoff.addingTimeInterval(JournalQueue.backoff(attempts: 1) + 1)
check("backoff dolunca seçilir", q4.nextToSend(now: backoffOver) == "e",
      q4.nextToSend(now: backoffOver) ?? "nil")

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

print("\n=== 9) Genel/geçici hata (kota, hesap) deneme hakkı TÜKETMEZ ===")
// JournalStore drainQueue, quotaExceeded/accountUnavailable gibi kayda özgü
// OLMAYAN hatalarda markFailed yerine markDeferred çağırır: markFailed
// attempts'i artırır ve maxAttempts sonrası kaydı kalıcı .failed'a düşürür;
// kota açıldığında kayıt yine de gitmezdi. markDeferred kaydı geri
// çekilmesiz .pending'e döndürür.
var q5 = JournalQueue()
q5.enqueue("f")
q5.markSyncing("f", now: t0)
q5.markDeferred("f")   // kota dolu — gönderim hiç yapılamadı
check("kota denemesi sayılmaz", q5.items.first?.attempts == 0,
      "\(q5.items.first?.attempts ?? -1)")
check("kayıt failed'a düşmez", q5.items.first?.state == .pending,
      q5.items.first?.state.rawValue ?? "nil")
check("hemen yeniden denenebilir", q5.nextToSend(now: t0) == "f",
      q5.nextToSend(now: t0) ?? "nil")
// Ard arda kota hataları da birikip .failed üretmemeli:
for i in 1 ... JournalQueue.maxAttempts + 2 {
    q5.markSyncing("f", now: t0)
    q5.markDeferred("f")
    _ = i
}
check("tekrarlı kota sonrası hâlâ pending", q5.items.first?.state == .pending,
      q5.items.first?.state.rawValue ?? "nil")
check("tekrarlı kota sonrası attempts sıfır", q5.items.first?.attempts == 0,
      "\(q5.items.first?.attempts ?? -1)")

print(failures == 0 ? "\n✅ hepsi geçti\n" : "\n❌ \(failures) başarısız\n")
exit(failures == 0 ? 0 : 1)
