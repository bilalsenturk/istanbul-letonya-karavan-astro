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
| `livePostSecret` | Web'e konum gönderme anahtarı — Vercel'deki `LIVE_POST_SECRET` ile aynı olmalı |

## Apple hesabı ve çoklu rotalar

- Uygulama `Sign in with Apple` ile açılır; erişim ve yenileme tokenları Keychain'de tutulur.
- Her kullanıcı yeni rota oluşturabilir. Harita araması, mevcut konum ve haritaya uzun basma ile durak eklenir.
- Rota sahibi başka Apple hesaplarını `Üye` veya `Görüntüleyen` olarak davet eder.
- `Üye` durakları düzenler; `Görüntüleyen` yalnızca okur. Son sahip kaldırılamaz.
- Letonca kursu ve Kuzey müziği yalnızca `Leyla'nın Kuzey Yolculuğu` içinde görünür.

## Web tarafında canlı konum için (bir kere)

Vercel projesinde:
1. **Storage → Blob** etkinleştir (`BLOB_READ_WRITE_TOKEN` otomatik oluşur)
2. **Settings → Environment Variables** → `LIVE_POST_SECRET` = `Config.livePostSecret` ile aynı değer

App konum iznini alınca 60 sn'de bir `POST /api/location` çağırır; site ana sayfadaki **"Karavan Nerede?"** kartı bunu okur.

## Sürüm yayınlama (TestFlight)

Uygulama açılışta (ve öne gelişte, en sık 6 saatte bir) sitedeki `/kuzey-version.json` manifest'ini okur; güncel `latestBuild` kurulu sürümden yüksekse Panel'in üstünde güncelleme banner'ı gösterir. Yeni TestFlight build'i yükleyince:

1. `public/kuzey-version.json`'da **`latestBuild`**'i yeni `CURRENT_PROJECT_VERSION` (`project.yml`) değerine çek — site deploy olunca aktif olur
2. **`testflightURL`**'deki `XXXXXX` yer tutucusunu App Store Connect → TestFlight → herkese açık davet linkiyle değiştir (bir kere; link her build için aynıdır)
3. Eski sürümlerin güncellemesi **zorunluysa** `minBuild`'i de yeni numaraya çek — banner kapatılamaz hâle gelir

Dürüst not: iOS, uygulamanın kendi kendini güncellemesine izin vermez — uygulama yalnızca **haber verir**, kurulumu TestFlight yapar. Her cihazda TestFlight → Kuzey → **Otomatik Güncelleme** açıksa yeni build zaten kendiliğinden kurulur; banner yedek güvencedir.

## Projeyi yeniden üretme

```sh
cd ios && xcodegen generate
```
