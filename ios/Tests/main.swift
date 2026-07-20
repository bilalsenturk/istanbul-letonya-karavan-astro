import Foundation

// TripPlanner kaskat doğrulaması — gerçek trip.json ile, app'ten bağımsız çalışır.

var failures = 0
func check(_ name: String, _ condition: Bool, _ detail: String = "") {
    if condition {
        print("  ✓ \(name)")
    } else {
        failures += 1
        print("  ✗ \(name) \(detail)")
    }
}

let path = "/Users/bilalsenturk/Developer/istanbul-letonya-karavan-astro/ios/Karavan/Resources/trip.json"
let data = try! Data(contentsOf: URL(fileURLWithPath: path))
let trip = try! JSONDecoder().decode(TripData.self, from: data)

let cal = Calendar.current
let fmt = DateFormatter()
fmt.locale = Locale(identifier: "tr_TR")
fmt.dateFormat = "d MMMM yyyy"

print("\n=== 1) Taban: kalkış web verisinden, tarihler türetilmiş ===")
var edits = TripEdits()
var days = TripPlanner.days(trip: trip, edits: edits)
let baseDep = TripPlanner.departure(trip: trip, edits: edits)
print("  kalkış: \(fmt.string(from: baseDep))")
for d in days { print("    gün \(d.index + 1): \(d.dateText)  [\(d.origin) → \(d.destination)] leg=\(d.legIndex.map(String.init) ?? "—")") }

check("8 gün türetildi", days.count == 8)
check("1. gün = kalkış günü", cal.isDate(days[0].date, inSameDayAs: baseDep))
check("günler ardışık", zip(days, days.dropFirst()).allSatisfy {
    cal.dateComponents([.day], from: $0.date, to: $1.date).day == 1
})
check("dinlenme günü etap tüketmiyor (gün5 leg=nil)", days[4].legIndex == nil, "\(String(describing: days[4].legIndex))")
check("dinlenme sonrası etap devam ediyor (gün6 leg=4)", days[5].legIndex == 4, "\(String(describing: days[5].legIndex))")
check("son gün leg=6 (7 etap)", days[7].legIndex == 6, "\(String(describing: days[7].legIndex))")
check("JSON'daki sabit metinle uyumlu (gün1)", days[0].dateText.contains("3 Ağustos"), days[0].dateText)

print("\n=== 2) KASKAT: kalkış 10 gün ileri alınınca tüm günler kayar ===")
let shifted = cal.date(byAdding: .day, value: 10, to: baseDep)!
edits.departureAt = shifted
days = TripPlanner.days(trip: trip, edits: edits)
print("  yeni kalkış: \(fmt.string(from: shifted))")
for d in days.prefix(3) { print("    gün \(d.index + 1): \(d.dateText)") }
check("1. gün yeni kalkışa taşındı", cal.isDate(days[0].date, inSameDayAs: shifted))
check("tüm günler tam 10 gün kaydı", days.allSatisfy { d in
    let orig = TripPlanner.days(trip: trip, edits: TripEdits())[d.index].date
    return cal.dateComponents([.day], from: orig, to: d.date).day == 10
})
check("varış da 10 gün kaydı", {
    let a = TripPlanner.arrivalDate(trip: trip, edits: TripEdits())!
    let b = TripPlanner.arrivalDate(trip: trip, edits: edits)!
    return cal.dateComponents([.day], from: a, to: b).day == 10
}())

print("\n=== 3) KASKAT: bir güne +2 gün eklenince SONRAKİ günler kayar, öncekiler kaymaz ===")
edits = TripEdits()
let budapestSlug = trip.days[3].slug          // 4. gün: Deva → Budapeşte
edits.days[budapestSlug] = DayEdit(extraDays: 2)
days = TripPlanner.days(trip: trip, edits: edits)
let baseline = TripPlanner.days(trip: trip, edits: TripEdits())
for d in days { print("    gün \(d.index + 1): \(d.shortDateText) (dayCount \(d.dayCount))") }
check("önceki günler kaymadı (gün1-4)", (0...3).allSatisfy {
    cal.isDate(days[$0].date, inSameDayAs: baseline[$0].date)
})
check("düzenlenen gün 3 takvim günü sürüyor", days[3].dayCount == 3, "\(days[3].dayCount)")
check("sonraki günler 2 gün kaydı", (4...7).allSatisfy {
    cal.dateComponents([.day], from: baseline[$0].date, to: days[$0].date).day == 2
})
check("toplam gün 8 → 10", TripPlanner.totalDays(trip: trip, edits: edits) == 10,
      "\(TripPlanner.totalDays(trip: trip, edits: edits))")
check("etap eşlemesi bozulmadı", days[7].legIndex == 6)

print("\n=== 4) Dinlenme günü düzenlemesi etap eşlemesini kaydırıyor ===")
edits = TripEdits()
edits.days[trip.days[1].slug] = DayEdit(isRestDay: true)   // 2. günü dinlenme yap
days = TripPlanner.days(trip: trip, edits: edits)
check("gün2 artık dinlenme (leg=nil)", days[1].legIndex == nil)
check("gün3 etabı bir geri kaydı (leg=1)", days[2].legIndex == 1, "\(String(describing: days[2].legIndex))")
check("tarihler değişmedi (dinlenme gün eklemez)", days.allSatisfy {
    cal.isDate($0.date, inSameDayAs: baseline[$0.index].date)
})

print("\n=== 5) Alan düzenlemesi: taban değerle aynıysa düzenleme sayılmaz ===")
edits = TripEdits()
edits.days["x"] = DayEdit()
check("boş düzenleme isEmpty", DayEdit().isEmpty)
check("dolu düzenleme isEmpty değil", !DayEdit(note: "test").isEmpty)

print("\n=== 6) Sınır durumları ===")
edits = TripEdits()
check("trip nil → boş liste", TripPlanner.days(trip: nil, edits: edits).isEmpty)
edits.days[trip.days[0].slug] = DayEdit(extraDays: -5)   // negatif
days = TripPlanner.days(trip: trip, edits: edits)
check("negatif extraDays kırpıldı", days[0].dayCount == 1, "\(days[0].dayCount)")
edits = TripEdits()
edits.days[trip.days[0].slug] = DayEdit(startHour: 99)
days = TripPlanner.days(trip: trip, edits: edits)
check("geçersiz saat kırpıldı", cal.component(.hour, from: days[0].departTime) == 23,
      "\(cal.component(.hour, from: days[0].departTime))")

print("\n" + (failures == 0 ? "✅ TÜM KONTROLLER GEÇTİ" : "❌ \(failures) KONTROL BAŞARISIZ"))
exit(failures == 0 ? 0 : 1)
