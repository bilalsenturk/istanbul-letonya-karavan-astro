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

@main
struct ArrivalTargetCheck {
    @MainActor static func main() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Istanbul")!
        let checkIn = calendar.date(from: DateComponents(year: 2026, month: 8, day: 3, hour: 15))!
        let checkOut = calendar.date(from: DateComponents(year: 2026, month: 8, day: 5, hour: 11))!

        let target = ArrivalTarget(
            id: "campuccino",
            name: "Camping Campuccino",
            kind: .campground,
            latitude: 42.66,
            longitude: 23.28,
            formattedAddress: "Sofia, Bulgaria",
            phone: "+359 88 123 4567",
            email: "hello@example.com"
        )

        print("\n=== Kesin varış hedefi ===")
        check("hedef olmadan etap başlamaz",
              !ArrivalTargetRequirement.canStart(isRestDay: false, target: nil))
        check("koordinatlı hedefle etap başlar",
              ArrivalTargetRequirement.canStart(isRestDay: false, target: target))
        check("dinlenme günü hedef gerektirmez",
              ArrivalTargetRequirement.canStart(isRestDay: true, target: nil))

        let invalid = ArrivalTarget(
            id: "invalid",
            name: "Hatalı",
            kind: .address,
            latitude: 120,
            longitude: 23,
            formattedAddress: "—"
        )
        check("geçersiz koordinat rota başlatmaz",
              !ArrivalTargetRequirement.canStart(isRestDay: false, target: invalid))

        print("\n=== Konaklama mesajı ===")
        let stay = StayDetails(
            checkIn: checkIn,
            checkOut: checkOut,
            estimatedArrival: "18:30"
        )
        let profile = StayContactProfile(
            contactName: "Bilal",
            adults: 2,
            children: 1,
            vehicleDescription: "Volkswagen Passat + Adria Altea 432PX",
            totalLengthMeters: 10.8,
            needsElectricity: true,
            hasPet: false,
            additionalNeeds: "Quiet pitch",
            preferredLanguage: .english
        )
        let departure = calendar.date(from: DateComponents(year: 2026, month: 8, day: 3, hour: 8))!
        let eta = StayETACalculator.calculate(.init(
            departure: departure,
            drivingSeconds: 8 * 3600,
            waypointMinutes: 45,
            borderBufferMinutes: 90,
            calendar: calendar
        ))
        // 08:00 + 8 saat + 45 dk ara durak + 90 dk sınır payı = 18:15.
        check("ETA yarım saatlik pencere üretir", eta.text == "18:00–19:00")

        let exactBoundary = StayETACalculator.calculate(.init(
            departure: departure,
            drivingSeconds: 9 * 3600,
            calendar: calendar
        ))
        check("tam yarım saatte ETA bir saatlik kalır", exactBoundary.text == "17:00–18:00")

        let rollover = StayETACalculator.calculate(.init(
            departure: calendar.date(from: DateComponents(year: 2026, month: 8, day: 3, hour: 23, minute: 50))!,
            drivingSeconds: 0,
            calendar: calendar
        ))
        check("ETA gece yarısını aşan pencereyi korur", rollover.text == "23:30–00:30")

        var rigaCalendar = Calendar(identifier: .gregorian)
        rigaCalendar.timeZone = TimeZone(identifier: "Europe/Riga")!
        let dstETA = StayETACalculator.calculate(.init(
            departure: rigaCalendar.date(from: DateComponents(year: 2026, month: 3, day: 29, hour: 2, minute: 45))!,
            drivingSeconds: 45 * 60,
            calendar: rigaCalendar
        ))
        check("ETA hedef saat diliminde yaz saati atlamasını taşır", dstETA.text == "04:30–05:30")

        let flight = StayMessageComposer.compose(
            target: target, stay: stay, profile: profile, transportMode: .flight, camp: nil
        )
        check("uçak mesajında araç yok",
              !flight.body.contains("Passat") && !flight.body.localizedCaseInsensitiveContains("electricity"))
        check("uçak mesajında konuk ve ek ihtiyaç kalır",
              flight.body.contains("2 adults and 1 child") && flight.body.contains("Additional note:"))

        let walking = StayMessageComposer.compose(
            target: target, stay: stay, profile: profile, transportMode: .walking, camp: nil
        )
        check("yürüyüş mesajında araç ve elektrik yok",
              !walking.body.contains("Passat") && !walking.body.localizedCaseInsensitiveContains("electricity"))
        check("yürüyüş mesajında ek ihtiyaç kalır", walking.body.contains("Quiet pitch"))

        let car = StayMessageComposer.compose(
            target: target,
            stay: stay,
            profile: profile,
            transportMode: .automobile,
            camp: .init(maximumLengthMeters: 8)
        )
        check("uzunluk sınırı teyit edilir", car.body.contains("10.8 m") && car.body.contains("8.0 m"))

        let legacyStay = try! JSONDecoder().decode(StayDetails.self, from: Data(#"{"estimatedArrival":"18:30"}"#.utf8))
        check("eski konaklama kaydı manuel ETA olur",
              legacyStay.estimatedArrivalMode == .manual && legacyStay.estimatedArrivalWindow == nil)

        let message = StayMessageComposer.compose(target: target, stay: stay, profile: profile)
        check("mesaj hedef adını içerir", message.body.contains("Camping Campuccino"))
        check("mesaj giriş ve çıkış tarihini içerir",
              message.body.contains("3 August 2026") && message.body.contains("5 August 2026"))
        check("mesaj kişi ve araç bilgisini içerir",
              message.body.contains("2 adults and 1 child") && message.body.contains("Adria Altea 432PX"))
        check("e-posta konusu anlamlıdır", message.subject.contains("3–5 August 2026"))

        print("\n=== İletişim bağlantıları ===")
        let whatsApp = ContactLinkBuilder.whatsAppURL(phone: target.phone, message: message.body)
        check("WhatsApp numarası E.164 biçimine gelir",
              whatsApp?.absoluteString.contains("wa.me/359881234567") == true)
        check("WhatsApp metni URL içine eklenir",
              whatsApp?.absoluteString.contains("text=") == true)
        let email = ContactLinkBuilder.emailURL(
            email: target.email,
            subject: message.subject,
            body: message.body
        )
        check("e-posta bağlantısı konu ve gövde taşır",
              email?.absoluteString.hasPrefix("mailto:hello@example.com") == true
                && email?.absoluteString.contains("subject=") == true
                && email?.absoluteString.contains("body=") == true)
        check("geçersiz e-posta reddedilir",
              ContactLinkBuilder.emailURL(email: "yanlış", subject: "x", body: "y") == nil)
        check("boş telefon reddedilir",
              ContactLinkBuilder.whatsAppURL(phone: " ", message: "x") == nil)

        print("\n=== Apple Maps sonuç eşlemesi ===")
        let snapshot = ArrivalPlaceSnapshot(
            id: "apple-campuccino",
            name: "Camping Campuccino",
            latitude: 42.66,
            longitude: 23.28,
            formattedAddress: "Sofia, Bulgaria",
            phone: "+359881234567",
            websiteURL: URL(string: "https://example.com"),
            kind: .campground
        )
        let mapped = snapshot.makeTarget()
        check("Maps adı, adresi ve telefonu korunur",
              mapped.name == snapshot.name && mapped.formattedAddress == snapshot.formattedAddress
                && mapped.phone == snapshot.phone)
        check("Maps sitesi korunur", mapped.websiteURL == snapshot.websiteURL)
        check("Maps'in vermediği iletişim alanı uydurulmaz",
              mapped.email == nil && mapped.whatsAppPhone == nil)

        print("\n=== Seyahat profili geçişi ===")
        let seeded = TravelProfileSeed.make(
            accountName: "Bilal Şentürk",
            accountEmail: "bilal@example.com",
            vehicleDescription: "VW Passat 2016 + Adria"
        )
        check("Apple hesap adı profile gelir", seeded.contactName == "Bilal Şentürk")
        check("Apple e-postası boş profile gelir", seeded.contactEmail == "bilal@example.com")
        check("mevcut rota aracı boş profili doldurur", seeded.vehicleDescription.contains("Adria"))

        var preserved = AccountTravelProfile(
            contactName: "Leyla",
            contactEmail: "leyla@example.com",
            vehicleDescription: "Kendi karavanım"
        )
        preserved = TravelProfileSeed.make(
            accountName: "Bilal Şentürk",
            accountEmail: "bilal@example.com",
            vehicleDescription: "VW Passat 2016 + Adria",
            profile: preserved
        )
        check("dolu iletişim bilgileri ezilmez",
              preserved.contactName == "Leyla" && preserved.contactEmail == "leyla@example.com")
        check("dolu araç bilgisi ezilmez", preserved.vehicleDescription == "Kendi karavanım")

        var oldLocal = seeded
        oldLocal.updatedAt = "2026-07-26T08:00:00Z"
        var newRemote = seeded
        newRemote.updatedAt = "2026-07-27T08:00:00Z"
        check("sunucu profili daha yeniyse kazanır",
              TravelProfileMerge.resolve(local: oldLocal, remote: newRemote) == newRemote)

        var equalRemote = seeded
        equalRemote.contactName = "Sunucu"
        equalRemote.updatedAt = oldLocal.updatedAt
        check("eşit zaman damgasında sunucu kararı sabittir",
              TravelProfileMerge.resolve(local: oldLocal, remote: equalRemote) == equalRemote)

        var malformedRemote = seeded
        malformedRemote.contactName = "Hatalı sunucu"
        malformedRemote.updatedAt = "2026-99-99"
        check("bozuk sunucu zamanı geçerli yereli ezmez",
              TravelProfileMerge.resolve(local: oldLocal, remote: malformedRemote) == oldLocal)

        var malformedLocal = oldLocal
        malformedLocal.updatedAt = "not-a-date"
        check("bozuk yerel zamanda geçerli sunucu kazanır",
              TravelProfileMerge.resolve(local: malformedLocal, remote: newRemote) == newRemote)

        print("\n=== Hesap yalıtımlı profil geçişi ===")
        let suiteName = "arrival-profile-store-check"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        let migrationDate = Date(timeIntervalSince1970: 1_785_000_000)
        let legacy = StayContactProfile(
            contactName: "Eski profil",
            adults: 3,
            vehicleDescription: "Eski Adria",
            additionalNeeds: "Sessiz alan"
        )
        defaults.set(try! JSONEncoder().encode(legacy), forKey: "stay-contact-profile-shared-route")

        let remoteA = AccountTravelProfile(contactName: "A sunucusu", updatedAt: "2026-07-01T00:00:00Z")
        let accountA = AccountUser(
            id: "account-a", email: "a@example.com", displayName: "A Kullanıcısı",
            globalRole: .user, createdAt: "2026-07-01T00:00:00Z", updatedAt: "2026-07-01T00:00:00Z",
            travelProfile: remoteA
        )
        let storeA = StayContactProfileStore(routeId: "shared-route", defaults: defaults, now: { migrationDate })
        let boundA = storeA.bind(account: accountA, vehicleSeed: "VW + Adria")
        check("zaman damgasız eski profil korunur", boundA.profile.contactName == "Eski profil")
        check("yerel yeni profil eşitleme ister", boundA.needsSync)
        check("eski kayıt ilk hesapta tüketilir",
              defaults.string(forKey: "stay-contact-profile-consumed-owner-shared-route") == "account-a"
                && defaults.data(forKey: "stay-contact-profile-shared-route") == nil)

        let accountB = AccountUser(
            id: "account-b", email: "b@example.com", displayName: "B Kullanıcısı",
            globalRole: .user, createdAt: "2026-07-01T00:00:00Z", updatedAt: "2026-07-01T00:00:00Z",
            travelProfile: AccountTravelProfile(contactName: "B sunucusu", updatedAt: "2026-07-02T00:00:00Z")
        )
        let storeB = StayContactProfileStore(routeId: "shared-route", defaults: defaults, now: { migrationDate })
        let boundB = storeB.bind(account: accountB, vehicleSeed: "B aracı")
        check("B hesabı A'nın eski profilini almaz", boundB.profile.contactName == "B sunucusu")

        let storeAOtherRoute = StayContactProfileStore(routeId: "other-route", defaults: defaults, now: { migrationDate })
        let boundAOtherRoute = storeAOtherRoute.bind(account: accountA, vehicleSeed: nil)
        check("hesap profili rota değişince korunur", boundAOtherRoute.profile.contactName == "Eski profil")
        let repeatedA = storeA.bind(account: accountA, vehicleSeed: nil)
        check("tekrar bağlama aynı hesabı korur", repeatedA.profile.contactName == "Eski profil")

        let signedOut = StayContactProfileStore(routeId: "shared-route", defaults: defaults, now: { migrationDate })
        signedOut.profile = StayContactProfile(contactName: "Yerel misafir", vehicleDescription: "Misafir araç")
        let freshB = StayContactProfileStore(routeId: "shared-route", defaults: defaults, now: { migrationDate })
        let boundBAgain = freshB.bind(account: accountB, vehicleSeed: nil)
        check("imzalı dışı taslak B hesabına taşınmaz", boundBAgain.profile.contactName == "B sunucusu")
        check("imzalı dışı taslak ayrı kullanılabilir", freshB.profile.contactName == "Yerel misafir")

        check("iki bozuk zaman damgasında sunucu sabit kazanır",
              TravelProfileMerge.resolve(local: malformedLocal, remote: malformedRemote) == malformedRemote)
        check("aynı hesap ve değişmeyen taslak yanıtı kabul eder",
              TravelProfileSaveGuard.accepts(
                currentAccountID: "account-a", requestAccountID: "account-a",
                submittedRevision: 4, currentRevision: 4
              ))
        check("hesap değişince yanıt reddedilir",
              !TravelProfileSaveGuard.accepts(
                currentAccountID: "account-b", requestAccountID: "account-a",
                submittedRevision: 4, currentRevision: 4
              ))
        check("taslak değişince yanıt reddedilir",
              !TravelProfileSaveGuard.accepts(
                currentAccountID: "account-a", requestAccountID: "account-a",
                submittedRevision: 4, currentRevision: 5
              ))
        check("A'nın geç yanıtı B oturumunu değiştiremez",
              !TravelProfileSessionGuard.accepts(
                currentAccountID: "account-b", currentAccessToken: "token-b",
                expectedAccountID: "account-a", expectedAccessToken: "token-a"
              ))
        check("aynı oturum sunucu profilini uygulayabilir",
              TravelProfileSessionGuard.accepts(
                currentAccountID: "account-a", currentAccessToken: "token-a",
                expectedAccountID: "account-a", expectedAccessToken: "token-a"
              ))
        let activeSave = UUID()
        check("eski kayıt tamamlanması yeni kaydı kapatamaz",
              !TravelProfileSaveOperationGuard.isCurrent(
                activeOperationID: UUID(), operationID: activeSave
              ))
        check("eşleşen kayıt tamamlanması yüklemeyi kapatır",
              TravelProfileSaveOperationGuard.isCurrent(
                activeOperationID: activeSave, operationID: activeSave
              ))
        let revisionBeforeLengthEdit = 6
        let revisionAfterLengthEdit = revisionBeforeLengthEdit + 1
        check("uzunluk düzenlemesi taslak sürümünü değiştirir",
              revisionAfterLengthEdit == 7 && !TravelProfileSaveGuard.accepts(
                currentAccountID: "account-a", requestAccountID: "account-a",
                submittedRevision: revisionBeforeLengthEdit, currentRevision: revisionAfterLengthEdit
              ))
        var sameSecondProfile = seeded
        sameSecondProfile.updatedAt = "2026-07-27T12:00:00Z"
        let submittedDraft = TravelProfileDraftFingerprint(
            profile: sameSecondProfile,
            totalLengthText: "10,5"
        )
        check("aynı saniyedeki tekrar kaydetme taslağı uzlaştırabilir",
              TravelProfileReconciliationGuard.accepts(
                currentAccountID: "account-a", requestAccountID: "account-a",
                activeOperationID: activeSave, operationID: activeSave,
                currentDraft: submittedDraft, submittedDraft: submittedDraft
              ))
        var editedDuringSave = sameSecondProfile
        editedDuringSave.additionalNeeds = "Sessiz köşe"
        check("kaydetme sırasında gerçek form düzenlemesi yanıtı reddeder",
              !TravelProfileReconciliationGuard.accepts(
                currentAccountID: "account-a", requestAccountID: "account-a",
                activeOperationID: activeSave, operationID: activeSave,
                currentDraft: TravelProfileDraftFingerprint(
                    profile: editedDuringSave, totalLengthText: "10,5"
                ),
                submittedDraft: submittedDraft
              ))
        check("yalnız uzunluk metni düzenlenirse yanıt reddedilir",
              !TravelProfileReconciliationGuard.accepts(
                currentAccountID: "account-a", requestAccountID: "account-a",
                activeOperationID: activeSave, operationID: activeSave,
                currentDraft: TravelProfileDraftFingerprint(
                    profile: sameSecondProfile, totalLengthText: "10.5"
                ),
                submittedDraft: submittedDraft
              ))
        check("boş uzunluk boş değer olur", TravelProfileLength.parse("") == .success(nil))
        check("virgüllü uzunluk okunur", TravelProfileLength.parse("10,5", locale: Locale(identifier: "tr_TR")) == .success(10.5))
        check("sınır dışı uzunluk reddedilir", TravelProfileLength.parse("31") == .failure(.outOfRange))
        check("bozuk uzunluk reddedilir", TravelProfileLength.parse("on") == .failure(.invalid))

        if failures > 0 {
            print("\n❌ \(failures) KONTROL BAŞARISIZ")
            exit(1)
        }
        print("\n✅ KESİN VARIŞ HEDEFİ KONTROLLERİ GEÇTİ")
    }
}
