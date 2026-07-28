import SwiftUI

/// Letonca kursunun ayar sayfası: ses, telaffuz, titreşim, hatırlatma ve
/// indirilmiş kliplerin durumu.
///
/// Üst çubuktaki dişliden bir yaprak (`sheet`) olarak açılıyor. Yaprak seçildi,
/// `NavigationLink` seçilmedi: bağlı olduğu `NavigationStack` bu ekranın değil,
/// `ToolsView`'in. Oraya dayanan bir bağlantı, o dosya yeniden düzenlendiğinde
/// sessizce hiçbir şey yapmayan bir düğmeye dönüşürdü.
///
/// **Hiçbir anahtar kendi kopyasını tutmuyor.** Üçü de sahibinin yayımlanan
/// alanına bağlı (`LatvianFeedback`, `LatvianAudioStore`, `LatvianCourseModel`),
/// böylece ayarın etkisi ile ekrandaki hâli asla ayrışmıyor. Özellikle bildirim
/// anahtarı: kendi `@AppStorage`'ıyla tutulsaydı `LatvianCourseModel`'in okuduğu
/// anahtardan (`letonca.bildirimAcik`) bağımsız ikinci bir değer olurdu ve
/// kapatmak kurulu bildirimleri gerçekten silmezdi.
///
/// **Yıkıcı denetim yok, bilerek.** "İlerlemeyi sıfırla" ve "sesleri sil"
/// düşünüldü ve ikisi de eklenmedi: ilerleme sıfırlaması geri alınamaz ve
/// kursun tek kaydını siler; ses silme ise kendini bozar — kurs her açılışta
/// eksik klipleri yeniden indirdiği için düğme bir sonraki açılışta kendi işini
/// geri alır. Kendini geri alan bir düğme, olmayan düğmeden kötüdür.
struct LatvianSettingsView: View {
    @ObservedObject var model: LatvianCourseModel
    @ObservedObject var audio: LatvianAudioStore
    @ObservedObject var feedback: LatvianFeedback

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                soundSection
                clipSection
                notificationSection
                progressSection
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(Theme.bg.ignoresSafeArea())
            .navigationTitle("Letonca ayarları")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Bitti") { dismiss() }
                        .accessibilityLabel("Ayarları kapat")
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    // MARK: - Ses

    private var soundSection: some View {
        Section {
            row("Ses efektleri", isOn: $feedback.soundsEnabled,
                hint: "Doğru, yanlış, kombo ve XP sesleri.")
            row("Telaffuz sesi", isOn: $audio.speechEnabled,
                hint: "Kelimelerin Letonca okunuşu.")
            row("Titreşim", isOn: $feedback.hapticsEnabled,
                hint: "Cevap ve can geri bildirimlerinde titreşim.")
        } header: {
            header("Ses ve titreşim")
        } footer: {
            footer(
                "Telaffuz sesi kapalıyken dinleme, dikte ve tekrar etme soruları "
                + "hiç sorulmaz — sessiz bir düğmeyle cevaplanamayacak soru kalmasın diye."
            )
        }
    }

    // MARK: - Klipler

    @ViewBuilder
    private var clipSection: some View {
        Section {
            value("İnen ses", clipCountText)
            value("Kapladığı yer", audio.storedSizeText)
            if audio.isDownloading {
                ProgressView(value: min(max(audio.downloadProgress, 0), 1))
                    .tint(Theme.c4)
                    .accessibilityLabel("Ses indirmesi sürüyor")
            } else if audio.missingClipCount > 0 {
                Button("Eksik sesleri indir") { retryDownload() }
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(Theme.c4)
                    .accessibilityLabel("Eksik sesleri indir")
                    .accessibilityHint("\(audio.missingClipCount) ses eksik.")
            }
        } header: {
            header("Ses dosyaları")
        } footer: {
            footer(
                "Klipler bir kez inip cihazda kalıyor; ders sırasında internet gerekmiyor. "
                + "Eksik kalanlar kurs her açıldığında kendiliğinden yeniden deneniyor."
            )
        }
    }

    private var clipCountText: String {
        audio.expectedClipCount > 0
            ? "\(audio.downloadedAudioIds.count) / \(audio.expectedClipCount) klip"
            : "\(audio.downloadedAudioIds.count) klip"
    }

    // MARK: - Bildirimler

    private var notificationSection: some View {
        Section {
            row("Letonca hatırlatmaları", isOn: notificationsBinding,
                hint: "Günlük ders, seri kurtarma ve unutma uyarıları.")
        } header: {
            header("Hatırlatmalar")
        } footer: {
            footer(
                "Hatırlatmalar \(Self.quietWindowText) arasında gönderilmez ve günde en "
                + "fazla iki tanedir. Kapatmak kurulu olanları da siler."
            )
        }
    }

    /// Sessiz saat penceresi kuralın kendisinden yazılıyor; metin sabiti
    /// kuralla ayrışmasın diye.
    private static var quietWindowText: String {
        String(
            format: "%02d:00-%02d:00",
            LatvianNotificationRules.quietStartHour,
            LatvianNotificationRules.quietEndHour
        )
    }

    /// Model'in `notificationsEnabled` alanı `private(set)`: yazma işi
    /// `setNotificationsEnabled` üzerinden gidiyor, çünkü kapatmak kurulu
    /// bildirimleri silmeyi ve açmak izin istemeyi de kapsıyor.
    private var notificationsBinding: Binding<Bool> {
        Binding(
            get: { model.notificationsEnabled },
            set: { model.setNotificationsEnabled($0) }
        )
    }

    // MARK: - İlerleme

    private var progressSection: some View {
        Section {
            value("Gün serisi", "\(model.progress.streakDays) gün")
            value("Toplam XP", "\(model.progress.xp)")
            value("Can", "\(model.progress.hearts) / \(LatvianProgress.maxHearts)")
            value("Geçilen durak", "\(clearedStopCount) / \(model.stops.count)")
            value("Çalışılan kelime", "\(studiedWordCount)")
        } header: {
            header("İlerleme")
        } footer: {
            footer("Bir durak, kelimelerinin %80'i kalıcı olarak öğrenilince geçilmiş sayılır.")
        }
    }

    private var clearedStopCount: Int {
        model.stops.filter(\.isCleared).count
    }

    private var studiedWordCount: Int {
        Set(model.progress.allCards().map(\.key.wordId)).count
    }

    // MARK: - Parçalar

    private func row(_ title: String, isOn: Binding<Bool>, hint: String) -> some View {
        Toggle(isOn: isOn) {
            Text(title)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Theme.text)
        }
        .tint(Theme.ok)
        .listRowBackground(Theme.panel)
        .accessibilityLabel(title)
        .accessibilityHint(hint)
    }

    private func value(_ title: String, _ detail: String) -> some View {
        HStack {
            Text(title)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Theme.text)
            Spacer(minLength: 12)
            Text(detail)
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundStyle(Theme.dim)
                .monospacedDigit()
        }
        .listRowBackground(Theme.panel)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title): \(detail)")
    }

    private func header(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 12, weight: .heavy))
            .foregroundStyle(Theme.muted)
    }

    private func footer(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(Theme.muted)
    }

    private func retryDownload() {
        feedback.tap()
        audio.retryMissingClips()
    }
}

#Preview("Letonca ayarları") {
    LatvianSettingsView(
        model: LatvianCourseModel(),
        audio: LatvianAudioStore(),
        feedback: LatvianFeedback()
    )
}
