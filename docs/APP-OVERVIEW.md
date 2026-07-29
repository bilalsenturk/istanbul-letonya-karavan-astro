# Kuzey — Tam Özellik Dökümü (AI agent brief)

> Bu belge bir AI agent'ın projeyi sıfırdan anlaması için yazıldı. Her özellik, hangi
> dosyada yaşadığı, hangi framework'ü kullandığı ve hangi sabitlerle çalıştığıyla birlikte.

## 0. Bir cümlede

**Kuzey**, 3–10 Ağustos 2026 tarihli İstanbul → Riga karavan yolculuğu için yazılmış
**iki parçalı** bir sistem: (1) `ios/` altında SwiftUI native iPhone/iPad uygulaması —
yolculuk sırasında kullanılan asıl araç; (2) kök dizindeki **Astro** sitesi — hem içerik
kaynağı (`/trip-data.json`), hem geride kalanların takip ettiği canlı ayna, hem de
uygulamanın yazdığı verinin durduğu ince bir serverless katman (Vercel Blob).

Astro'nun serverless API katmanı Apple ile giriş, Bearer oturumları, rota rolleri ve
özel Vercel Blob depolamasını yönetir. İstemcide gömülü ortak bir yayın sırrı yoktur;
yazma yetkisi her istekte kullanıcı oturumu ve URL'deki rota üzerinden denetlenir.

```
┌─────────────────┐  Bearer + /api/v2/trips/{id}/*       ┌──────────────────┐
│  iOS: Kuzey     │ ────────────────────────────────────► │  Astro / Vercel  │
│  (SwiftUI)      │  GET /trip-data.json, /api/roadfeed  │  + Private Blob  │
│                 │ ◄──────────────────────────────────── │                  │
│  App Group ──►  │                                      │  index.astro     │
│  Widget + Live  │  public /api/v2 projections          │  /day/[slug]     │
│  Activity       │ ◄──────────────────────────────────── │  20s/60s polling │
└─────────────────┘                                       └──────────────────┘
```

---

# BÖLÜM A — iOS uygulaması (`ios/`)

Bundle `com.bilalsenturk.kuzey` · iOS 17+ · Swift 5.9 · App Group
`group.com.bilalsenturk.kuzey` · sadece dark mode · tamamen Türkçe · iPhone portrait,
iPad serbest.

## A1. Ekran haritası

`ContentView` → 4 sekmeli `TabView`:

| Sekme | View | İçerik |
|---|---|---|
| **Panel** | `DashboardView` | Geri sayım (1 Hz `TimelineView`), toplam km/yakıt/gün metrikleri, harcama kartı, canlı konum kartı, mini müzik çubuğu, varış saatleri, yol feed'i (mazot/sınır/kur), hava şeridi. Sheet → `TripSettingsView` |
| **Harita** | `MapScreen` | Tam ekran MapKit, gerçek rota çizgileri, "rotayı başlat" düğmesi, kalan km/süre/hız pilleri. Sheet → `StopExploreView` (Look Around + yakın POI) |
| **Plan** | `PlanScreen` | 8 günlük takvim (iPad'de split view) → `DayDetailView` → `DayEditView`, `DayGalleryView`, `PhotoDetailView` |
| **Araçlar** | `ToolsView` | Fiş tarayıcı, sesli harcama, belge kasası, vinyet takibi, müzik, foto günlüğü, tabela çevirisi, SMS ile konum paylaş |

`Adaptive.swift` iPad'de içeriği iki dengeli kolona böler (`AdaptiveColumns`,
`_VariadicView_MultiViewRoot`), genişliği regular'da 900pt / compact'ta 700pt'a sabitler.

## A2. Uygulama açılışı ve veri akışı

`KaravanApp.swift` — 10 adet `@StateObject` store environment'a enjekte edilir:
`TripStore`, `LocationManager`, `WeatherService`, `ExpenseStore`, `RouteStore`,
`NavProgressStore`, `AltimeterService`, `TripPlanStore`, `GalleryStore`, `RoadFeedService`.

Açılış zinciri (`.task`): bildirim izni → store'ları birbirine bağla → altimetreyi
başlat → galeri/anons/müzik/yol-feed manifestlerini indir → araç bağlantısı callback'ini
kaydet → geofence'leri kur → plan senkronu → arka plan hava görevi planla.

**`applyPlanCascade()`** tek fan-out noktası: kalkış bildirimlerini yeniden kur →
App Group snapshot'ını yaz → widget'ları throttle'lı yenile → **sadece cihaz "sahip"
ise** seçili rota kapsamındaki `published-plan` kaynağını Bearer `PUT` ile yayınla.

`URLCache` 32 MB RAM / 128 MB disk olarak büyütülür (indirilen ses ve görseller
çevrimdışı çalışsın diye).

## A3. Konum, navigasyon ve ilerleme

**`LocationManager`** (CoreLocation, `.automotiveNavigation`)
- **Güç adaptasyonu**: düşük güç modu veya termal durum `.serious`/`.critical` →
  100 m doğruluk + 400 m filtre; normalde 10 m + 100 m.
- **Kademeli izin**: önce WhenInUse, sonra Always (arka planda varış uyarısı için).
- **Geofence**: her durak için 3000 m yarıçaplı `CLCircularRegion`, ilk 20 durakla sınırlı.
  Girişte → yerel bildirim (tüp gaz / elektrik-su / sınır belgeleri hatırlatması) +
  şehre özel varış anonsu + Live Activity'yi kapat.
- **Rota sapması SOS**: sadece hız > 20 km/s iken; 3 ardışık ölçüm ≥ 5 km rota dışıysa
  ve son uyarıdan ≥ 900 s geçtiyse → sesli uyarı + bildirim.
- **Web'e yayın**: en fazla 30 saniyede bir, seçili rota kapsamındaki `live-location`
  kaynağını `PublishOutbox` üzerinden Bearer `PUT` ile gönderir.

**`NavProgressStore`** — canlı ilerleme beyni
- 700 m hareket **veya** 45 s geçmeden yeniden hesaplamaz.
- **Segment tabanlı sonraki durak**: en yakın durağa değil, `[durak_k, durak_k+1]`
  segmentine dik mesafeye bakar (yoksa yeni çıktığın şehri "sıradaki" diye gösteriyordu).
- Kalan km/dk `MKDirections`'tan; yoksa kuş uçuşu × 80 km/s varsayımı.
- **Riga'ya kalan**: sonraki etap sürüşü + kalan etapların toplamı; eksik etaplar
  kuş uçuşu **× 1.25** Avrupa yol katsayısıyla tahmin edilir.
- `arrivals: [StopArrival]` — Riga'ya kadar zincirleme ETA'lar.
- Şehir adı `CLGeocoder` reverse geocode ile.

**`RouteStore`** — her ardışık durak çifti için `MKDirections`; etaplar tek tek
publish edilir (harita parça parça çizilir). Polyline'lar ≤ ~400 noktaya seyreltilir.
Hepsi başarılı olursa `Documents/route-cache.json`'a yazılır → çevrimdışı/sınır
bölgelerinde de rota görünür.

**`LegLauncher`** — "etabı başlat" tek yol: kaptan anonsu → Live Activity başlat →
istenirse Apple Maps'i sürüş modunda aç. `MapScreen` düğmesi ve `DepartureModal` buradan geçer.

**`AppleMapsService`** — Apple Maps'i *veri kaynağı* olarak kullanır: 30×30 km bölgede
`MKLocalSearch` ile kamp/yakıt/yemek/market/şarj POI'leri (mesafeye göre ilk 12) ve
`MKLookAroundSceneRequest` ile sokak görünümü. Konum izni gerektirmez.

## A4. Anons / sesli asistan sistemi (üç katman)

Yeni replik eklemek için **build gerekmiyor** — JSON uzaktan güncelleniyor.

1. **Katalog** (`AnnouncementCatalog.swift`) — `Clip(key, text, lang)`; şehir adı → slug
   eşlemesi; 24 kategori sabiti (captain, ready, morning, rest-reminder, border-ahead,
   deviation, rain-start, storm, crosswind, rough-road, traffic, speed-warning, focus,
   fuel-low, camp-ahead, eta-60/30/10, snack, karaoke, silence, family-council).
2. **Motor** (`AnnouncementEngine.swift`) — `/assets/announcements.json` uzaktan, bundle
   fallback. Seçim kuralları:
   - Aynı metin **12 saat**, aynı kategori **45 dakika** kilitli.
   - `critical` kategoriler (fırtına, rüzgâr, hız, yakıt, sınır, sapma…) bu kilitleri delip geçer.
   - **%4 sürpriz**: kritik olmayan seçimlere rastgele "rare" replik enjekte edilir.
   - Ağırlıklı havuz: kişisel replikler (içinde "Sezin"/"Leyla" geçen) ×25, kaptan ×15, diğer ×55.
   - **Osuruk şakası günde 1 kez** (metinde "pırt" geçiyorsa `annFartDay` ile sayılır).
   - Maks 220 karakter ≈ 12 saniye.
   - Her şey kilitliyse susmaz, en eski repliği çalar.
   - Dil, key son ekinden çıkarılır: `-bg/-ro/-hu/-pl/-lv`, yoksa `tr-TR`.
3. **Çalma** (`AnnouncementService` + `AnnouncementAudio`) — `.playback` + `.duckOthers`;
   konuşurken müzik %25'e kısılır, 400 ms sonra geri açılır. Önce kayıtlı m4a klip
   (manifest'ten, aynı klibi arka arkaya çalmaz, `.returnCacheDataElseLoad` ile çevrimdışı),
   yoksa `AVSpeechSynthesizer`.
   - **Araç algılama**: `routeChangeNotification` → çıkış portu `.carAudio` ise
     kaptan şakası + "Sıradaki durak: X. Hadi başlat!" — CarPlay entitlement'ı gerekmez.
   - Her 100 km barajında ve ≤ 15 km kala ilerleme anonsu.

> **Durum notu:** bugün fiilen tetiklenen kategoriler `captain`, `storm`, `deviation` ve
> varış klipleri. Kalan ~19 kategori katalogda ve JSON'da var ama **tetikleyici kodu yok**.

**Ses üretimi** `tools/generate-voices.mjs` ile: OpenRouter `openai/gpt-audio`,
kategori bazlı ton direktifleri, transkript sadakat kontrolü (hedef metnin ≥%75'i
geçmeliyse kabul, 3 deneme), PCM→WAV→`afconvert` ile 64 kbps AAC. Şu an 186 replik /
560 dosya; `public/audio` gitignore'da, Cloudflare R2'de barınıyor.

## A5. Plan motoru ve çok cihazlı senkron

**`TripPlanner.swift`** — saf, yan etkisiz, bu yüzden unit-test edilebilir.
- `DayEdit`: origin, destination, distanceKm, duration, fuel, note, campName, campPlace,
  isRestDay, `extraDays`, `startHour` — hepsi opsiyonel; `nil` = "web verisini kullan".
- `days()`: kalkış gününden kümülatif offset; `extraDays` sonraki tüm günleri kaydırır;
  dinlenme günü takvim günü tüketir ama **etap tüketmez** (`legCounter` sadece sürüş
  günlerinde artar). Başlangıç saati = edit ?? (0. gün → gerçek kalkış saati, aksi
  halde 08:00), 0…23 arası clamp'lenir.

**`TripPlanStore`** — last-write-wins'i bilerek reddeder: seçili yayın rotasının
`plan-edits` kaynağını Bearer `GET`/`PUT` ile senkronlar. İstek `baseRevision` taşır;
`409` yanıtındaki güncel durumla üç yönlü birleştirme yapılır. Ağ payload'ı ISO-8601,
yerel dosya varsayılan kodlamadır (mevcut cihaz dosyalarını bozmamak için).

**`TripSettingsView`** — sahiplik anahtarı, senkron durumu, kalkış tarihi seçici
(sahip değilse disabled), **canlı önizleme** (tüm günlerin nasıl kaydığı), hesaplanan
Riga varışı, onaylı sıfırlama.

**Testler** — `ios/Tests/run-planner-check.sh`, `swiftc -O` ile derleyip 6 grup assert eder:
temel türetme, +10 günlük kalkış kaydırması, +2 `extraDays` etkisi, dinlenme günü etap
eşlemesi, `DayEdit.isEmpty`, ve sınır durumları (nil trip, negatif extraDays,
`startHour: 99` → 23).

## A6. Harcama takibi

- `Expense(id, amountEur, category, note, date)`; kategoriler **yakit · kamp · yemek ·
  gecis · diger** (her biri SF Symbol + tema rengiyle).
- `Documents/expenses.json`. Web'e **sadece toplam** gider — kalemler cihazda kalır.
- `nonisolated static appendDirect(_:)` sayesinde **App Intent uygulama kapalıyken bile**
  harcama ekleyebilir.
- **Cihaz üstü not önerisi motoru**: geçmiş notları sıklık + tazelik (`1 - yaş/30`) +
  kategori eşleşmesi (+1.6) + prefix (+3) / içerik (+1.5) eşleşmesiyle skorlar, ayrıca
  kronolojik not çiftlerinden öğrenilen **sıra deseni bonusu** (+2.5, "benzin sonra
  atıştırmalık"). `AddExpenseSheet`'te sparkle çipleri olarak çıkar.
- "Ekle ve yeni ekle" hızlı giriş (kategori + tarih korunur), swipe-to-delete,
  kategori kırılımı, bütçe tavanı €1795.

## A7. Widget'lar, Live Activity, Focus

**`SharedSnapshot`** (App Group `UserDefaults`) uygulama ↔ widget köprüsü:
departureAt, nextStop, nextCode, remainingKm, remainingMin, spentEur, budgetMax,
legProgress, currentCity, updatedAt, simpleMode. 3600 s'den eskiyse `isFresh = false`.

| Widget | Aile | Yenileme |
|---|---|---|
| `CountdownWidget` | small, medium, accessoryInline, accessoryRectangular | saatlik timeline + `Text(date, style:.relative)` ile canlı tik |
| `TripStatusWidget` | medium + accessory | 15 dk; sonraki durak, kalan km/süre, etap barı, şehir, €harcanan/€bütçe |
| `TripLiveActivity` | kilit ekranı + Dynamic Island (leading/trailing/bottom/compact/minimal) | push yok, tamamen yerel |

Live Activity **hız > 25 km/s** olunca başlar; aynı duraksa `update`, durak değiştiyse
kapat+yeniden başlat, `staleDate = +30 dk`. Widget yenileme 60 saniyede bire throttle'lı.

**`DrivingFocusFilter`** (`SetFocusFilterIntent`) — Sürüş Focus'u açıldığında App Group'a
`simpleMode` yazar; `DashboardView` metrikleri/harcamayı/varışları/feed'i/havayı gizler,
geriye geri sayım + canlı konum + mini müzik kalır.

**App Intents / Siri**: `AddExpenseIntent` ("Kuzey harcama ekle"), `NextStopIntent`
("Kuzey sıradaki durak", "ne kadar kaldı") — cevabı `SharedSnapshot`'tan sesli okur.

## A8. Sensörler, hava, yol feed'i, bildirimler

- **`AltimeterService`** (CoreMotion `CMAltimeter`) — barometre. **Sadece araç dururken**
  (hız < 5 km/s) çalışan fırtına sezgisi: baz basınçtan **2.0 hPa** düşüş + 3600 s
  bekleme → bildirim + fırtına anonsu. Barometresiz cihazda sessizce devre dışı.
- **`WeatherService`** — Open-Meteo (API anahtarsız), tüm durakların koordinatı tek
  istekte. WMO kodu → SF Symbol + Türkçe açıklama tablosu (21 kod). Yağmur başlangıcı/
  bitişi ve *şiddetli* hava değişimlerinde bildirim; ilk çalıştırmada susar.
  `BGAppRefreshTask` (`…kuzey.weather`, ~2 saatte bir) ile arka planda tazelenir.
- **`RoadFeedService`** — `/api/roadfeed`'den mazot fiyatı + sınır kuyruğu + döviz kuru,
  3 saatte bir. `RoadFeedCard` en ucuz mazotu yeşille işaretler ("burada tam depo mantıklı"),
  Kapıkule bekleme süresini ve sıradaki ülkenin para birimini öne çıkarır.
- **Bildirimler** — kalkış hatırlatmaları idempotent üç kimlikle (`departure-0/1/2`:
  D−1 gün, T−2 saat, T−30 dk) her plan değişiminde yeniden kurulur. Ayrıca geofence
  varışı, rota sapması, fırtına, vinyet bitişi (D−1, 09:00).

## A9. Araçlar sekmesi

| Araç | Framework | Ne yapıyor |
|---|---|---|
| Fiş tarayıcı | VisionKit `DataScannerViewController` | Canlı metin taraması, regex ile tutar adayları (1 ≤ v < 100.000, ilk 6), "dizel/motorin/litre" gibi kelimeler görürse Yakıt kategorisini önseçer → `AddExpenseSheet` prefill |
| Sesli harcama | Speech (`tr-TR`) + `AVAudioEngine` | Anlık kısmi sonuç; tutarı regex, kategoriyi Türkçe kelime kovalarıyla çıkarır; kapanışta `.playback` session'ını geri verir ki anonslar susmasın |
| Belge kasası | LocalAuthentication + VisionKit doc scanner + QuickLook | Face ID / passcode; taramalar `UIGraphicsPDFRenderer` ile PDF; dosyalar `FileProtectionType.complete` ile `Documents/Kasa/` |
| Vinyet takibi | UserNotifications | Ülke bazlı vinyet + bitiş tarihi, kalan gün rozeti, D−1 09:00 hatırlatma |
| Müzik | AVFoundation + MediaPlayer | Manifest'ten indirir, **diskten** çalar (kapsama yokken de çalışsın), shuffle/repeat, kilit ekranı kontrolleri, anons için duck API'si |
| Foto günlüğü | Photos + MapKit | Kalkıştan 30 gün öncesine kadar ≤400 fotoğraf, sadece geo-etiketli olanlar, ilk 150'si haritada pin |
| Tabela çevirisi | VisionKit + `ShareLink` | Taranan metni sistem Translate'e devreder |
| SMS ile konum | `sms:` URL | Site linki + `maps.apple.com/?ll=` + sıradaki durak/km |

## A10. Galeri ve kamp görselleri

`GalleryStore` uzak manifest'ten şehir bazlı fotoğrafları (caption/credit/license ile)
çeker; `DayGalleryView` gün detayında yatay şerit, tam ekran `PhotoDetailView`.
`CampImage` görselleri `Config.imageBaseURL` üzerinden `AsyncImage` ile çeker, hata
halinde sıcak gradyan + çadır placeholder — **görseller IPA'ya gömülmez**, ağdan gelir.

## A11. Tema

`Theme.swift` — arka plan `#07070b`, panel beyaz %5.5, çizgi beyaz %10, aurora rampası
c1 `#ff9a3c` → c2 `#ff4d6d` → c3 `#a24bff` → c4 `#33e0d0`. `card()` modifier (16pt padding,
r18 continuous, 1pt border), `CountryBadge` (emoji bazı fontlarda "?" çizdiği için
ASCII ülke kodu), `MonoLabel`.

---

# BÖLÜM B — Web (Astro + Vercel)

## B1. Yapı

Astro 7, `@astrojs/vercel` adapter, default `static` output — tüm sayfalar build'de
prerender edilir, sadece `src/pages/api/*` (`prerender = false`) serverless function olur.
`@astrojs/sitemap`. Node ≥ 22.12. Leaflet npm'den (CDN bağımlılığı bilerek kaldırıldı).

| Route | Tür | İçerik |
|---|---|---|
| `/` | statik | Kontrol paneli / kokpit |
| `/day/[slug]` | statik ×8 | Günlük operasyon brifingi |
| `/trip-data.json` | statik endpoint | Tüm `tripData`, `max-age=300` — **iOS'un içerik kaynağı** |
| `/api/v2/auth/*`, `/api/v2/me` | serverless | Apple oturumu, token yenileme ve seyahat profili |
| `/api/v2/trips/*` | serverless | Rota, üye, durak ve korumalı yayın yönetimi |
| `/api/v2/public/trips/*` | serverless | Kuzey sitesinin salt-okunur yayın projeksiyonları |
| `/api/roadfeed` | serverless | Mazot + sınır + kur, `max-age=1800` |

## B2. API sözleşmesi

Apple giriş ve token yenileme uçları dışında korumalı v2 istekleri
`Authorization: Bearer <access-token>` taşır. `BearerSessionCoordinator`, aynı anda gelen
`401` yanıtlarını tek bir refresh rotasyonunda birleştirir, isteği bir kez yineler ve
yenilenen tokenları Keychain'e atomik yazar. Sunucu ayrıca oturum kaydını, URL rota
kimliğini ve rolün işlem iznini doğrular; gövdedeki `tripId` depolama hedefi olamaz.

**Korumalı URL'ler:**

| URL | Metot | Sözleşme |
|---|---|---|
| `/api/v2/me` | `GET`, `PATCH` | Hesap, seyahat profili ve erişilebilen rotalar |
| `/api/v2/trips` | `GET`, `POST` | Listeleme ve standart rota oluşturma |
| `/api/v2/trips/{id}` | `GET`, `PATCH` | Rota okuma/güncelleme |
| `/api/v2/trips/{id}/members` | `GET`, `POST`, `PATCH`, `DELETE` | Üye ve davet yönetimi |
| `/api/v2/trips/{id}/stops` | `POST`, `PATCH`, `DELETE` | Durak ekleme, değiştirme, sıralama ve silme |
| `/api/v2/trips/{id}/live-location` | `PUT` | Konum, hız, etap ilerlemesi ve cihaz ölçümleri |
| `/api/v2/trips/{id}/expense-summary` | `PUT` | Hesap katkısı olarak toplam ve kategori özeti; kalemler cihazda kalır |
| `/api/v2/trips/{id}/published-plan` | `PUT` | Maksimum 60 günlük hesaplanan plan görünümü |
| `/api/v2/trips/{id}/shared-journal` | `PUT` | Sunucunun doğruladığı ve hesap adıyla ilişkilendirdiği günlük katkısı |
| `/api/v2/trips/{id}/plan-edits` | `GET`, `PUT` | Özel, revizyonlu ham düzenleme durumu; herkese açık karşılığı yoktur |

**Herkese açık URL'ler:** yalnızca `kind === kuzey2026` ve `publicTracking` açıkken
yanıt verir. Özel durum zarfı, ETag ve katkı hesap kimlikleri dışarı çıkarılmaz.

| URL | Metot | Görünüm |
|---|---|---|
| `/api/v2/public/trips/{id}/live-location` | `GET` | Canlı rota görünümü |
| `/api/v2/public/trips/{id}/expense-summary` | `GET` | Hesap katkılarının anonim toplamı |
| `/api/v2/public/trips/{id}/published-plan` | `GET` | Yayınlanmış takvim |
| `/api/v2/public/trips/{id}/shared-journal` | `GET` | Düzleştirilmiş paylaşılabilir günlük |

Tüm v2 JSON yanıtları `Cache-Control: no-store` taşır. `401` geçersiz/iptal edilmiş
oturumu, `403` rol yetkisi eksikliğini, `404` bulunmayan veya herkese açık olmayan
rotayı belirtir. Eski `baseRevision` ve eşzamanlı yazma çakışmaları `409` döner;
plan düzenleme yanıtı istemcinin birleştirmesi için `current` alanını taşır. Rota alanı
ve iş kuralı doğrulama hataları `422`, bozuk JSON ise `400` döner.

**Özel Blob yolları:**

| Veri | Yol |
|---|---|
| Hesap | `accounts/users/{userId}.json` |
| Seyahat profili geçmişi | `accounts/profiles/{userId}/revisions/{timestamp}-{revisionId}.json` |
| Oturum | `accounts/sessions/{sessionId}.json` |
| Rota olayları | `accounts/trips/{tripId}/events/{revision}.json` |
| Yayın durumu | `accounts/trips/{tripId}/state/{resource}.json` |

Blob erişimi önce `PRIVATE_BLOB_READ_WRITE_TOKEN`, yoksa `BLOB_READ_WRITE_TOKEN`
kullanır. Üretimde ikisi de yoksa kapalı davranır; geliştirmede yalnızca süreç belleği
fallback'i vardır. İstemcinin bilmesi veya saklaması gereken ortak bir sunucu sırrı yoktur.

## B3. Ana sayfa (`index.astro`, 637 satır)

Bölümler: hero (3 görsel crossfade + geri sayım + canlı şerit) → 4 metrik kartı
(Yolculuk Özeti / Karavan Nerede? / Kalan Hedefler / Harcanan) → `#hava` → `#harita` →
`#ulkeler` (9 ülke rehberi) → `#etaplar` (7 segment) → `#strateji` (kahve/yemek/kamp
mantığı) → `#plan` (8 günlük timeline).

İnline script (`define:vars` ile):
- **Geri sayım** 1 s, T-0'da "🚐 Yoldayız!"
- **`pollLive()` 20 s** → `/api/v2/public/trips/kuzey-2026/live-location`. Sunucu `remainingToFinalKm` yolladıysa onu
  kullanır, yoksa haversine × 1.25 (düz çizgi tek başına 3300 km'lik rotayı 1800 gösteriyordu).
  Şehir, sonraki durak, ilerleme barı, hız, kat edilen km günceller; durak listesinde
  `is-next`/`is-passed` işaretler.
- **`pollPlan()` 60 s** → `/api/v2/public/trips/kuzey-2026/published-plan`. Kalkış tarihini ve her günün etiketini
  (`CSS.escape` ile `data-day-slug` eşleşmesi) yeniden yazar; `dayCount > 1` ise "· N gün" ekler.
- **`pollSpend()` 60 s** → `/api/v2/public/trips/kuzey-2026/expense-summary` → €X + bütçe yüzdesi.
- Hepsi `pagehide`'da temizlenir. Service worker **sadece burada** register edilir.

## B4. Gün sayfası (`/day/[slug]`)

8 slug: `istanbul-sofya`, `sofya-bukres`, `bukres-deva`, `deva-budapest`,
`budapest-dinlenme` (dinlenme), `budapest-katowice`, `katowice-suwalki`, `suwalki-riga`.

İçerik: başlık + mesafe/süre/yakıt etiketleri + `RouteStepper` → o güne odaklı
`RouteMap` → kamp bloğu (hero görsel, iletişim, telefon/e-posta, **hazır rezervasyon
şablonu**, alternatif kamp kartları) → Google Maps canlı trafik/rota derin linkleri →
riskler / fırsatlar / B planları → segment brifingi + ülke akordeonları → yol üstü
duraklar → şehir kameraları → varış sonrası kartları → önceki/sonraki gün.

## B5. Bileşenler

| Bileşen | Ne yapıyor |
|---|---|
| `RouteMap.astro` + `scripts/routeMap.ts` | Leaflet + OSM tile. Önce **anında kesikli düz çizgi** çizer, sonra `/assets/route-geometry.json`'ı yükleyip gerçek yol geometrisini (koyu casing + renkli üst çizgi, popup'ta km/sa) çizer. Aktif etap vurgulanır. Leaflet'in klasik "sıfır boyut" bug'ına karşı `requestAnimationFrame` + `load` + `resize` + `ResizeObserver` + `IntersectionObserver` beşli refit. JS yüklenmezse `staticmap.openstreetmap.de` fallback görseli kalır |
| `RouteStepper.astro` | Saf CSS ilerleme rayı, done/active/todo düğümler, ülke bayrakları |
| `WeatherStrip.astro` | Tek batch Open-Meteo çağrısı, 30 kodluk WMO → emoji + Türkçe tablo, yağmurda `.wx--rain`; sayfa yüklenince bir kez, polling yok |
| `CameraPlayer.astro` | 3 mod: `video` (iframe), `image` (cache-bust'lı auto-refresh, 45–180 s clamp, 4 hatada mesaj / 8 hatada durur), `web` (framing engelli kaynaklar için sadece link) |
| `MainLayout.astro` (1522 satır) | Tüm tasarım sistemi: dark + light CSS değişkenleri, aurora animasyonlu arka plan, FOUC'suz tema bootstrap'ı, Fontshare fontları (Clash Display / General Sans / JetBrains Mono), topbar + mobil menü, PWA meta |

## B6. Trip veri modeli (`src/data/tripData.json`, 1352 satır)

```ts
type TripData = {
  departureAt: string;            // "2026-08-03T05:00:00+03:00"
  vehicle: { plate; model; description; towing };   // 34 SC 2441 TR · VW Passat 2016 1.6 TDI
  totalKm: 3150;
  totalBudget: { min: 1345; max: 1795; fuel: "€520–590"; total: string };
  checklist: { id; due; task }[];                   // 10 — web'de HİÇ render edilmiyor, app kullanıyor
  postArrival: { when; title; text }[];             // 6
  countryGuides: CountryGuide[];                    // 9 (Slovakya/Çekya/Litvanya sadece transit)
  segmentGuides: { segment; from; to; highlights[]; netComment }[];  // 7
  coffeeStrategy / mealStrategy / campLogic;        // strateji metinleri
  stops: RouteStop[];                               // 8 — harita, stepper, hava, OSRM hepsi buradan
  routeGuide: { city; from; to; distance; reason }[];
  days: DayPlan[];                                  // 8
};
```

**8 durak:** İstanbul → Sofya → Bükreş → Deva → Budapeşte → Katowice → Suwałki → Riga.

**`DayPlan`**: `{ id, slug, date, origin, destination, distanceKm, duration, fuel,
risks[], opportunities[], contingencies[], camp, stops[], route, routeEmbed,
trafficEmbed, trafficLabel, cityCameras[] }`.

> Dikkat: `distanceKm`, `duration`, `fuel` **sayı değil, gösterim string'i**
> ("540–560 km", "8–10 saat + sınır", "65–75 L · €95–115"). Bu yüzden `index.astro`
> zorluk seviyesi için regex ile parse ediyor.

`camp`: isim, yer, iletişim, e-posta, telefon, link, **Türkçe rezervasyon şablonu**,
görsel ve 1–2 alternatif. 24 yol üstü durak (Petrol/Kahve/Görülecek/Tedarik).
15 şehir kamerası (hepsi `kind: "image"`, Windy still-frame'leri).

Dinlenme günü UI'da `day.origin === day.destination` ile tespit ediliyor.

## B7. PWA

`manifest.webmanifest` — "Kuzey — Letonya Yolculuğu", standalone, `#07070b`, 192/512 +
maskable ikonlar. `sw.js` (`trip-cache-v11`): navigasyonlar **network-first**, hash'li
Astro dosyaları **cache-first**; API'ler, manifest, gezi verisi, sürüm manifest'i ve
service worker'ın kendisi **network-only**. `no-store` yanıtları Cache API'ye yazılmaz.

## B8. Build araçları (`tools/`)

| Script | Ne yapıyor |
|---|---|
| `build-route-geometry.mjs` | OSRM'den gerçek yol geometrisi çeker, tek geometriyi durak bazlı etaplara böler, her etabı ≤ ~1400/(n-1) noktaya seyreltir, `public/assets/route-geometry.json` yazar (~28.5 KB). **Manuel adım** — `npm run build`'e bağlı değil, duraklar değişince elle çalıştırılmalı |
| `generate-voices.mjs` | Anons seslerini üretir (bkz. A4). `--voice --model --only --limit --dry-run`. Artımlı: mevcut dosyaları atlar, her klipte manifest'i yeniden yazar, kredi biterse temiz mesajla durur |
| `upload-r2.sh` | `public/audio` (+ `WITH_IMAGES=1` ile galeri/kamp görselleri) → Cloudflare R2, `wrangler` ile |
| `testflight.sh` | Tek komut sürüm: build numarasını bump → `xcodegen generate` → archive → export → `altool --upload-app` |

---

# BÖLÜM C — Bir agent'ın bilmesi gereken tuzaklar

1. **`src/components/LiveDashboard.astro` (433 satır) ölü kod** ve içinde altı adet
   uydurma trafik uyarısı üreten `generateMockTraffic()` var. Hiçbir yerden import
   edilmiyor; **mount edilmemeli** — uydurma veriyi canlıymış gibi gösterir.
2. **Herkese açık v2 projeksiyonları bilinçli olarak kimlik doğrulamaz.** Yeni kaynak
   eklerken `publicTracking` kontrolü, açık allowlist ve özel zarf/hesap alanı sızıntı
   testleri birlikte güncellenmeli; `plan-edits` özel kalmalıdır.
3. **Site yalnızca `/api/v2/public/trips/kuzey-2026/*` URL'lerini okumalıdır.** iOS
   yayınları ve plan senkronu korumalı rota kapsamından geçer; istemciye ortak sunucu
   kimlik bilgisi eklenmemelidir.
4. **`tripData.ts:173` runtime doğrulaması olmadan `as TripData` cast'liyor** — şema
   kayması ancak render sırasında patlar.
5. **`route-geometry.json` duraklar değişince elle yeniden üretilmeli**, yoksa harita
   sessizce eski yolu çizer.
6. **`tools/testflight.sh` içinde App Store Connect key/issuer ID'leri varsayılanlıdır**
   (env ile override edilebilir; özel anahtar dosyası repoya girmez).
7. **`ToolsView.swift` SMS gövdesinde site URL'i `Config`'ten değil, elle yazılmış.**
8. **Anons kategorilerinin çoğunun tetikleyicisi yok** — JSON'da replik var ama kod
   onları hiç çağırmıyor (en büyük "hazır ama bağlanmamış" alan).
9. Kaynak yolculuk görsellerinden bazıları megabayt ölçeğindedir; Astro build'i AVIF/WebP
   varyantları üretir ve `check:web-output` üretim çıktısına büyük PNG kaçmasını engeller.

---

# BÖLÜM D — Sabitler hızlı referansı

`URLCache 32/128 MB` · kalkış kontrolü 60 s, pencere 120 dk, erteleme 15 dk ·
nav yeniden hesap 700 m / 45 s · fallback hız 80 km/s · dolambaç katsayısı 1.25 ·
geofence 3000 m, maks 20 · sapma 5 km × 3 örnek, 900 s cooldown, hız > 20 km/s ·
Live Activity başlangıç 25 km/s, staleDate 30 dk · widget throttle 60 s ·
konum POST throttle 30 s · roadfeed 3 sa · arka plan hava ~2 sa ·
fırtına ΔP 2.0 hPa / 3600 s · anons 12 sa metin / 45 dk kategori / %4 rare /
220 karakter / günde 1 osuruk · müzik duck %25 · polyline ≤ 400 nokta ·
POI 30 km / 12 sonuç · foto 400 çekim / 150 pin · bütçe tavanı €1795 ·
web polling 20 s (konum) / 60 s (plan, harcama) · widget timeline 1 sa / 15 dk
