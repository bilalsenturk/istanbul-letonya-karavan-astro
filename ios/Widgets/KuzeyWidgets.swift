import WidgetKit
import SwiftUI
import ActivityKit

@main
struct KuzeyWidgetsBundle: WidgetBundle {
    var body: some Widget {
        CountdownWidget()
        TripStatusWidget()
        TripLiveActivity()
    }
}

// Widget'a özel mini tema (app'in Theme'inden bağımsız, kendi kendine yeter).
enum WTheme {
    static let bg = Color(red: 0.06, green: 0.05, blue: 0.10)
    static let text = Color.white
    static let dim = Color.white.opacity(0.78)
    static let muted = Color.white.opacity(0.5)
    static let warm = LinearGradient(colors: [Color(red: 1, green: 0.60, blue: 0.24), Color(red: 1, green: 0.30, blue: 0.43)],
                                     startPoint: .topLeading, endPoint: .bottomTrailing)
    static let teal = Color(red: 0.31, green: 0.90, blue: 0.76)
}

// MARK: - Geri sayım widget'ı (yola çıkmaya kalan; StandBy'da gece panosu gibi durur)

struct CountdownEntry: TimelineEntry {
    let date: Date
    let departure: Date?
    let activeRouteStop: String?
}

struct CountdownProvider: TimelineProvider {
    private func current() -> CountdownEntry {
        CountdownEntry(
            date: .now,
            departure: SharedSnapshot.departureDate,
            activeRouteStop: SharedSnapshot.defaults?.string(forKey: SharedSnapshot.Key.activeRouteStop)
        )
    }

    func placeholder(in context: Context) -> CountdownEntry {
        CountdownEntry(date: .now, departure: .now.addingTimeInterval(14 * 86400), activeRouteStop: nil)
    }

    func getSnapshot(in context: Context, completion: @escaping (CountdownEntry) -> Void) {
        completion(current())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<CountdownEntry>) -> Void) {
        completion(Timeline(entries: [current()], policy: .after(.now.addingTimeInterval(15 * 60))))
    }
}

struct CountdownWidgetView: View {
    var entry: CountdownEntry
    @Environment(\.widgetFamily) private var family

    private var hasStartedRoute: Bool {
        entry.activeRouteStop?.isEmpty == false
    }

    var body: some View {
        Group {
            switch family {
            case .accessoryInline:
                if let d = entry.departure, d > .now {
                    Label { Text("Riga'ya çıkış: \(d, style: .relative)") } icon: { Image(systemName: "car.side.fill") }
                } else if hasStartedRoute {
                    Label(entry.activeRouteStop.map { "Rota aktif: \($0)" } ?? "Rota aktif", systemImage: "car.side.fill")
                } else {
                    Label("Kuzey · rota bekliyor", systemImage: "map.fill")
                }
            case .accessoryRectangular:
                VStack(alignment: .leading, spacing: 2) {
                    Text("İSTANBUL → RIGA").font(.caption2).opacity(0.7)
                    if let d = entry.departure, d > .now {
                        Text(d, style: .relative).font(.headline).bold()
                        Text("yola çıkmaya kalan").font(.caption2).opacity(0.7)
                    } else if hasStartedRoute {
                        Text("Rota aktif").font(.headline).bold()
                        Text(entry.activeRouteStop ?? "seçili durak").font(.caption2).opacity(0.7)
                    } else {
                        Text("Rota bekliyor").font(.headline).bold()
                        Text("Rotalar'dan başlat").font(.caption2).opacity(0.7)
                    }
                }
            default:
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 5) {
                        Image(systemName: "car.side.fill").font(.caption)
                        Text("KUZEY").font(.system(size: 10, weight: .heavy, design: .monospaced)).kerning(1.5)
                        Spacer()
                    }
                    .foregroundStyle(WTheme.teal)
                    Spacer(minLength: 0)
                    if let d = entry.departure, d > .now {
                        Text(d, style: .relative)
                            .font(.system(size: 24, weight: .heavy, design: .rounded))
                            .foregroundStyle(WTheme.text)
                            .minimumScaleFactor(0.5)
                        Text("yola çıkmaya kalan")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(WTheme.muted)
                    } else if hasStartedRoute {
                        Text("Rota aktif")
                            .font(.system(size: 22, weight: .heavy, design: .rounded))
                            .foregroundStyle(WTheme.text)
                        Text(entry.activeRouteStop ?? "Seçili durak")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(WTheme.muted)
                    } else {
                        Text("Rota bekliyor")
                            .font(.system(size: 22, weight: .heavy, design: .rounded))
                            .foregroundStyle(WTheme.text)
                        Text("Rotalar'dan başlat")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(WTheme.muted)
                    }
                }
                .padding(2)
            }
        }
        .containerBackground(for: .widget) { WTheme.bg }
    }
}

struct CountdownWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "KuzeyCountdown", provider: CountdownProvider()) {
            CountdownWidgetView(entry: $0)
        }
        .configurationDisplayName("Yola çıkış sayacı")
        .description("İstanbul → Riga kalkışına kalan süre.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryInline, .accessoryRectangular])
    }
}

// MARK: - Yol durumu widget'ı (sıradaki durak · kalan km · harcanan)

struct StatusEntry: TimelineEntry {
    let date: Date
    let nextStop: String?
    let nextCode: String?
    let remainingKm: Int?
    let remainingMin: Int?
    let spentEur: Double?
    let budgetMax: Double?
    let progress: Double
    let city: String?
    let navFresh: Bool   // nav verisi 1 saatten eskiyse false → "eski" işareti
}

struct StatusProvider: TimelineProvider {
    private func current() -> StatusEntry {
        let d = SharedSnapshot.defaults
        let km = d?.object(forKey: SharedSnapshot.Key.remainingKm) as? Int
        let min = d?.object(forKey: SharedSnapshot.Key.remainingMin) as? Int
        let spent = d?.object(forKey: SharedSnapshot.Key.spentEur) as? Double
        let budget = d?.object(forKey: SharedSnapshot.Key.budgetMax) as? Double
        let prog = (d?.object(forKey: SharedSnapshot.Key.legProgress) as? Int).map { Double($0) / 100 } ?? 0
        return StatusEntry(
            date: .now,
            nextStop: d?.string(forKey: SharedSnapshot.Key.nextStop),
            nextCode: d?.string(forKey: SharedSnapshot.Key.nextCode),
            remainingKm: km, remainingMin: min,
            spentEur: spent, budgetMax: budget,
            progress: prog,
            city: d?.string(forKey: SharedSnapshot.Key.currentCity),
            navFresh: SharedSnapshot.isNavFresh
        )
    }

    func placeholder(in context: Context) -> StatusEntry {
        StatusEntry(date: .now, nextStop: "Sofya", nextCode: "BG", remainingKm: 480, remainingMin: 340,
                    spentEur: 625, budgetMax: 1795, progress: 0.35, city: "İstanbul", navFresh: true)
    }

    func getSnapshot(in context: Context, completion: @escaping (StatusEntry) -> Void) { completion(current()) }

    func getTimeline(in context: Context, completion: @escaping (Timeline<StatusEntry>) -> Void) {
        completion(Timeline(entries: [current()], policy: .after(.now.addingTimeInterval(15 * 60))))
    }
}

struct TripStatusWidgetView: View {
    var entry: StatusEntry
    @Environment(\.widgetFamily) private var family

    private var timeText: String? {
        guard let m = entry.remainingMin else { return nil }
        return m >= 60 ? "\(m / 60) sa \(m % 60) dk" : "\(m) dk"
    }

    var body: some View {
        Group {
            switch family {
            case .accessoryInline:
                if let s = entry.nextStop, let km = entry.remainingKm {
                    // Eski nav verisini güncel gibi gösterme (intent'teki uyarıyla aynı).
                    Text("→ \(s) · \(km) km" + (entry.navFresh ? "" : " · eski"))
                } else {
                    Text("Kuzey · veri bekleniyor")
                }
            case .accessoryRectangular:
                VStack(alignment: .leading, spacing: 2) {
                    Text("SIRADAKİ · \(entry.nextStop?.uppercased() ?? "—")").font(.caption2).opacity(0.7)
                    Text(entry.remainingKm.map { "\($0) km" } ?? "—").font(.headline).bold()
                    if let t = timeText {
                        Text(entry.navFresh ? t : "\(t) · eski").font(.caption2).opacity(0.7)
                    } else if !entry.navFresh {
                        Text("eski veri").font(.caption2).opacity(0.7)
                    }
                }
            default:
                VStack(alignment: .leading, spacing: 7) {
                    HStack {
                        Text(entry.nextCode ?? "•")
                            .font(.system(size: 10, weight: .heavy, design: .rounded))
                            .padding(.horizontal, 5).padding(.vertical, 2)
                            .background(WTheme.warm, in: RoundedRectangle(cornerRadius: 5))
                        Text("Sıradaki: \(entry.nextStop ?? "—")")
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                            .lineLimit(1)
                        Spacer()
                    }
                    .foregroundStyle(WTheme.text)
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(entry.remainingKm.map { "\($0)" } ?? "—")
                            .font(.system(size: 30, weight: .heavy, design: .rounded))
                        Text("km" + (timeText.map { " · \($0)" } ?? "") + (entry.navFresh ? "" : " · eski"))
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(WTheme.muted)
                    }
                    .foregroundStyle(WTheme.text)
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(.white.opacity(0.12))
                            Capsule().fill(WTheme.warm).frame(width: geo.size.width * entry.progress)
                        }
                    }
                    .frame(height: 6)
                    HStack {
                        if let city = entry.city {
                            Label(city, systemImage: "location.fill")
                        }
                        Spacer()
                        if let s = entry.spentEur, let b = entry.budgetMax {
                            Text("€\(Int(s)) / €\(Int(b))")
                        }
                    }
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(WTheme.muted)
                }
                .padding(2)
            }
        }
        .containerBackground(for: .widget) { WTheme.bg }
    }
}

struct TripStatusWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "KuzeyStatus", provider: StatusProvider()) {
            TripStatusWidgetView(entry: $0)
        }
        .configurationDisplayName("Yol durumu")
        .description("Sıradaki durak, kalan km/süre ve harcanan.")
        .supportedFamilies([.systemMedium, .accessoryInline, .accessoryRectangular])
    }
}

// MARK: - Sürüş Live Activity (kilit ekranı + Dynamic Island)

struct TripLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: TripActivityAttributes.self) { context in
            // Kilit ekranı kartı
            HStack(spacing: 12) {
                Image(systemName: "car.side.fill")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(WTheme.teal)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Sıradaki: \(context.attributes.nextStop)")
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(.white.opacity(0.14))
                            Capsule().fill(WTheme.warm)
                                .frame(width: geo.size.width * context.state.progress)
                        }
                    }
                    .frame(height: 6)
                    Text("\(context.state.remainingKm) km · \(context.state.remainingMin >= 60 ? "\(context.state.remainingMin / 60) sa \(context.state.remainingMin % 60) dk" : "\(context.state.remainingMin) dk") · \(context.state.speedKmh) km/s")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.65))
                }
            }
            .foregroundStyle(.white)
            .padding(14)
            .activityBackgroundTint(WTheme.bg)
            .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    HStack(spacing: 6) {
                        Image(systemName: "car.side.fill").foregroundStyle(WTheme.teal)
                        Text(context.attributes.nextCode)
                            .font(.system(size: 12, weight: .heavy, design: .rounded))
                    }
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text("\(context.state.remainingKm) km")
                        .font(.system(size: 14, weight: .heavy, design: .rounded))
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(spacing: 5) {
                        Text("Sıradaki: \(context.attributes.nextStop) · \(context.state.remainingMin >= 60 ? "\(context.state.remainingMin / 60) sa \(context.state.remainingMin % 60) dk" : "\(context.state.remainingMin) dk")")
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                Capsule().fill(.white.opacity(0.14))
                                Capsule().fill(WTheme.warm)
                                    .frame(width: geo.size.width * context.state.progress)
                            }
                        }
                        .frame(height: 5)
                    }
                }
            } compactLeading: {
                Image(systemName: "car.side.fill").foregroundStyle(WTheme.teal)
            } compactTrailing: {
                Text("\(context.state.remainingKm) km")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
            } minimal: {
                Image(systemName: "car.side.fill").foregroundStyle(WTheme.teal)
            }
        }
    }
}
