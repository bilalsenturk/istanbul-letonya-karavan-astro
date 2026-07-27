import Foundation

private var failures = 0

private func check(_ name: String, _ condition: @autoclosure () -> Bool) {
    if condition() {
        print("  ✓ \(name)")
    } else {
        failures += 1
        print("  ✗ \(name)")
    }
}

private let legacyDay = Data(#"""
{
  "slug": "legacy-day",
  "date": "3 Ağustos",
  "origin": "İstanbul",
  "destination": "Sofya",
  "distanceKm": "550 km",
  "duration": "8 saat",
  "fuel": "70 L",
  "risks": [],
  "opportunities": [],
  "contingencies": [],
  "camp": { "name": "Kamp", "place": "Sofya", "note": "", "link": "" }
}
"""#.utf8)

private let currentDay = Data(#"""
{
  "slug": "current-day",
  "date": "4 Ağustos",
  "origin": "Sofya",
  "destination": "Novi Sad",
  "distanceKm": "390 km",
  "duration": "6 saat",
  "fuel": "50 L",
  "risks": [],
  "opportunities": [],
  "contingencies": [],
  "camp": { "name": "Campuccino", "place": "Kovilj", "note": "", "link": "" },
  "arrivalTarget": {
    "id": "camping-campuccino",
    "name": "Camping Campuccino",
    "kind": "campground",
    "latitude": 45.2410861,
    "longitude": 20.0255374,
    "formattedAddress": "Branka Bajića 60, 21243 Kovilj, Serbia",
    "source": "migrated",
    "updatedAt": 0
  }
}
"""#.utf8)

let decoder = JSONDecoder()
let legacy = try? decoder.decode(DayPlan.self, from: legacyDay)
let current = try? decoder.decode(DayPlan.self, from: currentDay)

check("arrivalTarget alanı olmayan eski gün çözülür", legacy != nil)
check("eski günde kesin varış hedefi nil kalır", legacy?.arrivalTarget == nil)
check("günün kesin varış hedefi çözülür", current?.arrivalTarget?.id == "camping-campuccino")
check("hedef koordinatı korunur", current?.arrivalTarget?.longitude == 20.0255374)

print(failures == 0 ? "✅ DayPlan arrival-target kontrolleri geçti" : "❌ \(failures) kontrol başarısız")
exit(failures == 0 ? 0 : 1)
