import Foundation

/// Tam ekran açılan bir ders koşusu.
struct LatvianLessonRun: Identifiable, Equatable {
    let id: Int
    let sceneId: String
    let exercises: [LatvianExercise]
}

/// Ders sonu ekranının çizeceği özet. Ders bitip ilerleme **diske yazıldıktan
/// sonra** üretiliyor; kutlama ekranı hiçbir şeyin sonucunu beklemiyor.
struct LatvianCelebration: Identifiable, Equatable {
    let id: Int
    let xp: Int
    let accuracy: Double
    let streakDays: Int
    let streakExtended: Bool
    let isFailed: Bool
}

/// İlerleme dosyasının durumu. Arayüz bunu Türkçe bir şeride çeviriyor.
enum LatvianStorageState: Equatable {
    case ok
    /// Ana dosya okunamadı, yedekten devam edildi.
    case recovered
    /// Ne ana dosya ne yedek okunabildi; sıfırdan başlandı.
    case reset
    /// Diske yazılamadı.
    case saveFailed
}

/// Kurs ekranının saf hesapları: rota durakları, can zamanı, ders tohumu.
///
/// Hepsi durumsuz ve `now`'ı dışarıdan alıyor — motorun kuralı arayüz katmanında
/// da sürüyor. `LatvianCourseModel` bunları çağırıp sonuçlarını yayımlıyor.
enum LatvianCourseRules {

    /// Paketteki sahneleri ekranda gösterilecek duraklara çevirir.
    ///
    /// Kilit "önceki sahnelerin hepsi geçildi mi" demek. Sahne başına ayrı ayrı
    /// `LatvianLessonBuilder.isSceneUnlocked` sormak bunu kareye çıkarırdı;
    /// sırayla gezip tek bir bayrak taşımak aynı sonucu doğrusal veriyor.
    static func stops(pack: LatvianPack, progress: LatvianProgress, now: Date) -> [LatvianRouteStop] {
        var previousCleared = true
        var result: [LatvianRouteStop] = []
        result.reserveCapacity(pack.scenes.count)
        for scene in pack.scenes.sorted(by: { $0.index < $1.index }) {
            let cleared = LatvianLessonBuilder.isSceneCleared(
                scene: scene, progress: progress, now: now
            )
            result.append(
                LatvianRouteStop(
                    id: scene.id,
                    title: scene.title,
                    index: scene.index,
                    isUnlocked: previousCleared,
                    isCleared: cleared,
                    masteryRatio: LatvianLessonBuilder.masteryRatio(
                        scene: scene, progress: progress, now: now
                    )
                )
            )
            previousCleared = previousCleared && cleared
        }
        return result
    }

    /// Maskotun bekleyeceği durak: açık ama henüz geçilmemiş ilki. Hepsi
    /// geçildiyse açık olan son durak.
    static func currentStopId(in stops: [LatvianRouteStop]) -> String? {
        stops.first { $0.isUnlocked && !$0.isCleared }?.id ?? stops.last { $0.isUnlocked }?.id
    }

    /// Canlar eksikken bir sonraki canın geleceği an; doluyken `nil`.
    static func nextHeartAt(progress: LatvianProgress) -> Date? {
        guard progress.hearts < LatvianProgress.maxHearts,
              let anchor = progress.lastHeartLostAt else { return nil }
        return anchor.addingTimeInterval(LatvianProgress.heartRefillInterval)
    }

    /// Canı biten öğrenciye ne zaman dönebileceğini söyleyen cümle. Ölü bir
    /// düğmeyle baş başa bırakmamak için var.
    static func outOfHeartsNotice(at moment: Date?) -> String {
        guard let moment else { return "Canların bitti." }
        return "Canların bitti. Sonraki can \(moment.formatted(date: .omitted, time: .shortened)) civarında geliyor."
    }

    /// Ders tohumu. `Int64(exactly:)` kullanılıyor: bozuk bir saatten gelen uçuk
    /// tarih `Int64(...)` dönüşümünde uygulamayı düşürürdü. Sayaç, aynı
    /// milisaniyede başlatılan iki dersin aynı soruları almasını engelliyor.
    static func seed(now: Date, counter: Int) -> UInt64 {
        let millis = Int64(exactly: (now.timeIntervalSince1970 * 1000).rounded()) ?? 0
        return UInt64(bitPattern: millis) &* 0x9E37_79B9_7F4A_7C15 &+ UInt64(counter)
    }
}
