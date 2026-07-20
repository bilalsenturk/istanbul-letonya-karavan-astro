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
check("tam %3 sınırında tetiklenir", NotificationRules.currencyJump(previous: 100, current: 103) == true)

print("\n=== 5) Yakıt farkı ===")
check("burası %12 ucuzsa yüzde döner",
      NotificationRules.fuelCheaper(here: 1.76, next: 2.0) == 12,
      String(describing: NotificationRules.fuelCheaper(here: 1.76, next: 2.0)))
check("fark küçükse nil", NotificationRules.fuelCheaper(here: 1.98, next: 2.0) == nil)
check("burası pahalıysa nil", NotificationRules.fuelCheaper(here: 2.2, next: 2.0) == nil)
check("tam %5 sınırında 5 döner", NotificationRules.fuelCheaper(here: 1.90, next: 2.00) == 5)

print("\n=== 6) Düşük pil yalnızca navigasyondayken ===")
check("navigasyon kapalıyken uyarmaz", NotificationRules.lowBattery(level: 0.15, navigating: false) == false)
check("navigasyon açıkken uyarır", NotificationRules.lowBattery(level: 0.15, navigating: true) == true)
check("pil yüksekse uyarmaz", NotificationRules.lowBattery(level: 0.55, navigating: true) == false)
check("bilinmeyen pil (-1) düşük sayılmaz", NotificationRules.lowBattery(level: -1, navigating: true) == false)
check("tam %20 sınırında uyarır", NotificationRules.lowBattery(level: 0.20, navigating: true) == true)

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

print("\n=== 10) allow() sonrası gerçek gönderim başarısız olursa release() bekleme hakkını iade eder ===")
var b4 = NotificationBudget()
check("ilk izin geçer", b4.allow(.borderApproach, now: t0) == true)
b4.release(.borderApproach)
check("release sonrası hemen tekrar geçer", b4.allow(.borderApproach, now: t0.addingTimeInterval(60)) == true)
var b5 = NotificationBudget()
_ = b5.allow(.lowBattery, now: t0)
check("release edilmeyen tür bekleme süresine tabi kalır", b5.allow(.lowBattery, now: t0.addingTimeInterval(60)) == false)

print(failures == 0 ? "\n✅ hepsi geçti\n" : "\n❌ \(failures) başarısız\n")
exit(failures == 0 ? 0 : 1)
