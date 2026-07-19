import Foundation

// Open-Meteo: API anahtarı gerektirmez. Web ile aynı kaynak.
// Görsel: sistem SF Symbols (multicolor) — native hava widget'ı hissi.
struct StopWeather: Identifiable {
    let id: String
    let name: String
    let flag: String
    let temp: Int
    let symbol: String
    let desc: String
    let isRaining: Bool
}

@MainActor
final class WeatherService: ObservableObject {
    @Published var items: [StopWeather] = []
    @Published var updatedAt: Date?

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

        var result: [StopWeather] = []
        for (i, stop) in stops.enumerated() where i < responses.count {
            let cur = responses[i].current
            let (symbol, desc) = Self.wmo[cur.weather_code] ?? ("thermometer.medium", "—")
            result.append(
                StopWeather(
                    id: stop.id,
                    name: stop.name,
                    flag: stop.flag,
                    temp: Int(cur.temperature_2m.rounded()),
                    symbol: symbol,
                    desc: desc,
                    isRaining: cur.precipitation > 0
                )
            )
        }
        items = result
        updatedAt = Date()
    }
}
