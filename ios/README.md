# Kuzey — iOS Uygulaması (SwiftUI)

İstanbul → Riga yolculuğunun **native iOS dashboard'u**. iPhone ve iPad'de çalışır; App Store gerekmez, kendi cihazlarına Xcode ile kurulur.

## Özellikler

- **3 sekme:** Panel (geri sayım + canlı konum + hava) · Harita (tam ekran etkileşimli) · Plan (gün gün timeline)
- **Canlı geri sayım** — gün : saat : dk : sn
- **Canlı konum — sunucusuz** — cihaz GPS'i: Riga'ya kalan km, en yakın durak, anlık hız
- **Gerçek navigasyon** — her durak/gün için tek dokunuşla **Apple Maps** veya **Google Maps** sürüş rotası
- **Native hava durumu** — 8 durak, SF Symbols ikonlarıyla (Open-Meteo, anahtarsız)
- **Web'e canlı yayın** — konum 60 sn'de bir siteye gönderilir; site "Karavan Nerede?" kartında gösterir
- **Kendini güncelleyen içerik** — veri, sitedeki `/trip-data.json`'dan tazelenir; çevrimdışıysa gömülü kopya

## Kurulum (kendi cihazına)

1. `ios/Kuzey.xcodeproj`'u Xcode ile aç
2. **Kuzey** target → **Signing & Capabilities** → **Team** olarak Apple ID'ni seç
3. iPhone/iPad'ini bağla, cihazı seç, **⌘R**
4. Cihazda: Ayarlar → Genel → VPN ve Aygıt Yönetimi → sertifikana güven

> Ücretsiz Apple ID ile kurulum **7 gün** geçerli (tekrar ⌘R yeterli). Yolculuk 8 gün — çıkmadan hemen önce kur.

## Yapılandırma — `Karavan/Config.swift`

| Sabit | Ne işe yarar |
|---|---|
| `siteURL` | Deploy edilen site (veri + canlı konum hedefi) |
| `accountAPIBaseURL` | Apple oturumu ve rota kapsamlı `/api/v2` isteklerinin kökü |

## Apple hesabı ve çoklu rotalar

- Uygulama `Sign in with Apple` ile açılır; erişim ve yenileme tokenları Keychain'de tutulur.
- Korumalı çağrılar `Authorization: Bearer <access-token>` kullanır. Sunucu `401`
  döndürürse tek bir ortak yenileme işlemi tokenları döndürür ve istek bir kez yinelenir.
- Her kullanıcı yeni rota oluşturabilir. Harita araması, mevcut konum ve haritaya uzun basma ile durak eklenir.
- Rota sahibi başka Apple hesaplarını `Üye` veya `Görüntüleyen` olarak davet eder.
- `Üye` durakları düzenler; `Görüntüleyen` yalnızca okur. Son sahip kaldırılamaz.
- Letonca kursu ve Kuzey müziği yalnızca `Leyla'nın Kuzey Yolculuğu` içinde görünür.

## Web yayın senkronu

Vercel projesinde:
1. **Storage → Blob** etkinleştir (`BLOB_READ_WRITE_TOKEN` otomatik oluşur).
2. En az 32 bayt rastgele bir `AUTH_SESSION_SECRET` tanımla.

İstemcide gömülü ortak bir yayın sırrı yoktur. `BearerSessionCoordinator`, seçili
`kuzey2026` rota kimliğiyle aşağıdaki korumalı URL'lere gider:

| URL | Metot | Veri |
|---|---|---|
| `/api/v2/trips/{id}/live-location` | `PUT` | Canlı konum ve rota ilerlemesi |
| `/api/v2/trips/{id}/expense-summary` | `PUT` | Yalnızca toplam/kategori özeti; harcama kalemleri cihazda kalır |
| `/api/v2/trips/{id}/published-plan` | `PUT` | Hesaplanan takvim görünümü |
| `/api/v2/trips/{id}/shared-journal` | `PUT` | Paylaşılabilir günlük katkısı |
| `/api/v2/trips/{id}/plan-edits` | `GET`, `PUT` | Revizyonlu plan düzenlemeleri |

Başarısız yayınlar `PublishOutbox` içinde rota kimliği, kaynak adı ve gövdeyle atomik
olarak saklanır; URL, token veya başka kimlik bilgisi diske yazılmaz. Eski revizyon
`409` döndürür ve istemci sunucunun güncel planıyla üç yönlü birleştirme yapar. Alan
ve iş kuralı doğrulama hataları `422` döner.

Site yalnızca aşağıdaki herkese açık, salt-okunur projeksiyonları kullanır; plan
düzenlemeleri hiçbir zaman herkese açılmaz.

| URL | Metot |
|---|---|
| `/api/v2/public/trips/kuzey-2026/live-location` | `GET` |
| `/api/v2/public/trips/kuzey-2026/expense-summary` | `GET` |
| `/api/v2/public/trips/kuzey-2026/published-plan` | `GET` |
| `/api/v2/public/trips/kuzey-2026/shared-journal` | `GET` |

Sunucuda yayın zarfları özel Blob deposunda
`accounts/trips/{tripId}/state/{resource}.json` yolunda tutulur; herkese açık yanıtlar
ETag, hesap kimliği ve özel zarf alanlarını çıkarır.

## Sürüm yayınlama (TestFlight)

Uygulama açılışta (ve öne gelişte, en sık 6 saatte bir) sitedeki `/kuzey-version.json` manifest'ini okur; güncel `latestBuild` kurulu sürümden yüksekse Panel'in üstünde güncelleme banner'ı gösterir. Yeni TestFlight build'i yükleyince:

1. `public/kuzey-version.json`'da **`latestBuild`**'i yeni `CURRENT_PROJECT_VERSION` (`project.yml`) değerine çek — site deploy olunca aktif olur
2. **`testflightURL`** isteğe bağlıdır; harici test grubu varsa App Store Connect'teki herkese açık davet linkini, yalnız iç test kullanılıyorsa TestFlight ana bağlantısını kullan
3. Eski sürümlerin güncellemesi **zorunluysa** `minBuild`'i de yeni numaraya çek — banner kapatılamaz hâle gelir

Dürüst not: iOS, uygulamanın kendi kendini güncellemesine izin vermez — uygulama yalnızca **haber verir**, kurulumu TestFlight yapar. Her cihazda TestFlight → Kuzey → **Otomatik Güncelleme** açıksa yeni build zaten kendiliğinden kurulur; banner yedek güvencedir.

## Projeyi yeniden üretme

```sh
cd ios && xcodegen generate
```
