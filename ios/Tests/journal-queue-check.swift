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
