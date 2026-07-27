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

print("\n=== 4) Dinlenme günü düzenlemesi etap eşlemesini BOZMUYOR ===")
edits = TripEdits()
edits.days[trip.days[1].slug] = DayEdit(isRestDay: true)   // 2. günü dinlenme yap
days = TripPlanner.days(trip: trip, edits: edits)
check("gün2 artık dinlenme (leg=nil)", days[1].legIndex == nil)
// legIndex artık gün sayımından değil durak konumundan türetiliyor:
// dinlenme düzenlemesi sonraki günlerin etabını kaydırmaz (DayDetailView doğru etabı gösterir).
check("gün3 etabı yerinde kalıyor (leg=2)", days[2].legIndex == 2, "\(String(describing: days[2].legIndex))")
check("tarihler değişmedi (dinlenme gün eklemez)", days.allSatisfy {
    cal.isDate($0.date, inSameDayAs: baseline[$0.index].date)
})

print("\n=== 5) Alan düzenlemesi: taban değerle aynıysa düzenleme sayılmaz ===")
edits = TripEdits()
edits.days["x"] = DayEdit()
check("boş düzenleme isEmpty", DayEdit().isEmpty)
check("dolu düzenleme isEmpty değil", !DayEdit(note: "test").isEmpty)
let legacyDayEdit = try! JSONDecoder().decode(DayEdit.self, from: Data(#"{"note":"eski kayıt"}"#.utf8))
check("eski gün düzenlemesi kesin hedef olmadan açılır",
      legacyDayEdit.arrivalTarget == nil && legacyDayEdit.stayDetails == nil)

let localSelection = ArrivalTarget(
    id: "local-selection", name: "Yerel kamp", kind: .campground,
    latitude: 42.7, longitude: 23.3, formattedAddress: "Sofya",
    phone: "+359 88 123 4567", whatsAppPhone: "+359 88 765 4321",
    email: "private@example.com", websiteURL: URL(string: "https://private.example.com")
)
let accountSelection = ArrivalTarget(
    id: "account-selection", name: "Eski hesap kampı", kind: .campground,
    latitude: 42.71, longitude: 23.31, formattedAddress: "Sofya"
)
let baseSelection = ArrivalTarget(
    id: "base-selection", name: "Taban kamp", kind: .campground,
    latitude: 42.72, longitude: 23.32, formattedAddress: "Sofya"
)
let selectionScope = ArrivalTargetOverrideScope(
    tripID: "trip-a", daySlug: "istanbul-sofya", userID: "user-a"
)
let privateContactedAt = Date(timeIntervalSince1970: 1_785_146_400)
let privateStay = StayDetails(
    reservationStatus: .confirmed,
    reservationReference: "PRIVATE-REF-42",
    note: "Gate code 2468",
    estimatedArrival: "18:00",
    lastContactedAt: privateContactedAt
)
let persistedSelection = ScopedArrivalTargetOverride(
    scope: selectionScope,
    target: localSelection,
    stay: privateStay
)
check("yeniden oluşturulan görünümde eşleşen kalıcı yerel seçim hesap verisini geçer",
      ArrivalTargetSelectionResolver.target(
        scope: selectionScope,
        ephemeral: nil,
        persisted: persistedSelection,
        account: accountSelection,
        base: baseSelection
      )?.id == "local-selection")
check("başka rota gün veya kullanıcıya ait yerel seçim sızmaz",
      ArrivalTargetSelectionResolver.target(
        scope: ArrivalTargetOverrideScope(tripID: "trip-b", daySlug: "istanbul-sofya", userID: "user-a"),
        ephemeral: persistedSelection,
        persisted: persistedSelection,
        account: accountSelection,
        base: baseSelection
      )?.id == "account-selection"
        && ArrivalTargetSelectionResolver.target(
          scope: ArrivalTargetOverrideScope(tripID: "trip-a", daySlug: "other-day", userID: "user-a"),
          ephemeral: nil,
          persisted: persistedSelection,
          account: nil,
          base: baseSelection
        )?.id == "base-selection")
let scopedEdit = DayEdit(
    arrivalTarget: localSelection,
    stayDetails: privateStay,
    arrivalTargetScope: selectionScope
)
let scopedEditRoundTrip = try! JSONDecoder().decode(DayEdit.self, from: JSONEncoder().encode(scopedEdit))
check("kalıcı gün düzenlemesi rota gün kullanıcı kapsamını JSON turunda korur",
      scopedEditRoundTrip.arrivalTargetScope == selectionScope)
var scopedOverrides = ScopedArrivalTargetOverrides()
scopedOverrides.set(persistedSelection)
let scopedOverridesRoundTrip = try! JSONDecoder().decode(
    ScopedArrivalTargetOverrides.self,
    from: JSONEncoder().encode(scopedOverrides)
)
check("özel seçim ayrı depoda uygulama yeniden açıldığında korunur",
      scopedOverridesRoundTrip.value(for: selectionScope)?.target == localSelection
        && scopedOverridesRoundTrip.value(for: selectionScope)?.stay == privateStay)
check("özel seçim yalnız tam rota gün kullanıcı anahtarıyla okunur",
      scopedOverridesRoundTrip.value(
        for: ArrivalTargetOverrideScope(
            tripID: "trip-a", daySlug: "istanbul-sofya", userID: "user-b"
        )
      ) == nil)
var clearedOverrides = scopedOverridesRoundTrip
clearedOverrides.remove(scope: ArrivalTargetOverrideScope(
    tripID: "trip-a", daySlug: "istanbul-sofya", userID: "user-b"
))
check("başka hesabın başarılı yanıtı bekleyen seçimi temizlemez",
      clearedOverrides.value(for: selectionScope)?.target.id == "local-selection")
clearedOverrides.remove(scope: selectionScope)
check("yalnız eşleşen başarılı yanıt bekleyen seçimi temizler",
      clearedOverrides.value(for: selectionScope) == nil)
let sharedScopedEdits = TripEdits(days: [
    selectionScope.daySlug: DayEdit(
        note: "paylaşılan not",
        arrivalTarget: localSelection.publicSummary,
        stayDetails: StayDetails(estimatedArrival: "18:00"),
        arrivalTargetScope: selectionScope
    )
]).sharedSyncState
check("ortak senkron tabanı özel hedef ve kapsamı taşımaz",
      sharedScopedEdits.days[selectionScope.daySlug]?.arrivalTarget == nil
        && sharedScopedEdits.days[selectionScope.daySlug]?.stayDetails == nil
        && sharedScopedEdits.days[selectionScope.daySlug]?.arrivalTargetScope == nil
        && sharedScopedEdits.days[selectionScope.daySlug]?.note == "paylaşılan not")
var scopedPlannerEdits = TripEdits()
scopedPlannerEdits.days[selectionScope.daySlug] = scopedEdit
let scopedEffectiveDay = TripPlanner.days(trip: trip, edits: scopedPlannerEdits)
    .first { $0.id == selectionScope.daySlug }!
check("kapsam doğrulanmadan özel hedef etkin plana sızmaz",
      scopedEffectiveDay.arrivalTarget?.id != "local-selection")
check("kapsam doğrulanmadan özel konaklama etkin plana sızmaz",
      scopedEffectiveDay.stayDetails.estimatedArrival == nil)
check("başarılı yanıttan sonra hesap hedefi tabanın önünde görünür",
      ArrivalTargetSelectionResolver.target(
        scope: selectionScope,
        ephemeral: nil,
        persisted: nil,
        account: accountSelection,
        base: baseSelection
      )?.id == "account-selection")
let newerPersistedSelection = ScopedArrivalTargetOverride(
    scope: selectionScope,
    target: ArrivalTarget(
        id: "newer-persisted", name: "Yeni kalıcı kamp", kind: .campground,
        latitude: 42.8, longitude: 23.4, formattedAddress: "Sofya"
    ),
    stay: StayDetails(estimatedArrival: "19:00")
)
var existingMigrationOverrides = ScopedArrivalTargetOverrides()
existingMigrationOverrides.set(newerPersistedSelection)
let legacyMigrationEdits = TripEdits(days: [selectionScope.daySlug: scopedEdit])
let legacyMigrationBase = legacyMigrationEdits
var failedMigrationOverrides = existingMigrationOverrides
var failedMigrationEdits = legacyMigrationEdits
var failedMigrationBase = legacyMigrationBase
var failedMigrationEvents: [String] = []
let failedMigration = ScopedArrivalTargetOverrideMigration.perform(
    overrides: &failedMigrationOverrides,
    edits: &failedMigrationEdits,
    syncBase: &failedMigrationBase,
    persistOverrides: { candidate in
        failedMigrationEvents.append("overrides:\(candidate.value(for: selectionScope)?.target.id ?? "nil")")
        return false
    },
    persistEdits: { _ in failedMigrationEvents.append("edits") },
    persistBase: { _ in failedMigrationEvents.append("base") }
)
check("özel depo yazımı başarısızsa eski kaynaklar silinmez",
      !failedMigration
        && failedMigrationEdits == legacyMigrationEdits
        && failedMigrationBase == legacyMigrationBase
        && failedMigrationEvents == ["overrides:newer-persisted"])
var successfulMigrationOverrides = existingMigrationOverrides
var successfulMigrationEdits = legacyMigrationEdits
var successfulMigrationBase = legacyMigrationBase
var successfulMigrationEvents: [String] = []
let successfulMigration = ScopedArrivalTargetOverrideMigration.perform(
    overrides: &successfulMigrationOverrides,
    edits: &successfulMigrationEdits,
    syncBase: &successfulMigrationBase,
    persistOverrides: { candidate in
        successfulMigrationEvents.append("overrides:\(candidate.value(for: selectionScope)?.target.id ?? "nil")")
        return true
    },
    persistEdits: { _ in successfulMigrationEvents.append("edits") },
    persistBase: { _ in successfulMigrationEvents.append("base") }
)
check("başarılı göçte özel depo eski dosyalardan önce yazılır",
      successfulMigration
        && successfulMigrationEvents == ["overrides:newer-persisted", "edits", "base"])
check("mevcut tam kapsamlı seçim eski kaydın üstüne yazılmaz",
      successfulMigrationOverrides.value(for: selectionScope)?.target.id == "newer-persisted")
check("özel depo yazıldıktan sonra iki ortak kaynak temizlenir",
      successfulMigrationEdits == legacyMigrationEdits.sharedSyncState
        && successfulMigrationBase == legacyMigrationBase.sharedSyncState)
var importedMigrationOverrides = ScopedArrivalTargetOverrides()
var importedMigrationEdits = legacyMigrationEdits
var importedMigrationBase = TripEdits()
let importedMigration = ScopedArrivalTargetOverrideMigration.perform(
    overrides: &importedMigrationOverrides,
    edits: &importedMigrationEdits,
    syncBase: &importedMigrationBase,
    persistOverrides: { _ in true },
    persistEdits: { _ in },
    persistBase: { _ in }
)
check("eski kapsamlı kaydın tüm özel hedef ve konaklama alanları göç eder",
      importedMigration
        && importedMigrationOverrides.value(for: selectionScope)?.target == localSelection
        && importedMigrationOverrides.value(for: selectionScope)?.stay == privateStay)
let legacyDay = try! JSONDecoder().decode(DayPlan.self, from: Data(#"{"slug":"old","date":"3 Ağustos","origin":"İstanbul","destination":"Sofya","distanceKm":"1 km","duration":"1 dk","fuel":"€1","risks":[],"opportunities":[],"contingencies":[],"camp":{"name":"Kamp","place":"Sofya","note":"","link":""},"stops":[{"type":"Mola","name":"Eski mola"}]}"#.utf8))
check("eski gün JSON'u ETA alanları olmadan açılır",
      legacyDay.borderBufferMinutes == nil && legacyDay.waypoints?.first?.estimatedMinutes == nil)

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

print("\n=== 7) Saat dilimi: rota günü cihaz saat diliminden bağımsız ===")
let originalTimeZone = NSTimeZone.default
NSTimeZone.default = TimeZone(identifier: "America/Los_Angeles")!
let earlyTrip = TripData(
    departureAt: "2026-08-03T00:30:00+03:00",
    totalKm: 1,
    totalBudget: Budget(fuel: "€1", total: "€1", min: nil, max: nil),
    stops: [
        Stop(id: "istanbul", name: "İstanbul", country: "Türkiye", lat: 41.0, lng: 29.0),
        Stop(id: "sofia", name: "Sofya", country: "Bulgaristan", lat: 42.7, lng: 23.3),
    ],
    days: [
        DayPlan(
            slug: "istanbul-sofya",
            date: "3 Ağustos",
            origin: "İstanbul",
            destination: "Sofya",
            distanceKm: "1 km",
            duration: "1 dk",
            fuel: "€1",
            risks: [],
            opportunities: [],
            contingencies: [],
            camp: Camp(name: "Kamp", place: "Sofya", note: "", link: "", image: nil, alternatives: nil, maximumLengthMeters: nil),
            borderBufferMinutes: nil,
            waypoints: nil,
            route: nil,
            trafficLabel: nil,
            cityCameras: nil
        ),
    ],
    checklist: []
)
let earlyDay = TripPlanner.days(trip: earlyTrip, edits: TripEdits()).first!
let routeCalendar = TripPlanner.routeCalendar
check("erken kalkış rota takviminde 3 Ağustos kalır",
      routeCalendar.component(.day, from: earlyDay.date) == 3,
      "\(routeCalendar.component(.day, from: earlyDay.date))")
NSTimeZone.default = originalTimeZone

print("\n=== 8) Kalkış modalı: aynı gün saat değişirse anahtar yenilenir ===")
let iso = ISO8601DateFormatter()
iso.formatOptions = [.withInternetDateTime]
let sameDayMorning = iso.date(from: "2026-08-03T08:00:00+03:00")!
let sameDayNoon = iso.date(from: "2026-08-03T12:00:00+03:00")!
check("aynı gün farklı saat farklı modal anahtarı üretir",
      DeparturePromptKey.key(stopId: "sofia", departure: sameDayMorning)
        != DeparturePromptKey.key(stopId: "sofia", departure: sameDayNoon))

print("\n=== 9) Rota başlatma: Live Activity 0/0 metrikle başlamaz ===")
check("nav yoksa Live Activity payload yok",
      RouteStartMetrics(remainingKm: nil, remainingMinutes: nil).liveActivityPayload == nil)
check("0 km/0 dk payload reddedilir",
      RouteStartMetrics(remainingKm: 0, remainingMinutes: 0).liveActivityPayload == nil)
check("pozitif metrik payload üretir",
      RouteStartMetrics(remainingKm: 12, remainingMinutes: 18).liveActivityPayload?.remainingKm == 12)

print("\n=== 10) Rota sapma anonsu yalnız aktif rota döngüsünde çalışır ===")
check("rota başlamadan sapma anonsu kapalı",
      RouteAnnouncementPolicy.allowsDeviationAnnouncement(
        routeStarted: false,
        activeStopId: nil,
        nextStopId: "sofia",
        currentLegIndex: 0,
        speedKmh: 82,
        hasLegGeometry: true
      ) == false)
check("aktif rota hedefi sıradaki durakla eşleşince sapma anonsu açık",
      RouteAnnouncementPolicy.allowsDeviationAnnouncement(
        routeStarted: true,
        activeStopId: "sofia",
        nextStopId: "sofia",
        currentLegIndex: 0,
        speedKmh: 82,
        hasLegGeometry: true
      ) == true)
check("aktif rota başka hedefteyse sapma anonsu kapalı",
      RouteAnnouncementPolicy.allowsDeviationAnnouncement(
        routeStarted: true,
        activeStopId: "budapest",
        nextStopId: "sofia",
        currentLegIndex: 0,
        speedKmh: 82,
        hasLegGeometry: true
      ) == false)
check("araç ses yolu bağlantısı rota hazır anonsunu otomatik açmaz",
      RouteAnnouncementPolicy.allowsRouteReadyAnnouncement(
        triggeredByUserAction: false,
        routeStarted: false
      ) == false)
check("kullanıcı panelden isterse rota hazır anonsu çalabilir",
      RouteAnnouncementPolicy.allowsRouteReadyAnnouncement(
        triggeredByUserAction: true,
        routeStarted: false
      ) == true)
check("rota başlamadan mesafe anonsu kapalı",
      RouteAnnouncementPolicy.allowsRouteProgressAnnouncement(
        routeStarted: false,
        activeStopId: nil,
        nextStopId: "sofia"
      ) == false)
check("aktif rota hedefi sıradaki durak değilse mesafe anonsu kapalı",
      RouteAnnouncementPolicy.allowsRouteProgressAnnouncement(
        routeStarted: true,
        activeStopId: "budapest",
        nextStopId: "sofia"
      ) == false)
check("aktif rota hedefi sıradaki duraksa mesafe anonsu açık",
      RouteAnnouncementPolicy.allowsRouteProgressAnnouncement(
        routeStarted: true,
        activeStopId: "sofia",
        nextStopId: "sofia"
      ) == true)
check("rota başlamadan geofence varış anonsu kapalı",
      RouteAnnouncementPolicy.allowsArrivalAnnouncement(
        routeStarted: false,
        activeStopId: nil,
        enteredStopId: "sofia"
      ) == false)
check("aktif rota başka hedefteyse geofence varış anonsu kapalı",
      RouteAnnouncementPolicy.allowsArrivalAnnouncement(
        routeStarted: true,
        activeStopId: "budapest",
        enteredStopId: "sofia"
      ) == false)
check("aktif rota hedef çemberine girince varış anonsu açık",
      RouteAnnouncementPolicy.allowsArrivalAnnouncement(
        routeStarted: true,
        activeStopId: "sofia",
        enteredStopId: "sofia"
      ) == true)
check("rota başlamadan sürüş molası bildirimi kapalı",
      RouteAnnouncementPolicy.allowsDrivingReminder(routeStarted: false) == false)
check("rota aktifken sürüş molası bildirimi açık",
      RouteAnnouncementPolicy.allowsDrivingReminder(routeStarted: true) == true)

print("\n=== 11) Rakım gösterimi: göreli değer mutlak rakım gibi yazılmaz ===")
let relativeAltitude = AltitudeDisplay.reading(absoluteMeters: nil, relativeMeters: 2)
check("barometre göreli değerini ayrı etiketler",
      relativeAltitude?.label == "Rakım değişimi" && relativeAltitude?.text == "+2 m",
      "\(String(describing: relativeAltitude))")
let absoluteAltitude = AltitudeDisplay.reading(absoluteMeters: 145.4, relativeMeters: 2)
check("mutlak rakım varsa önceliklidir",
      absoluteAltitude?.label == "Rakım" && absoluteAltitude?.text == "145 m",
      "\(String(describing: absoluteAltitude))")

print("\n=== 12) Rota sırası: yalnız sıradaki etap başlatılır ===")
let stopIds = trip.stops.map(\.id)
let sofia = trip.stops[1]
let bucharest = trip.stops[2]
let deva = trip.stops[3]
var completedStops = Set<String>()
check("başta yalnız 1. etap (Sofya) başlatılabilir",
      RouteStepPolicy.state(for: sofia.id, orderedStopIds: stopIds, completedStopIds: completedStops, activeStopId: nil) == .available)
check("Sofya tamamlanmadan 2. etap kilitlidir",
      RouteStepPolicy.state(for: bucharest.id, orderedStopIds: stopIds, completedStopIds: completedStops, activeStopId: nil) == .locked)
completedStops.insert(sofia.id)
check("Sofya tamamlanınca Bükreş sıradaki etap olur",
      RouteStepPolicy.state(for: bucharest.id, orderedStopIds: stopIds, completedStopIds: completedStops, activeStopId: nil) == .available)
check("Bükreş aktifken Deva başlatılamaz",
      RouteStepPolicy.state(for: deva.id, orderedStopIds: stopIds, completedStopIds: completedStops, activeStopId: bucharest.id) == .locked)
check("aktif hedef kendi durumunu korur",
      RouteStepPolicy.state(for: bucharest.id, orderedStopIds: stopIds, completedStopIds: completedStops, activeStopId: bucharest.id) == .active)
completedStops.insert(bucharest.id)
check("tamamlanan durak tamamlandı görünür",
      RouteStepPolicy.state(for: bucharest.id, orderedStopIds: stopIds, completedStopIds: completedStops, activeStopId: nil) == .completed)

let exactTarget = ArrivalTarget(
    id: "campuccino", name: "Camping Campuccino", kind: .campground,
    latitude: 42.66, longitude: 23.28, formattedAddress: "Sofia, Bulgaria"
)
check("kesin hedef olmadan uygun etap da başlamaz",
      !RouteStartPolicy.canStart(isRestDay: false, target: nil, stepState: .available))
check("kilitli etap kesin hedefle de başlamaz",
      !RouteStartPolicy.canStart(isRestDay: false, target: exactTarget, stepState: .locked))
check("sıradaki etap geçerli kesin hedefle başlar",
      RouteStartPolicy.canStart(isRestDay: false, target: exactTarget, stepState: .available))
check("aktif hedef kimliği değişmişse ilerleme anonsu kapanır",
      !RouteAnnouncementPolicy.allowsRouteProgressAnnouncement(
        routeStarted: true,
        activeStopId: "sofia",
        activeTargetId: "old-target",
        nextStopId: "sofia",
        nextTargetId: "campuccino"
      ))

print("\n=== 13) Rota başlangıcı: aktif navigasyon GPS konumundan hesaplanır ===")
let currentCoordinate = CoordinateValue(latitude: 41.0123, longitude: 29.1122)
let plannedOrigin = CoordinateValue(latitude: 41.0172, longitude: 28.9850)
check("GPS varsa kaynak mevcut konumdur",
      RouteStartOrigin.coordinate(location: currentCoordinate, plannedOrigin: plannedOrigin) == currentCoordinate)
check("GPS yoksa plan durağı yedek kaynak olur",
      RouteStartOrigin.coordinate(location: nil, plannedOrigin: plannedOrigin) == plannedOrigin)

print("\n=== 14) KASKAT: ilk durakta +1 gün tüm sonrayı ve varışı kaydırır ===")
edits = TripEdits()
edits.days[trip.days[0].slug] = DayEdit(extraDays: 1)
days = TripPlanner.days(trip: trip, edits: edits)
check("ilk gün 2 takvim günü sürer", days[0].dayCount == 2, "\(days[0].dayCount)")
check("sonraki tüm günler 1 gün kayar", (1 ..< days.count).allSatisfy {
    cal.dateComponents([.day], from: baseline[$0].date, to: days[$0].date).day == 1
})
check("varış tarihi de 1 gün kayar",
      cal.dateComponents(
        [.day],
        from: TripPlanner.arrivalDate(trip: trip, edits: TripEdits())!,
        to: TripPlanner.arrivalDate(trip: trip, edits: edits)!
      ).day == 1)

print("\n" + (failures == 0 ? "✅ TÜM KONTROLLER GEÇTİ" : "❌ \(failures) KONTROL BAŞARISIZ"))
exit(failures == 0 ? 0 : 1)
