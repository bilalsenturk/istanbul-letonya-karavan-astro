import Foundation

// Open-Meteo: API anahtarı gerektirmez. Web ile aynı kaynak.
struct StopWeather: Identifiable {
    let id: String
    let name: String
    let flag: String
    let temp: Int
    let icon: String
    let desc: String
    let isRaining: Bool
}

@MainActor
final class WeatherService: ObservableObject {
    @Published var items: [StopWeather] = []
    @Published var updatedAt: Date?

    private static let wmo: [Int: (String, String)] = [
        0: ("☀️", "Açık"), 1: ("🌤️", "Genelde açık"), 2: ("⛅", "Parçalı bulutlu"), 3: ("☁️", "Bulutlu"),
        45: ("🌫️", "Sisli"), 48: ("🌫️", "Kırağı sisi"),
        51: ("🌦️", "Hafif çisenti"), 53: ("🌦️", "Çisenti"), 55: ("🌦️", "Yoğun çisenti"),
        61: ("🌧️", "Hafif yağmur"), 63: ("🌧️", "Yağmur"), 65: ("🌧️", "Kuvvetli yağmur"),
        71: ("🌨️", "Hafif kar"), 73: ("🌨️", "Kar"), 75: ("🌨️", "Yoğun kar"),
        80: ("🌦️", "Sağanak"), 81: ("🌧️", "Sağanak"), 82: ("⛈️", "Kuvvetli sağanak"),
        95: ("⛈️", "Gök gürültülü"), 96: ("⛈️", "Dolu + fırtına"), 99: ("⛈️", "Dolu + fırtına"),
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
            let (icon, desc) = Self.wmo[cur.weather_code] ?? ("🌡️", "—")
            result.append(
                StopWeather(
                    id: stop.id,
                    name: stop.name,
                    flag: stop.flag,
                    temp: Int(cur.temperature_2m.rounded()),
                    icon: icon,
                    desc: desc,
                    isRaining: cur.precipitation > 0
                )
            )
        }
        items = result
        updatedAt = Date()
    }
}
