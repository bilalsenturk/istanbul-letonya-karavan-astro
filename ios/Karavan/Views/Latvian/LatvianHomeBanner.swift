import SwiftUI

/// Ana ekranın üstünde duran tek satırlık bilgi şeridi.
///
/// Sessiz kalmamak için var: paket yedeğe düştüğünde, ses inmediğinde ya da
/// canlar bittiğinde öğrenci ne olduğunu ve ne yapabileceğini Türkçe okuyor.
struct LatvianNoticeBanner: View {
    let symbol: String
    let message: String
    let tone: Color
    /// Verilirse sağda bir kapatma düğmesi çıkıyor.
    var onDismiss: (() -> Void)?

    var body: some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(tone)
                .padding(.top, 1)
            Text(message)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.dim)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            if let onDismiss {
                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Theme.muted)
                        .padding(4)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Uyarıyı kapat")
            }
        }
        .padding(11)
        .background(Theme.panel, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(tone.opacity(0.35), lineWidth: 1)
        )
    }
}

/// Ses indirme şeridi. Ders **beklemeden** başlatılabildiği için metin bunu
/// açıkça söylüyor; motor eksik klipte o kelimeyi dinleme sorusu olmadan
/// çalıştırıyor.
struct LatvianDownloadBanner: View {
    /// 0-1.
    let progress: Double

    private var percent: Int { Int((min(max(progress, 0), 1) * 100).rounded()) }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 7) {
                Image(systemName: "arrow.down.circle.fill")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Theme.c4)
                Text("Letonca sesleri iniyor · %\(percent)")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Theme.dim)
                Spacer(minLength: 0)
            }
            ProgressView(value: min(max(progress, 0), 1))
                .tint(Theme.c4)
            Text("Beklemeden başlayabilirsin.")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Theme.muted)
        }
        .padding(11)
        .background(Theme.panel, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Theme.line, lineWidth: 1)
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Letonca sesleri iniyor, yüzde \(percent). Beklemeden başlayabilirsin.")
    }
}

/// "Öğrendin ama daha oturmadı" şeridi — yol arkadaşının ağzından.
///
/// Halka artık kısmi ilerlemeyi gösteriyor ama **neden** durduğunu söyleyemiyor:
/// kalıcılık yalnızca tekrarların arasına zaman girdiğinde büyüyor, dolayısıyla bir
/// akşamda altı kusursuz ders yapan öğrenci durağı yine açamıyor. Kural doğru; ekranın
/// susması yanlıştı (ölçüm: `.superpowers/sdd/p3-task-7-report.md`).
///
/// Metin dışarıdan geliyor ve durumdan türetiliyor (`LatvianCourseRules.restNotice`);
/// burada sabit bir cümle yok.
///
/// Kapatma düğmesi bilerek yok: uyarı değil durum bildirimi, ve durum ortadan kalktığı
/// anda şerit kendiliğinden kayboluyor.
struct LatvianRestBanner: View {
    let message: String

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            // Maskotun kendi erişilebilirlik metni kapatıldı: şeridin tamamı tek bir
            // öğe olarak okunuyor, yoksa VoiceOver aynı şeyi iki kez söylerdi.
            LatvianMascot(mood: .idle, size: 40)
                .accessibilityHidden(true)
            Text(message)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.dim)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(11)
        .background(Theme.panel, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Theme.c4.opacity(0.35), lineWidth: 1)
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Yol arkadaşın diyor ki: \(message)")
    }
}

#Preview("Şeritler") {
    VStack(spacing: 10) {
        LatvianDownloadBanner(progress: 0.42)
        LatvianRestBanner(
            message: "Bugünlük tamam. 23 kelime demleniyor: kalıcı sayılmaları için "
                + "araya zaman girmeli. En erken yarın 09:12 civarında geri gelecekler."
        )
        LatvianNoticeBanner(
            symbol: "exclamationmark.triangle.fill",
            message: "İlerleme dosyası okunamadı, yedekten devam ediliyor.",
            tone: Theme.warn
        )
        LatvianNoticeBanner(
            symbol: "heart.slash.fill",
            message: "Canların bitti. Sonraki can 14:20 civarında geliyor.",
            tone: Theme.bad,
            onDismiss: {}
        )
    }
    .padding(20)
    .frame(maxHeight: .infinity)
    .background(Theme.bg)
}
