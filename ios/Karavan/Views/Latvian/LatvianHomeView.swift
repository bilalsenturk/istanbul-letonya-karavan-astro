import SwiftUI

/// Letonca kursunun ana ekranı: üst çubuk, bilgi şeritleri ve İstanbul'dan
/// Riga'ya uzanan rota haritası.
///
/// Ekranın kendi durumu yok; her şey `LatvianCourseModel`'de ve oradan hazır
/// geliyor. Gövde ne saat okuyor ne hakimiyet hesaplıyor.
struct LatvianHomeView: View {
    @StateObject private var model = LatvianCourseModel()
    @StateObject private var audio = LatvianAudioStore()
    @StateObject private var feedback = LatvianFeedback()

    @Environment(\.scenePhase) private var scenePhase

    @State private var isSettingsPresented = false

    /// Can dolumunun ekranda beklerken de görülmesi için tazeleme aralığı.
    private static let heartTick: Duration = .seconds(60)

    var body: some View {
        ZStack {
            Theme.bg.ignoresSafeArea()
            if let message = model.loadError {
                errorState(message)
            } else {
                content
            }
        }
        .task { await model.load(audio: audio) }
        .task { await tickHearts() }
        .onChange(of: scenePhase) { _, phase in
            // Uygulama arkadayken geçen saatler de can getiriyor.
            if phase == .active { model.refreshHearts() }
        }
        .fullScreenCover(isPresented: flowPresentation) {
            LatvianLessonFlowView(model: model, audio: audio, feedback: feedback)
        }
        .sheet(isPresented: $isSettingsPresented) {
            LatvianSettingsView(model: model, audio: audio, feedback: feedback)
        }
    }

    // MARK: - İçerik

    private var content: some View {
        VStack(spacing: 0) {
            LatvianTopBar(
                streakDays: model.progress.streakDays,
                hearts: model.progress.hearts,
                xp: model.progress.xp,
                isDailyGoalDone: model.isDailyGoalDone,
                onOpenSettings: openSettings
            )
            banners
            ScrollView {
                LatvianRouteMap(
                    stops: model.stops,
                    currentStopId: model.currentStopId,
                    onSelect: select
                )
                .padding(.vertical, 24)
            }
        }
    }

    @ViewBuilder
    private var banners: some View {
        let storage = storageMessage
        let audioError = audio.lastError

        if storage != nil || audioError != nil || audio.isDownloading
            || model.actionNotice != nil || model.nextHeartAt != nil {
            VStack(spacing: 8) {
                if let storage {
                    LatvianNoticeBanner(
                        symbol: "externaldrive.badge.exclamationmark",
                        message: storage,
                        tone: Theme.warn
                    )
                }
                if audio.isDownloading {
                    LatvianDownloadBanner(progress: audio.downloadProgress)
                }
                if let audioError {
                    LatvianNoticeBanner(
                        symbol: "speaker.slash.fill",
                        message: audioError,
                        tone: Theme.warn,
                        onDismiss: audio.dismissError
                    )
                }
                if let notice = model.actionNotice {
                    LatvianNoticeBanner(
                        symbol: "heart.slash.fill",
                        message: notice,
                        tone: Theme.bad,
                        onDismiss: model.dismissActionNotice
                    )
                } else if let moment = model.nextHeartAt {
                    LatvianNoticeBanner(
                        symbol: "heart.fill",
                        message: "Sonraki can \(moment.formatted(date: .omitted, time: .shortened)) civarında geliyor.",
                        tone: Theme.c1
                    )
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 10)
        }
    }

    private var storageMessage: String? {
        switch model.storage {
        case .ok: return nil
        case .recovered: return "İlerleme dosyası okunamadı, yedekten devam ediliyor."
        case .reset: return "İlerleme dosyası okunamadı ve yedeği de yoktu; sıfırdan başlanıyor."
        case .saveFailed: return "İlerleme diske yazılamadı. Cihazda yer açıp tekrar dene."
        }
    }

    private func errorState(_ message: String) -> some View {
        VStack(spacing: 14) {
            LatvianMascot(mood: .wrong, size: 88)
            Text("Letonca kursu açılamadı")
                .font(.system(size: 19, weight: .heavy, design: .rounded))
                .foregroundStyle(Theme.text)
                .accessibilityAddTraits(.isHeader)
            Text(message)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Theme.dim)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 40)
        }
    }

    // MARK: - Eylemler

    private var flowPresentation: Binding<Bool> {
        Binding(
            get: { model.isLessonFlowPresented },
            set: { if !$0 { model.dismissFlow() } }
        )
    }

    private func select(_ stop: LatvianRouteStop) {
        feedback.tap()
        model.startLesson(sceneId: stop.id, audio: audio)
    }

    private func openSettings() {
        feedback.tap()
        isSettingsPresented = true
    }

    /// `.task` ekran kaybolunca iptal ediliyor, dolayısıyla döngü de duruyor.
    private func tickHearts() async {
        while !Task.isCancelled {
            do {
                try await Task.sleep(for: Self.heartTick)
            } catch {
                return
            }
            model.refreshHearts()
        }
    }
}

/// Tam ekran ders akışı: önce sorular, sonra kutlama — tek bir kapak içinde.
///
/// İkisi ayrı `fullScreenCover` olsaydı, ders bitince aynı karede biri kapanıp
/// öbürü açılacaktı ve SwiftUI ikincisini sessizce düşürürdü; can biten öğrenci
/// hiçbir açıklama görmeden haritaya dönerdi.
private struct LatvianLessonFlowView: View {
    @ObservedObject var model: LatvianCourseModel
    @ObservedObject var audio: LatvianAudioStore
    @ObservedObject var feedback: LatvianFeedback

    var body: some View {
        ZStack {
            Theme.bg.ignoresSafeArea()
            if let celebration = model.celebration {
                LatvianLessonCompleteView(
                    xp: celebration.xp,
                    accuracy: celebration.accuracy,
                    streakDays: celebration.streakDays,
                    streakExtended: celebration.streakExtended,
                    isFailed: celebration.isFailed,
                    feedback: feedback,
                    onDone: { model.dismissFlow() }
                )
            } else if let lesson = model.lesson {
                LatvianLessonView(
                    exercises: lesson.exercises,
                    audio: audio,
                    feedback: feedback,
                    onFinish: { outcome in model.finish(outcome) }
                )
                .id(lesson.id)
            }
        }
        .preferredColorScheme(.dark)
    }
}
