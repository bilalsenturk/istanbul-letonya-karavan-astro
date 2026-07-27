import Foundation

#if DEBUG
extension AccountUser {
    static let previewAdmin = AccountUser(
        id: "preview-admin",
        email: "senturk.bilal@icloud.com",
        displayName: "Bilal Şentürk",
        globalRole: .globalAdmin,
        createdAt: "2026-07-26T08:00:00Z",
        updatedAt: "2026-07-26T08:00:00Z",
        travelProfile: AccountTravelProfile(
            contactName: "Bilal Şentürk",
            contactEmail: "senturk.bilal@icloud.com",
            adults: 2,
            children: 1,
            vehicleDescription: "VW Passat + Adria",
            totalLengthMeters: 10.8,
            needsElectricity: true,
            hasPet: false,
            additionalNeeds: "",
            preferredLanguage: .english,
            updatedAt: "2026-07-26T08:00:00Z"
        )
    )
}

extension AccountTrip {
    static let previewStandard = AccountTrip(
        id: "preview-balkan",
        name: "Balkan Yazı",
        kind: .standard,
        transportMode: .automobile,
        revision: 7,
        createdAt: "2026-07-26T08:00:00Z",
        updatedAt: "2026-07-26T08:20:00Z",
        stops: [
            AccountRouteStop(id: "istanbul", name: "İstanbul", lat: 41.0082, lng: 28.9784, order: 0, note: "Başlangıç", arrivalAt: nil, accommodation: nil, link: nil),
            AccountRouteStop(id: "plovdiv", name: "Filibe", lat: 42.1354, lng: 24.7453, order: 1, note: "Öğle molası", arrivalAt: nil, accommodation: nil, link: nil),
            AccountRouteStop(id: "sofia", name: "Sofya", lat: 42.6977, lng: 23.3219, order: 2, note: "İlk gece", arrivalAt: "2026-08-03T17:00:00Z", accommodation: "Sofia Camping", link: nil)
        ],
        members: [
            AccountTripMember(userId: "preview-admin", role: .owner),
            AccountTripMember(userId: "preview-member", role: .member)
        ],
        invites: [AccountTripInvite(email: "arkadas@example.com", role: .viewer)],
        features: .standard,
        access: TripAccess(tripRole: .owner, canEditTrip: true, canEditStops: true, canEditJournal: true, canManageMembers: true, canStartRoute: true, canDeleteTrip: true)
    )

    static let previewKuzey = AccountTrip(
        id: "kuzey-2026",
        name: "Leyla'nın Kuzey Yolculuğu",
        kind: .kuzey2026,
        transportMode: .automobile,
        revision: 14,
        createdAt: "2026-07-26T08:00:00Z",
        updatedAt: "2026-07-26T08:20:00Z",
        stops: [
            kuzeyStop("istanbul", "İstanbul", 41.0082, 28.9784, 0, source: .currentLocation),
            kuzeyStop("sofia", "Sofya", 42.63252, 23.57471, 1, target: previewTarget(
                "sunset-garden-camping", "Sunset Garden Camping", 42.63252, 23.57471,
                "33 1-vi May, 2109 Elin Pelin, Sofia, Bulgaristan"
            )),
            kuzeyStop("novi-sad", "Novi Sad", 45.2410861, 20.0255373, 2, target: previewTarget(
                "camping-campuccino", "Camping Campuccino", 45.2410861, 20.0255373,
                "Branka Bajića 60, 21243 Kovilj, Sırbistan", phone: "+381 63 222 783",
                email: "info@campuccino.org", website: "https://campuccino.org/"
            )),
            kuzeyStop("budapest", "Budapeşte", 47.504162, 19.1561948, 3, target: previewTarget(
                "arena-camping-budapest", "Aréna Camping Budapest", 47.504162, 19.1561948,
                "Pilisi utca 7, 1106 Budapest, Macaristan", phone: "+36 30 296 9129",
                email: "info@budapestcamping.hu", website: "https://arenacamping.eu/en"
            )),
            kuzeyStop("krakow", "Krakow", 50.0467778, 19.9031667, 4, target: previewTarget(
                "camping-adam-krakow", "Camping Adam", 50.0467778, 19.9031667,
                "Wioślarska 19, 30-206 Kraków, Polonya", phone: "+48 519 15 98 64",
                email: "info@campingadam.pl", website: "https://campingadam.pl/"
            )),
            kuzeyStop("warsaw", "Varşova", 52.17798, 21.14727, 5, target: previewTarget(
                "camping-motel-wok", "Camping Motel WOK", 52.17798, 21.14727,
                "Odrębna 16, 04-867 Warszawa, Polonya", phone: "+48 22 612 79 51",
                email: "wok@campingwok.warszawa.pl", website: "https://campingwok.warszawa.pl/"
            )),
            kuzeyStop("riga", "Riga", 56.96117, 24.09431, 6, target: previewTarget(
                "camping-yachts-riga", "Camping Yachts", 56.96117, 24.09431,
                "Matrožu iela 7A, Riga, Letonya", phone: "+371 29 205 543",
                email: "info@campingyachts.lv", website: "https://campingyachts.lv/"
            ))
        ],
        members: [AccountTripMember(userId: "preview-admin", role: .owner)],
        invites: [],
        features: .kuzey,
        access: TripAccess(tripRole: .owner, canEditTrip: true, canEditStops: true, canEditJournal: true, canManageMembers: true, canStartRoute: true, canDeleteTrip: true)
    )

    private static func kuzeyStop(
        _ id: String,
        _ name: String,
        _ lat: Double,
        _ lng: Double,
        _ order: Int,
        source: RouteStopSource = .place,
        target: AccountArrivalTarget? = nil
    ) -> AccountRouteStop {
        AccountRouteStop(
            id: id, name: name, lat: lat, lng: lng, order: order, source: source,
            note: order == 0 ? "Kalkışta güncel konum kullanılır." : nil,
            arrivalAt: nil, accommodation: target?.name, link: target?.websiteURL,
            arrivalTarget: target,
            stayDetails: target.map { _ in AccountStayDetails(StayDetails()) }
        )
    }

    private static func previewTarget(
        _ id: String,
        _ name: String,
        _ latitude: Double,
        _ longitude: Double,
        _ address: String,
        phone: String? = nil,
        email: String? = nil,
        website: String? = nil
    ) -> AccountArrivalTarget {
        AccountArrivalTarget(ArrivalTarget(
            id: id, mapItemIdentifier: nil, name: name, kind: .campground,
            latitude: latitude, longitude: longitude, formattedAddress: address,
            phone: phone, whatsAppPhone: phone, email: email,
            websiteURL: website.flatMap(URL.init(string:)), source: .migrated,
            updatedAt: Date(timeIntervalSince1970: 1_753_488_000)
        ))
    }
}
#endif
