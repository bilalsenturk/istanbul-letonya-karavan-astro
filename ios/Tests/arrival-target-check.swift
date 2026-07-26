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
    static func main() {
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
            preferredLanguage: .english
        )
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

        if failures > 0 {
            print("\n❌ \(failures) KONTROL BAŞARISIZ")
            exit(1)
        }
        print("\n✅ KESİN VARIŞ HEDEFİ KONTROLLERİ GEÇTİ")
    }
}
