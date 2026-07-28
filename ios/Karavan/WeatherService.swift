import Foundation

// Open-Meteo: API anahtarı gerektirmez. Web ile aynı kaynak.
// Görsel: sistem SF Symbols (multicolor) — native hava widget'ı hissi.
struct StopWeather: Identifiable {
    let id: String
    let name: String
    let flag: String
    let code: String
    let temp: Int
    let symbol: String
    let desc: String
    let isRaining: Bool
    /// Bu durağın verisinin gerçekten yenilendiği an — kısmi yanıtta eski
    /// verisi korunan durak "az önce güncellendi" yalanı söylemesin diye.
    var updatedAt: Date? = nil
}

@MainActor
final class WeatherService: ObservableObject {
    @Published var items: [StopWeather] = []
    @Published var updatedAt: Date?

    // Hava değişiminde bildirim göndermek için (opsiyonel).
    weak var notifier: NotificationManager?

    // WMO kodu → (SF Symbol, Türkçe açıklama)
    private static let wmo: [Int: (String, String)] = [
        0: ("sun.max.fill", "Açık"), 1: ("sun.min.fill", "Genelde açık"),
        2: ("cloud.sun.fill", "Parçalı bulutlu"), 3: ("cloud.fill", "Bulutlu"),
        45: ("cloud.fog.fill", "Sisli"), 48: ("cloud.fog.fill", "Kırağı sisi"),
        51: ("cloud.drizzle.fill", "Hafif çisenti"), 53: ("cloud.drizzle.fill", "Çisenti"), 55: ("cloud.drizzle.fill", "Yoğun çisenti"),
        61: ("cloud.rain.fill", "Hafif yağmur"), 63: ("cloud.rain.fill", "Yağmur"), 65: ("cloud.heavyrain.fill", "Kuvvetli yağmur"),
        71: ("cloud.snow.fill", "Hafif kar"), 73: ("cloud.snow.fill", "Kar"), 75: ("cloud.snow.fill", "Yoğun kar"),
        80: ("cloud.sun.rain.fill", "Sağanak"), 81: ("cloud.rain.fill", "Sağanak"), 82: ("cloud.heavyrain.fill", "Kuvvetli sağanak"),
        95: ("cloud.bolt.rain.fill", "Gök gürültülü"), 96: ("cloud.bolt.rain.fill", "Dolu + fırtına"), 99: ("cloud.bolt.rain.fill", "Dolu + fırtına"),
    ]

    private struct OMCurrent: Decodable {
        let temperature_2m: Double
        let precipitation: Double
        let weather_code: Int
    }

    private struct OMResponse: Decodable {
        let current: OMCurrent
        // Çok duraklı yanıtta her eleman kendi koordinatını döner — kısmi
        // yanıtta durakları kaydırmadan eşleştirmek için kullanılır.
        let latitude: Double?
        let longitude: Double?
    }

    func refresh(stops: [Stop]) async {
        guard !stops.isEmpty else { return }
        let lats = stops.map { String($0.lat) }.joined(separator: ",")
        let lngs = stops.map { String($0.lng) }.joined(separator: ",")
        let urlString = "https://api.open-meteo.com/v1/forecast?latitude=\(lats)&longitude=\(lngs)&current=temperature_2m,precipitation,weather_code&timezone=auto"
        guard let url = URL(string: urlString) else { return }

        guard let (data, response) = try? await URLSession.shared.data(from: url),
              let http = response as? HTTPURLResponse, http.statusCode == 200
        else { return }

        // Tek durak → obje, çok durak → dizi döner
        let decoder = JSONDecoder()
        let responses: [OMResponse]
        if let many = try? decoder.decode([OMResponse].self, from: data) {
            responses = many
        } else if let one = try? decoder.decode(OMResponse.self, from: data) {
            responses = [one]
        } else {
            return
        }

        let now = Date()
        var result: [StopWeather] = []
        var anyFresh = false
        // Yanıt elemanlarını duraklara koordinatla eşle (Open-Meteo istenen
        // noktaya en yakın grid koordinatını döner; ~0.1° tolerans yeter).
        // Koordinat yoksa konumsal eşleme ancak eleman sayısı durak sayısına
        // eşitken güvenli — ortası eksik kısmi yanıtta hava yanlış durağa kayar.
        let positional = responses.count == stops.count
        var used = Set<Int>()
        for (i, stop) in stops.enumerated() {
            var match: OMResponse?
            if let j = responses.indices.first(where: { j in
                guard !used.contains(j),
                      let la = responses[j].latitude, let lo = responses[j].longitude
                else { return false }
                return abs(la - stop.lat) < 0.1 && abs(lo - stop.lng) < 0.1
            }) {
                used.insert(j)
                match = responses[j]
            } else if positional, !used.contains(i) {
                used.insert(i)
                match = responses[i]
            }
            guard let cur = match?.current else {
                // Kısmi yanıt: eksik durağın önceki verisini ESKİ updatedAt'iyle
                // koru ki yağmur bildirimleri tekrar atılmasın ama tazelik
                // zamanı da gerçeği söylesin.
                if let old = items.first(where: { $0.id == stop.id }) { result.append(old) }
                continue
            }
            let (symbol, desc) = Self.wmo[cur.weather_code] ?? ("thermometer.medium", "—")
            result.append(
                StopWeather(
                    id: stop.id,
                    name: stop.name,
                    flag: stop.flag,
                    code: stop.code,
                    temp: Int(cur.temperature_2m.rounded()),
                    symbol: symbol,
                    desc: desc,
                    isRaining: cur.precipitation > 0,
                    updatedAt: now
                )
            )
            anyFresh = true
        }
        items = result
        if anyFresh { updatedAt = now }   // hiç taze veri yoksa "az önce güncellendi" deme
        detectAndNotifyChanges(result)
    }

    // MARK: - Hava değişimi algısı → bildirim

    private struct Snap: Codable { let raining: Bool; let desc: String }

    private var lastSnapshot: [String: Snap] {
        get {
            guard let data = UserDefaults.standard.data(forKey: "weatherSnapshot"),
                  let decoded = try? JSONDecoder().decode([String: Snap].self, from: data)
            else { return [:] }
            return decoded
        }
        set {
            UserDefaults.standard.set(try? JSONEncoder().encode(newValue), forKey: "weatherSnapshot")
        }
    }

    private func detectAndNotifyChanges(_ items: [StopWeather]) {
        let previous = lastSnapshot
        let isFirstEver = previous.isEmpty
        var next: [String: Snap] = [:]

        for w in items {
            next[w.id] = Snap(raining: w.isRaining, desc: w.desc)
            guard !isFirstEver, let prev = previous[w.id] else { continue }

            if !prev.raining && w.isRaining {
                notifier?.notify(title: "\(w.name) · yağmur başladı", body: "\(w.desc), \(w.temp)°")
            } else if prev.raining && !w.isRaining {
                notifier?.notify(title: "\(w.name) · yağmur durdu", body: "\(w.desc), \(w.temp)°")
            } else if prev.desc != w.desc && isSevere(w.desc) {
                notifier?.notify(title: "\(w.name) · \(w.desc)", body: "Dikkatli sür — \(w.temp)°")
            }
        }
        lastSnapshot = next
    }

    private func isSevere(_ desc: String) -> Bool {
        ["kuvvetli", "fırtına", "dolu", "sağanak", "gürültü"]
            .contains { desc.localizedCaseInsensitiveContains($0) }
    }
}
