import Foundation
import Speech

/// Cihazda Letonca konuşma tanıma var mı.
///
/// Cevap bugün her cihazda "hayır" ve bu bir arıza değil: Apple'ın konuşma tanıması
/// Letoncayı hiç içermiyor. iOS 26.3 çalışma zamanında `SFSpeechRecognizer.supportedLocales()`
/// 63 dil döndürüyor ve hiçbirinin dil kodu `lv` değil (Litvanca ve Estonca da yok),
/// dolayısıyla `SFSpeechRecognizer(locale: "lv-LV")` her cihazda `nil` dönüyor. İzin,
/// ayar ya da donanım meselesi değil — hiçbir kod değişikliği Letonca tanımayı var edemez.
///
/// Bu yüzden bayrak yanlışken telaffuz sorusu hiç üretilmiyor
/// (bkz. `LatvianCourseModel.startLesson`): öğrenciye cevaplanamayacak bir mikrofon
/// göstermenin anlamı yok. Düşürmenin bedeli ölçüldü — gerçek pakette hiçbir kelime
/// tüm soru tiplerini kaybetmiyor ve hiçbir kelimenin **üretim** tarafı kapanmıyor,
/// dolayısıyla sahne kilidi her kelime için kapanmaya devam ediyor
/// (bkz. `latvian-engine-check.swift`, "Telaffuz sorusu olmayan cihaz").
///
/// Bayrak neden burada: `Learning/` katmanı saf `Foundation` kalmak zorunda (çıplak
/// `swiftc` ile derleniyor, bkz. `run-latvian-check.sh`). `Speech`'e bağlı olan taraf
/// görünüm katmanı; ders kurucusu bayrağı dışarıdan alıyor.
enum LatvianSpeechAvailability {
    /// `static let` tembel ve tek seferlik: sorgu ilk ihtiyaçta bir kez yapılıyor,
    /// `SFSpeechRecognizer` kurulumu her ders başlangıcında tekrarlanmıyor.
    static let hasLatvian: Bool = SFSpeechRecognizer(locale: Locale(identifier: "lv-LV")) != nil
}
