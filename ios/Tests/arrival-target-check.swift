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
        check("ETA bir saatlik pencere üretir", eta.text == "18:00–19:00")

        let nearest = StayETACalculator.calculate(.init(
            departure: departure, drivingSeconds: 11 * 3600 + 5 * 60, calendar: calendar
        ))
        check("ETA en yakın yarım saate yuvarlar", nearest.text == "18:30–19:30")
        let halfBoundary = StayETACalculator.calculate(.init(
            departure: departure, drivingSeconds: 9 * 3600 + 30 * 60, calendar: calendar
        ))
        check("tam yarım saat ETA merkezini korur", halfBoundary.text == "17:00–18:00")

        let exactBoundary = StayETACalculator.calculate(.init(
            departure: departure,
            drivingSeconds: 9 * 3600,
            calendar: calendar
        ))
        check("tam saat ETA merkezini korur", exactBoundary.text == "16:30–17:30")

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
        check("ETA hedef saat diliminde yaz saati atlamasını taşır", dstETA.text == "04:00–05:00")

        let secondRepeatedRigaCenter = ISO8601DateFormatter().date(from: "2026-10-25T01:45:00Z")!
        let secondRepeatedRigaETA = StayETACalculator.calculate(.init(
            departure: secondRepeatedRigaCenter, drivingSeconds: 0, calendar: rigaCalendar
        ))
        let rigaWallClock = DateFormatter()
        rigaWallClock.locale = Locale(identifier: "en_GB")
        rigaWallClock.timeZone = rigaCalendar.timeZone
        rigaWallClock.dateFormat = "HH:mm zzz"
        check("Riga ikinci tekrar saatini UTC ile ayırt eder",
              rigaWallClock.string(from: secondRepeatedRigaCenter).contains("03:45")
                && rigaCalendar.timeZone.secondsFromGMT(for: secondRepeatedRigaCenter) == 2 * 3_600
                && secondRepeatedRigaETA.start <= secondRepeatedRigaCenter
                && secondRepeatedRigaCenter <= secondRepeatedRigaETA.end
                && (rigaWallClock.string(from: secondRepeatedRigaCenter).contains("GMT+2")
                    || rigaWallClock.string(from: secondRepeatedRigaCenter).contains("EET")))

        let fallBackDeparture = ISO8601DateFormatter().date(from: "2026-10-25T00:15:00Z")!
        let fallBack = StayETACalculator.calculate(.init(
            departure: fallBackDeparture, drivingSeconds: 45 * 60, calendar: rigaCalendar
        ))
        let fallCenter = fallBackDeparture.addingTimeInterval(45 * 60)
        check("DST geri saatte pencere mutlak olarak düzgündür",
              fallBack.start < fallBack.end && fallBack.end.timeIntervalSince(fallBack.start) == 3_600
                && fallBack.start <= fallCenter && fallCenter <= fallBack.end)
        let fallBackStartZone = rigaWallClock.string(from: fallBack.start).split(separator: " ").last.map(String.init) ?? ""
        let fallBackEndZone = rigaWallClock.string(from: fallBack.end).split(separator: " ").last.map(String.init) ?? ""
        check("DST geri saatte pencere iki ayrı Riga saat dilimini yazar",
              rigaCalendar.timeZone.secondsFromGMT(for: fallBack.start) == 3 * 3_600
                && rigaCalendar.timeZone.secondsFromGMT(for: fallBack.end) == 2 * 3_600
                && fallBackStartZone != fallBackEndZone
                && fallBack.text.contains(fallBackStartZone)
                && fallBack.text.contains(fallBackEndZone))

        let hugeETA = StayETACalculator.calculate(.init(
            departure: departure, drivingSeconds: 0, waypointMinutes: .max, borderBufferMinutes: .max, calendar: calendar
        ))
        check("çok büyük ETA payları sınırlanır", hugeETA.start < hugeETA.end
            && hugeETA.end.timeIntervalSince(departure) <= 15 * 24 * 60 * 60)
        check("çok büyük durak toplamı taşmaz", StayETAInput.boundedWaypointMinutes([.max, .max]) == 10_080)

        let manualWindow = StayETAWindow(start: departure, end: departure.addingTimeInterval(3_600), timeZoneIdentifier: "Europe/Istanbul")
        let manualStay = StayDetails(estimatedArrival: "08:00–09:00", estimatedArrivalMode: .manual, estimatedArrivalWindow: manualWindow)
        let automaticWindow = StayETAWindow(start: departure.addingTimeInterval(7_200), end: departure.addingTimeInterval(10_800), timeZoneIdentifier: "Europe/Istanbul")
        check("manuel ETA hesaplanan varsayılanı korur",
              StayArrivalModeResolver.applyingAutomaticDefault(automaticWindow, to: manualStay) == manualStay)
        let restored = StayArrivalModeResolver.useAutomatic(automaticWindow, replacing: manualStay)
        check("otomatik seçimi manuel pencereyi değiştirir",
              restored.estimatedArrivalMode == .automatic && restored.estimatedArrivalWindow == automaticWindow
                && restored.estimatedArrival == automaticWindow.text)
        let encodedManualStay = try! JSONEncoder().encode(AccountStayDetails(manualStay))
        let decodedManualStay = try! JSONDecoder().decode(AccountStayDetails.self, from: encodedManualStay).resolved
        check("manuel ETA hesap JSON turunda korunur",
              decodedManualStay.estimatedArrivalMode == .manual
                && decodedManualStay.estimatedArrivalWindow == manualWindow
                && decodedManualStay.estimatedArrival == manualStay.estimatedArrival)

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

        var turkishProfile = profile
        turkishProfile.preferredLanguage = .turkish
        turkishProfile.hasPet = true
        let turkishFlight = StayMessageComposer.compose(
            target: target, stay: stay, profile: turkishProfile, transportMode: .flight,
            camp: .init(maximumLengthMeters: 8)
        )
        check("uçak Türkçe mesajında araç sınırı yok",
              !turkishFlight.body.contains("Passat") && !turkishFlight.body.contains("10.8")
                && !turkishFlight.body.contains("8.0") && !turkishFlight.body.contains("Elektrik"))
        check("uçak Türkçe mesajında yolcu pet ve ihtiyaç var",
              turkishFlight.body.contains("2 yetişkin ve 1 çocuk")
                && turkishFlight.body.contains("Evcil hayvan") && turkishFlight.body.contains("Quiet pitch"))

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
              whatsApp?.absoluteString.contains("phone=359881234567") == true)
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

        print("\n=== Hazırlanmış iletişim eylemleri ===")
        let exactBody = "Merhaba & + % /?= — aynı metin"
        let exactMessage = StayMessage(subject: "Konaklama & fiyat", body: exactBody)
        let mailAction = StayContactAction.email.prepare(message: exactMessage, target: target)
        check("e-posta hazırlığı alıcı konu ve gövdeyi değiştirmez",
              mailAction?.recipient == "hello@example.com"
                && mailAction?.subject == "Konaklama & fiyat"
                && mailAction?.body == exactBody)
        let messagesAction = StayContactAction.messages.prepare(message: exactMessage, target: target)
        check("Mesajlar hazırlığı telefon ve gövdeyi taşır",
              messagesAction?.recipient == "+359881234567" && messagesAction?.body == exactBody)
        let whatsAppAction = StayContactAction.whatsApp.prepare(message: exactMessage, target: target)
        check("WhatsApp hazırlığı E.164 alıcı ve özgün gövde taşır",
              whatsAppAction?.recipient == "359881234567" && whatsAppAction?.body == exactBody)
        check("her kanal panoya aynı gövdeyi verir",
              mailAction?.clipboardText == exactBody
                && messagesAction?.clipboardText == exactBody
                && whatsAppAction?.clipboardText == exactBody)
        var missingEmailTarget = target
        missingEmailTarget.email = "geçersiz"
        check("geçersiz e-posta eylemi hazırlanmaz",
              StayContactAction.email.prepare(message: exactMessage, target: missingEmailTarget) == nil)
        var missingPhoneTarget = target
        missingPhoneTarget.phone = "telefon yok"
        missingPhoneTarget.whatsAppPhone = nil
        check("geçersiz telefonla Mesajlar eylemi hazırlanmaz",
              StayContactAction.messages.prepare(message: exactMessage, target: missingPhoneTarget) == nil)
        check("geçersiz telefonla WhatsApp eylemi hazırlanmaz",
              StayContactAction.whatsApp.prepare(message: exactMessage, target: missingPhoneTarget) == nil)
        let encodedWhatsApp = ContactLinkBuilder.whatsAppURL(phone: target.phone, message: exactBody)
        check("WhatsApp URL'si gövdenin ayırıcılarını kodlar",
              encodedWhatsApp?.absoluteString.contains("%26") == true
                && encodedWhatsApp?.absoluteString.contains("%25") == true
                && !(encodedWhatsApp?.absoluteString.contains("?text=Merhaba%20&") ?? true))
        check("WhatsApp doğrudan uygulama şemasını kullanır",
              encodedWhatsApp?.scheme == "whatsapp" && encodedWhatsApp?.host == "send")
        check("WhatsApp 00 önekli numarayı E.164'e çevirir",
              ContactLinkBuilder.normalizedWhatsAppPhone("00359 881 234 567") == "359881234567")
        check("WhatsApp en uzun 15 haneli numarayı kabul eder",
              ContactLinkBuilder.normalizedWhatsAppPhone("+123456789012345") == "123456789012345")
        check("WhatsApp biçimli artı, 00 ve yalın numarayı kabul eder",
              ContactLinkBuilder.normalizedWhatsAppPhone(" +359 (88) 123-45 67 ") == "359881234567"
                && ContactLinkBuilder.normalizedWhatsAppPhone("00 359 (88) 123-45 67") == "359881234567"
                && ContactLinkBuilder.normalizedWhatsAppPhone("359 881 234 567") == "359881234567")
        check("WhatsApp Unicode rakamlarını ve geçersiz önekleri reddeder",
              ContactLinkBuilder.normalizedWhatsAppPhone("+٣٥٩٨٨١٢٣٤٥٦٧") == nil
                && ContactLinkBuilder.normalizedWhatsAppPhone("+000359881234567") == nil
                && ContactLinkBuilder.normalizedWhatsAppPhone("+1234567") == nil
                && ContactLinkBuilder.normalizedWhatsAppPhone("+1234567890123456") == nil
                && ContactLinkBuilder.normalizedWhatsAppPhone("+359call881234567") == nil
                && ContactLinkBuilder.normalizedWhatsAppPhone("++359881234567") == nil
                && ContactLinkBuilder.normalizedWhatsAppPhone("00+359881234567") == nil
                && ContactLinkBuilder.normalizedWhatsAppPhone("(00)359881234567") == nil
                && ContactLinkBuilder.normalizedWhatsAppPhone("+359+881234567") == nil)

        let handoffID = UUID()
        var handoff = WhatsAppHandoffState()
        handoff.begin(actionID: handoffID)
        check("WhatsApp başarı önce gelse dönüşte bir kez sorar",
              handoff.openCompleted(actionID: handoffID, opened: true) == .none
                && handoff.becameInactive() == .none
                && handoff.becameActive() == .offerAwaitingReply
                && handoff.becameActive() == .none)
        var completionAfterReturn = WhatsAppHandoffState()
        completionAfterReturn.begin(actionID: handoffID)
        check("WhatsApp dönüşü tamamlanmadan önce olursa başarı sonrası sorar",
              completionAfterReturn.becameInactive() == .none
                && completionAfterReturn.becameActive() == .none
                && completionAfterReturn.openCompleted(actionID: handoffID, opened: true) == .offerAwaitingReply)
        var failedHandoff = WhatsAppHandoffState()
        failedHandoff.begin(actionID: handoffID)
        check("başarısız WhatsApp açılışı geç gelse bile yalnız bir kez kullanılamaz der",
              failedHandoff.becameInactive() == .none
                && failedHandoff.openCompleted(actionID: handoffID, opened: false) == .showUnavailable
                && failedHandoff.becameActive() == .none
                && failedHandoff.openCompleted(actionID: handoffID, opened: false) == .none)
        var staleHandoff = WhatsAppHandoffState()
        staleHandoff.begin(actionID: handoffID)
        let replacementID = UUID()
        staleHandoff.begin(actionID: replacementID)
        check("eski WhatsApp geri çağrısı yeni eylemi soramaz",
              staleHandoff.openCompleted(actionID: handoffID, opened: true) == .none
                && staleHandoff.becameInactive() == .none
                && staleHandoff.becameActive() == .none)
        check("gönderim sonrası durum yardımı yalnız açık onayla beklemeye geçer",
              StayContactFollowUp.shouldOfferAwaitingReply(after: .sent)
                && !StayContactFollowUp.shouldOfferAwaitingReply(after: .cancelled)
                && !StayContactFollowUp.shouldOfferAwaitingReply(after: .failed)
                && StayContactFollowUp.shouldMarkAwaitingReply(userConfirmed: true)
                && !StayContactFollowUp.shouldMarkAwaitingReply(userConfirmed: false))

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
