# İstanbul → Riga Karavan Yolculuğu

Astro ile oluşturulmuş karavan yolculuğu brifing ve takip panosu.

## Yolculuk

- **Güzergâh:** İstanbul → Sofya → Bükreş → Deva → Budapeşte → Katowice → Suwałki → Riga
- **Tarih:** 3–10 Ağustos 2026
- **Araç:** VW Passat 1.6 TDI + Adria karavan
- **Toplam:** ~3.150 km

## Proje Yapısı

```
src/
├── components/
│   ├── CameraPlayer.astro   # Şehir kamerası oynatıcı
│   └── RouteMap.astro       # Leaflet interaktif rota haritası
├── data/
│   ├── tripData.json        # Tüm yolculuk verileri
│   └── tripData.ts          # TypeScript tipleri
├── layouts/
│   └── MainLayout.astro     # Ana sayfa düzeni
├── pages/
│   ├── index.astro          # Kontrol paneli
│   └── day/[slug].astro     # Günlük detay sayfaları
└── scripts/
    └── routeMap.ts          # Leaflet harita başlatma
```

## Komutlar

| Komut | Açıklama |
|-------|----------|
| `npm run dev` | Geliştirme sunucusu (`localhost:4321`) |
| `npm run build` | Üretim build'i (`dist/`) |
| `npm run preview` | Build önizlemesi |
| `npm run lint` | ESLint ile kod kontrolü |
| `npm run format` | Prettier ile formatlama |
| `npm run check` | TypeScript tip kontrolü |

## Hesap ve rota altyapısı

iOS uygulaması Apple ile giriş yapar. Astro `/api/v2` uçları erişim tokenını
`Authorization: Bearer <access-token>` başlığından doğrular; süresi dolan token tek bir
yenileme isteğiyle döndürülür ve Keychain'de saklanır. Hesap, oturum, rota ve yayın
durumu Vercel Private Blob'da tutulur. İstemcide gömülü ortak bir yayın sırrı yoktur.

| Ortam değişkeni | Amaç |
|---|---|
| `AUTH_SESSION_SECRET` | Kuzey erişim ve yenileme tokenlarını imzalar; en az 32 bayt rastgele değer olmalı |
| `PRIVATE_BLOB_READ_WRITE_TOKEN` | Özel Blob deposu için tercih edilen token |
| `BLOB_READ_WRITE_TOKEN` | Vercel'in eklediği Blob tokenı; özel token verilmezse yedek olarak kullanılır |

Üretimde özel Blob tokenı yoksa hesap API'si veri yazmaz. Yerel geliştirmede hesap deposu yalnızca süreç belleğine düşer ve sunucu yeniden başlayınca temizlenir.

### Korumalı v2 uçları

Aşağıdaki çağrıların tamamı Bearer oturumu ve rota rolü/yetkisi ister. `{id}`, URL'deki
seçili rota kimliğidir; gövdedeki bir rota kimliği depolama hedefini değiştiremez.

| URL | Metot | Amaç |
|---|---|---|
| `/api/v2/me` | `GET`, `PATCH` | Hesap, seyahat profili ve erişilebilen rotalar |
| `/api/v2/trips` | `GET`, `POST` | Rotaları listeleme ve standart rota oluşturma |
| `/api/v2/trips/{id}` | `GET`, `PATCH` | Rota okuma ve temel alanları güncelleme |
| `/api/v2/trips/{id}/members` | `GET`, `POST`, `PATCH`, `DELETE` | Üyelik ve davet yönetimi |
| `/api/v2/trips/{id}/stops` | `POST`, `PATCH`, `DELETE` | Durak yönetimi |
| `/api/v2/trips/{id}/live-location` | `PUT` | Canlı konum görünümünü yayınlama |
| `/api/v2/trips/{id}/expense-summary` | `PUT` | Hesap bazlı harcama özetini yayınlama |
| `/api/v2/trips/{id}/published-plan` | `PUT` | Hesaplanan plan görünümünü yayınlama |
| `/api/v2/trips/{id}/shared-journal` | `PUT` | Paylaşılan günlük katkısını yayınlama |
| `/api/v2/trips/{id}/plan-edits` | `GET`, `PUT` | Revizyonlu plan düzenleme senkronu |

### Herkese açık v2 okuma uçları

Yalnızca `publicTracking` özelliği açık `kuzey2026` rotaları okunabilir. Yanıtlar özel
zarfı, ETag'i ve hesap kimliklerini içermez; bütün dinamik JSON yanıtları `no-store`'dur.

| URL | Metot | Görünüm |
|---|---|---|
| `/api/v2/public/trips/{id}/live-location` | `GET` | Canlı konum |
| `/api/v2/public/trips/{id}/expense-summary` | `GET` | Birleştirilmiş harcama özeti |
| `/api/v2/public/trips/{id}/published-plan` | `GET` | Yayınlanmış takvim |
| `/api/v2/public/trips/{id}/shared-journal` | `GET` | Paylaşılabilir günlük girdileri |

Özel Blob yolları hesaplar için `accounts/users/{userId}.json`, oturumlar için
`accounts/sessions/{sessionId}.json`, rota olayları için
`accounts/trips/{tripId}/events/{revision}.json` ve yayın durumu için
`accounts/trips/{tripId}/state/{resource}.json` biçimindedir. Eski `baseRevision` ya
da eşzamanlı yazma çakışmaları `409` (plan düzenlemelerinde güncel durumla), alan ve
iş kuralı doğrulama hataları `422` döner.

## Yapılan İyileştirmeler

- Veri (JSON) ve tipler (TS) ayrıştırıldı
- Leaflet npm paketi ile CDN bağımlılığı kaldırıldı
- Sitemap, robots.txt ve PWA eklendi
- ESLint + Prettier yapılandırması
- Tarih tekilleştirme, setInterval cleanup, responsive iyileştirmeler
